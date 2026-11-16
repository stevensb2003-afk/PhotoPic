"""Main entrypoint for PhotoPic Windows 10/11 desktop app."""

from __future__ import annotations

import json
from pathlib import Path
import sys

from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QApplication, QMainWindow, QStackedWidget

from .design_system import build_darkroom_stylesheet, resolve_asset_path
from .models import PhotoSession
from .ui_home import HomeDashboardWidget
from .ui_workspace import SessionWorkspaceWidget
from .wpd_tether_service import WindowsTetherService


class _BridgeSignals(QObject):
    file_staged = Signal(object, str, object)
    devices_updated = Signal(object)


class PhotoPicMainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("PhotoPic — Tethering USB y Culling RAW con IA")
        self.resize(1360, 860)

        icon_path = resolve_asset_path("assets/AppIcon.ico")
        if icon_path.exists():
            self.setWindowIcon(QIcon(str(icon_path)))

        self._signals = _BridgeSignals()
        self.tether_service = WindowsTetherService(
            on_file_staged=lambda p, n, prof: self._signals.file_staged.emit(p, n, prof),
            on_devices_changed=lambda devs: self._signals.devices_updated.emit(devs),
        )
        self._signals.file_staged.connect(self._on_file_staged)
        self._signals.devices_updated.connect(self._on_devices_updated)

        self._stack = QStackedWidget()
        self._home = HomeDashboardWidget(on_open_session=self.open_session, on_change_root=self.set_root_folder)
        self._workspace: SessionWorkspaceWidget | None = None
        self._stack.addWidget(self._home)
        self.setCentralWidget(self._stack)

        default_root = self._load_saved_root() or (Path.home() / "Pictures" / "Sesiones_PhotoPic")
        default_root.mkdir(parents=True, exist_ok=True)
        self.set_root_folder(default_root)
        self.tether_service.start()

    def set_root_folder(self, folder: Path) -> None:
        folder.mkdir(parents=True, exist_ok=True)
        cfg_file = Path.home() / ".photopic_windows.json"
        cfg_file.write_text(json.dumps({"root_folder": str(folder)}), encoding="utf-8")
        self._home.set_root_folder(folder)

    def _load_saved_root(self) -> Path | None:
        cfg_file = Path.home() / ".photopic_windows.json"
        if not cfg_file.exists():
            return None
        try:
            raw = json.loads(cfg_file.read_text(encoding="utf-8"))
            p = Path(raw.get("root_folder", ""))
            return p if p.exists() else None
        except Exception:
            return None

    def open_session(self, session: PhotoSession) -> None:
        if self._workspace is not None:
            self._stack.removeWidget(self._workspace)
            self._workspace.deleteLater()
        self._workspace = SessionWorkspaceWidget(session, self.tether_service, on_back=self.close_session)
        self._stack.addWidget(self._workspace)
        self._stack.setCurrentWidget(self._workspace)
        self._workspace.setFocus()

    def close_session(self) -> None:
        self._stack.setCurrentWidget(self._home)
        self._home.reload_sessions()

    def _on_file_staged(self, path: Path, filename: str, profile) -> None:
        if self._workspace is not None:
            self._workspace.handle_staged_file(path, filename, profile)

    def _on_devices_updated(self, devices: list) -> None:
        if devices:
            self._home.update_live_device_text(f"{devices[0].name} · {devices[0].status_label}", True)
        else:
            self._home.update_live_device_text("Esperando cámara USB / WPD...", False)

    def closeEvent(self, event) -> None:
        self.tether_service.stop()
        super().closeEvent(event)


def main() -> int:
    app = QApplication(sys.argv)
    app.setStyleSheet(build_darkroom_stylesheet())
    win = PhotoPicMainWindow()
    win.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
