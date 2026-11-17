"""Cloud OTA update top banner & Settings section widgets for PhotoPic Windows."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QCheckBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .cloud_updater import CloudAutoUpdaterWin, CloudUpdateEventWin
from .design_system import AppColors, AppSpacing


class CloudUpdateBannerWidget(QFrame):
    """Subtle studio top banner shown when a GitHub Cloud update is downloading or ready."""

    def __init__(self, on_install_now, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.on_install_now = on_install_now
        self.setVisible(False)
        self.setStyleSheet(
            f"background: {AppColors.PANEL_SURFACE}; border-bottom: 1px solid {AppColors.BORDER_STRONG};"
        )
        lay = QHBoxLayout(self)
        lay.setContentsMargins(AppSpacing.LG, 6, AppSpacing.LG, 6)
        lay.setSpacing(AppSpacing.MD)

        self._dot = QLabel("●")
        self._dot.setStyleSheet(f"color: {AppColors.INFO_BLUE}; font-size: 12px;")
        self._msg = QLabel("")
        self._msg.setStyleSheet(f"color: {AppColors.TEXT_PRIMARY}; font-size: 12px; font-weight: 500;")

        self._install_btn = QPushButton("Actualizar y Reiniciar")
        self._install_btn.setObjectName("ApproveButton")
        self._install_btn.setVisible(False)
        self._install_btn.clicked.connect(self.on_install_now)

        self._dismiss_btn = QPushButton("Más tarde")
        self._dismiss_btn.setVisible(False)
        self._dismiss_btn.clicked.connect(lambda: self.setVisible(False))

        lay.addWidget(self._dot)
        lay.addWidget(self._msg, stretch=1)
        lay.addWidget(self._install_btn)
        lay.addWidget(self._dismiss_btn)

    def apply_event(self, event: CloudUpdateEventWin) -> None:
        if event.kind == "downloading":
            self._dot.setStyleSheet(f"color: {AppColors.INFO_BLUE};")
            self._msg.setText(event.message)
            self._install_btn.setVisible(False)
            self._dismiss_btn.setVisible(False)
            self.setVisible(True)
        elif event.kind == "ready":
            self._dot.setStyleSheet(f"color: {AppColors.APPROVE_GREEN};")
            notes = f" — {event.release_notes}" if event.release_notes else ""
            self._msg.setText(f"Nueva versión v{event.version} descargada desde GitHub Cloud{notes}")
            self._install_btn.setVisible(True)
            self._dismiss_btn.setVisible(True)
            self.setVisible(True)
        elif event.kind == "up_to_date":
            self._install_btn.setVisible(False)


class CloudUpdateSettingsSection(QFrame):
    """Settings card for checking GitHub Cloud updates and toggling auto-updates."""

    def __init__(self, updater: CloudAutoUpdaterWin, auto_check_enabled: bool, on_install_now, parent=None) -> None:
        super().__init__(parent)
        self.updater = updater
        self.setObjectName("PanelSurface")
        lay = QVBoxLayout(self)
        lay.setContentsMargins(AppSpacing.LG, AppSpacing.MD, AppSpacing.LG, AppSpacing.MD)
        lay.setSpacing(AppSpacing.XS)

        top = QHBoxLayout()
        title = QLabel("Actualizaciones Automáticas (Nube GitHub)")
        title.setStyleSheet("font-weight: 600; font-size: 13px;")
        ver = QLabel(f"v{updater.identity.version} · build {updater.identity.build_number}")
        ver.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 11px;")
        top.addWidget(title)
        top.addStretch()
        top.addWidget(ver)
        lay.addLayout(top)

        self._chk_auto = QCheckBox("Buscar y descargar actualizaciones automáticamente desde GitHub Cloud")
        self._chk_auto.setChecked(auto_check_enabled)
        lay.addWidget(self._chk_auto)

        row = QHBoxLayout()
        self._status = QLabel("Conectado a github.com/stevensb2003-afk/PhotoPic/releases")
        self._status.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 11px;")
        self._check_btn = QPushButton("Buscar actualizaciones")
        self._check_btn.clicked.connect(lambda: updater.check_async(user_initiated=True))
        self._apply_btn = QPushButton("Instalar y Reiniciar")
        self._apply_btn.setObjectName("ApproveButton")
        self._apply_btn.setVisible(False)
        self._apply_btn.clicked.connect(on_install_now)
        row.addWidget(self._status, stretch=1)
        row.addWidget(self._check_btn)
        row.addWidget(self._apply_btn)
        lay.addLayout(row)

    @property
    def auto_check_checked(self) -> bool:
        return self._chk_auto.isChecked()

    def apply_event(self, event: CloudUpdateEventWin) -> None:
        self._status.setText(event.message)
        self._apply_btn.setVisible(event.kind == "ready")
