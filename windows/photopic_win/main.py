"""Main entrypoint for PhotoPic Windows 10/11 desktop app."""

from __future__ import annotations

import json
from pathlib import Path
import sys

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QApplication, QMainWindow, QMessageBox, QStackedWidget, QVBoxLayout, QWidget

from .cloud_updater import CloudAutoUpdaterWin
from .design_system import build_darkroom_stylesheet, resolve_asset_path
from .hardware_auditor import HardwareCapabilityAuditor, PerformancePreferences, WindowsConfigStore
from .models import PhotoSession
from .ui_cloud_update import CloudUpdateBannerWidget
from .ui_home import HomeDashboardWidget
from .ui_setup_wizard import GuidedSetupWizardWidget, HardwareSettingsDialog
from .ui_workspace import SessionWorkspaceWidget
from .wpd_tether_service import WindowsTetherService


class _BridgeSignals(QObject):
    file_staged = Signal(object, str, object)
    devices_updated = Signal(object)
    cloud_update_event = Signal(object)


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
        self._signals.cloud_update_event.connect(self._on_cloud_update_event)

        self._config_store = WindowsConfigStore()
        self._hardware_audit = HardwareCapabilityAuditor.audit_host()
        saved_root, self._perf_prefs = self._config_store.load(self._hardware_audit)
        self._active_hw_dialog: HardwareSettingsDialog | None = None

        self._cloud_updater = CloudAutoUpdaterWin(
            on_event=lambda ev: self._signals.cloud_update_event.emit(ev),
            auto_check=self._perf_prefs.auto_check_updates,
        )

        self._update_banner = CloudUpdateBannerWidget(on_install_now=self._install_ready_cloud_update)
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

        shell = QWidget()
        shell_lay = QVBoxLayout(shell)
        shell_lay.setContentsMargins(0, 0, 0, 0)
        shell_lay.setSpacing(0)
        shell_lay.addWidget(self._update_banner)
        shell_lay.addWidget(self._stack, stretch=1)
        self.setCentralWidget(shell)

        if saved_root is not None and self._perf_prefs.has_completed_guided_setup:
            self.set_root_folder(saved_root)
            self._stack.setCurrentWidget(self._home)
        else:
            self._stack.setCurrentWidget(self._wizard)
        self.tether_service.start()

        self._ota_timer = QTimer(self)
        self._ota_timer.setInterval(1_800_000)
        self._ota_timer.timeout.connect(self._periodic_cloud_check)
        if self._perf_prefs.auto_check_updates:
            QTimer.singleShot(3000, self._periodic_cloud_check)
            self._ota_timer.start()

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
        dlg = HardwareSettingsDialog(
            self._hardware_audit,
            self._perf_prefs,
            on_apply=self._apply_performance_prefs,
            updater=self._cloud_updater,
            on_install_update=self._install_ready_cloud_update,
            parent=self,
        )
        self._active_hw_dialog = dlg
        dlg.exec()
        self._active_hw_dialog = None

    def _apply_performance_prefs(self, prefs: PerformancePreferences) -> None:
        self._perf_prefs = prefs
        self._config_store.save(getattr(self, "_root_dir", None), prefs)
        self._cloud_updater.auto_check = prefs.auto_check_updates
        if prefs.auto_check_updates and not self._ota_timer.isActive():
            self._ota_timer.start()
        elif not prefs.auto_check_updates:
            self._ota_timer.stop()
        if self._workspace is not None:
            self._workspace.apply_performance_preferences(prefs)

    def _periodic_cloud_check(self) -> None:
        if self._perf_prefs.auto_check_updates:
            self._cloud_updater.check_async(user_initiated=False)

    def _on_cloud_update_event(self, event) -> None:
        self._update_banner.apply_event(event)
        if self._active_hw_dialog is not None:
            self._active_hw_dialog.forward_update_event(event)

    def _install_ready_cloud_update(self) -> None:
        if self._workspace is not None and self._stack.currentWidget() == self._workspace:
            ans = QMessageBox.question(
                self,
                "Actualizar y Reiniciar PhotoPic",
                "Tenés una sesión abierta. ¿Cerrar el estudio e instalar la nueva versión ahora?",
            )
            if ans != QMessageBox.StandardButton.Yes:
                return
            self.close_session()
        if self._cloud_updater.install_staged_and_restart():
            QApplication.quit()

    def open_session(self, session: PhotoSession, run_vision_ai: bool = False) -> None:
        if self._workspace is not None:
            self._stack.removeWidget(self._workspace)
            self._workspace.deleteLater()
        self._workspace = SessionWorkspaceWidget(
            session,
            self.tether_service,
            on_back=self.close_session,
            performance_prefs=self._perf_prefs,
            run_vision_ai_on_open=run_vision_ai,
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
