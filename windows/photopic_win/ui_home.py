"""Home & Session Manager PySide6 view for PhotoPic Windows."""

from __future__ import annotations

from pathlib import Path
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QFileDialog,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from .design_system import AppColors, AppSpacing
from .models import PhotoSession
from .session_manager import SessionFileManager


class HomeDashboardWidget(QWidget):
    def __init__(self, on_open_session, on_change_root, on_open_hardware_settings=None, parent=None) -> None:
        super().__init__(parent)
        self.on_open_session = on_open_session
        self.on_change_root = on_change_root
        self.on_open_hardware_settings = on_open_hardware_settings
        self.root_dir: Path | None = None

        root_layout = QVBoxLayout(self)
        root_layout.setContentsMargins(0, 0, 0, 0)
        root_layout.setSpacing(0)

        self._top_bar = QFrame()
        self._top_bar.setObjectName("TopBar")
        self._top_bar.setFixedHeight(52)
        bar_layout = QHBoxLayout(self._top_bar)
        bar_layout.setContentsMargins(AppSpacing.LG, 0, AppSpacing.LG, 0)

        title = QLabel("PhotoPic")
        title.setStyleSheet("font-size: 15px; font-weight: 600;")
        self._root_label = QLabel("Sin carpeta raíz")
        self._root_label.setStyleSheet(f"color: {AppColors.TEXT_TERTIARY}; font-size: 11px;")

        title_col = QVBoxLayout()
        title_col.setSpacing(1)
        title_col.addWidget(title)
        title_col.addWidget(self._root_label)
        bar_layout.addLayout(title_col)
        bar_layout.addStretch()

        self._device_pill = QLabel("● Esperando cámara USB / WPD...")
        self._device_pill.setStyleSheet(
            f"background: {AppColors.ELEVATED_SURFACE}; border: 1px solid {AppColors.BORDER_SUBTLE}; "
            "border-radius: 12px; padding: 5px 12px; font-size: 12px;"
        )
        bar_layout.addWidget(self._device_pill)

        change_root_btn = QPushButton("Carpeta Raíz...")
        change_root_btn.clicked.connect(self._pick_root)
        bar_layout.addWidget(change_root_btn)

        if self.on_open_hardware_settings is not None:
            hw_btn = QPushButton("Rendimiento e IA...")
            hw_btn.clicked.connect(self.on_open_hardware_settings)
            bar_layout.addWidget(hw_btn)

        help_btn = QPushButton("Ayuda (?)")
        help_btn.clicked.connect(self._open_help)
        bar_layout.addWidget(help_btn)

        root_layout.addWidget(self._top_bar)

        header = QHBoxLayout()
        header.setContentsMargins(AppSpacing.XL, AppSpacing.XL, AppSpacing.XL, AppSpacing.MD)
        h_text = QLabel("Sesiones de Estudio")
        h_text.setStyleSheet("font-size: 22px; font-weight: 600;")
        header.addWidget(h_text)
        header.addStretch()

        refresh_btn = QPushButton("Actualizar")
        refresh_btn.clicked.connect(self.reload_sessions)
        header.addWidget(refresh_btn)

        new_btn = QPushButton("+ Nueva Sesión de Filtrado")
        new_btn.setObjectName("PrimaryButton")
        new_btn.clicked.connect(self._create_new_session)
        header.addWidget(new_btn)
        root_layout.addLayout(header)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        self._grid_container = QWidget()
        self._grid = QGridLayout(self._grid_container)
        self._grid.setContentsMargins(AppSpacing.XL, AppSpacing.SM, AppSpacing.XL, AppSpacing.XL)
        self._grid.setSpacing(AppSpacing.MD)
        scroll.setWidget(self._grid_container)
        root_layout.addWidget(scroll)

    def set_root_folder(self, root_dir: Path) -> None:
        self.root_dir = root_dir
        self._root_label.setText(str(root_dir))
        self.reload_sessions()

    def update_live_device_text(self, text: str, live: bool) -> None:
        color = AppColors.APPROVE_GREEN if live else AppColors.TEXT_TERTIARY
        self._device_pill.setText(f"<span style='color:{color};'>●</span> {text}")

    def reload_sessions(self) -> None:
        while self._grid.count():
            item = self._grid.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        if self.root_dir is None:
            return

        sessions = SessionFileManager.load_sessions(self.root_dir)
        if not sessions:
            empty = QLabel("Todavía no hay sesiones. Creá una con '+ Nueva Sesión de Filtrado'.")
            empty.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; padding: 36px;")
            empty.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self._grid.addWidget(empty, 0, 0)
            return

        for idx, session in enumerate(sessions):
            card = self._build_session_card(session)
            self._grid.addWidget(card, idx // 3, idx % 3)

    def _build_session_card(self, session: PhotoSession) -> QFrame:
        card = QFrame()
        card.setObjectName("PanelSurface")
        layout = QVBoxLayout(card)
        layout.setContentsMargins(AppSpacing.LG, AppSpacing.LG, AppSpacing.LG, AppSpacing.LG)
        layout.setSpacing(AppSpacing.MD)

        name_lbl = QLabel(session.name)
        name_lbl.setStyleSheet("font-size: 14px; font-weight: 600;")
        layout.addWidget(name_lbl)

        counts = QLabel(
            f"Pendientes: {session.counts.pending}  ·  "
            f"Para Edición: {session.counts.for_editing}  ·  "
            f"Archivadas: {session.counts.archived}"
        )
        counts.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 12px;")
        layout.addWidget(counts)

        open_btn = QPushButton("Abrir Estudio")
        open_btn.clicked.connect(lambda _=False, s=session: self.on_open_session(s))
        layout.addWidget(open_btn)
        return card

    def _pick_root(self) -> None:
        chosen = QFileDialog.getExistingDirectory(self, "Elegir Carpeta Raíz Global")
        if chosen:
            self.on_change_root(Path(chosen))

    def _open_help(self) -> None:
        from .ui_help_dialog import HelpCenterDialog
        HelpCenterDialog(parent=self).exec()

    def _create_new_session(self) -> None:
        if self.root_dir is None:
            self._pick_root()
            return
        name, ok = QInputDialog.getText(self, "Nueva Sesión de Filtrado", "Nombre de la sesión:")
        if ok and name.strip():
            created = SessionFileManager.create_session(name.strip(), self.root_dir)
            self.reload_sessions()
            self.on_open_session(created)
