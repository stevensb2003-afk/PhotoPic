"""Main entrypoint for PhotoPic Windows 10/11 desktop app."""

from __future__ import annotations

import json
from pathlib import Path
import sys

from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QApplication, QMainWindow, QStackedWidget

from .design_system import build_darkroom_stylesheet, resolve_asset_path
from .hardware_auditor import HardwareCapabilityAuditor, PerformancePreferences, WindowsConfigStore
from .models import PhotoSession
from .ui_home import HomeDashboardWidget
from .ui_setup_wizard import GuidedSetupWizardWidget, HardwareSettingsDialog
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

        self._config_store = WindowsConfigStore()
        self._hardware_audit = HardwareCapabilityAuditor.audit_host()
        saved_root, self._perf_prefs = self._config_store.load(self._hardware_audit)

        self._stack = QStackedWidget()
        self._home = HomeDashboardWidget(
            on_open_session=self.open_session,
            on_change_root=self.set_root_folder,
            on_open_hardware_settings=self._open_hardware_settings,
        )
        self._workspace: SessionWorkspaceWidget | None = None
        self._wizard = GuidedSetupWizardWidget(
            self._hardware_audit,
            self._perf_prefs,
            on_complete=self._finish_guided_setup,
        )
        self._stack.addWidget(self._wizard)
        self._stack.addWidget(self._home)
        self.setCentralWidget(self._stack)

        if saved_root is not None and self._perf_prefs.has_completed_guided_setup:
            self.set_root_folder(saved_root)
            self._stack.setCurrentWidget(self._home)
        else:
            self._stack.setCurrentWidget(self._wizard)
        self.tether_service.start()

    def set_root_folder(self, folder: Path) -> None:
        folder.mkdir(parents=True, exist_ok=True)
        self._root_dir = folder
        self._config_store.save(folder, self._perf_prefs)
        self._home.set_root_folder(folder)

    def _finish_guided_setup(self, folder: Path, prefs: PerformancePreferences) -> None:
        self._perf_prefs = prefs
        self.set_root_folder(folder)
        self._stack.setCurrentWidget(self._home)

    def _open_hardware_settings(self) -> None:
        HardwareSettingsDialog(
            self._hardware_audit,
            self._perf_prefs,
            on_apply=self._apply_performance_prefs,
            parent=self,
        ).exec()

    def _apply_performance_prefs(self, prefs: PerformancePreferences) -> None:
        self._perf_prefs = prefs
        self._config_store.save(getattr(self, "_root_dir", None), prefs)
        if self._workspace is not None:
            self._workspace.apply_performance_preferences(prefs)

    def open_session(self, session: PhotoSession) -> None:
        if self._workspace is not None:
            self._stack.removeWidget(self._workspace)
            self._workspace.deleteLater()
        self._workspace = SessionWorkspaceWidget(
            session,
            self.tether_service,
            on_back=self.close_session,
            performance_prefs=self._perf_prefs,
        )
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
