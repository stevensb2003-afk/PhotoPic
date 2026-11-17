"""Home & Session Manager PySide6 view for PhotoPic Windows with Master Groups, Tags, Search & Delete."""

from __future__ import annotations

from pathlib import Path
from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QComboBox,
    QFileDialog,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from .design_system import AppColors, AppSpacing
from .models import PhotoSession
from .session_manager import SessionFileManager
from .session_metadata import SessionMetadataStore, create_master_group, load_master_groups
from .ui_home_dialogs import (
    NewSessionDialog,
    SessionOrganizationDialog,
    build_session_card,
    confirm_permanent_delete_session,
)


class HomeDashboardWidget(QWidget):
    def __init__(self, on_open_session, on_change_root, on_open_hardware_settings=None, parent=None) -> None:
        super().__init__(parent)
        self.on_open_session = on_open_session
        self.on_change_root = on_change_root
        self.on_open_hardware_settings = on_open_hardware_settings
        self.root_dir: Path | None = None
        self._all_sessions: list[PhotoSession] = []
        self._groups: list[str] = []

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
        self._last_device_status_text = "Esperando cámara USB / WPD..."
        bar_layout.addWidget(self._device_pill)

        usb_guide_btn = QPushButton("Validar USB...")
        usb_guide_btn.clicked.connect(self._open_connection_validator)
        bar_layout.addWidget(usb_guide_btn)

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
        header.setContentsMargins(AppSpacing.XL, AppSpacing.XL, AppSpacing.XL, AppSpacing.SM)
        h_text = QLabel("Sesiones de Estudio")
        h_text.setStyleSheet("font-size: 22px; font-weight: 600;")
        header.addWidget(h_text)
        header.addStretch()

        new_group_btn = QPushButton("+ Carpeta Máster")
        new_group_btn.clicked.connect(self._create_new_group)
        header.addWidget(new_group_btn)

        refresh_btn = QPushButton("Actualizar")
        refresh_btn.clicked.connect(self.reload_sessions)
        header.addWidget(refresh_btn)

        new_btn = QPushButton("+ Nueva Sesión de Filtrado")
        new_btn.setObjectName("PrimaryButton")
        new_btn.clicked.connect(self._create_new_session)
        header.addWidget(new_btn)
        root_layout.addLayout(header)

        filter_bar = QHBoxLayout()
        filter_bar.setContentsMargins(AppSpacing.XL, 0, AppSpacing.XL, AppSpacing.MD)
        self._search_input = QLineEdit()
        self._search_input.setPlaceholderText("Buscar sesión, carpeta máster o etiqueta...")
        self._search_input.textChanged.connect(self._render_filtered_grid)
        filter_bar.addWidget(self._search_input, stretch=1)

        self._group_filter = QComboBox()
        self._group_filter.currentIndexChanged.connect(self._render_filtered_grid)
        filter_bar.addWidget(self._group_filter)

        self._tag_filter = QComboBox()
        self._tag_filter.currentIndexChanged.connect(self._render_filtered_grid)
        filter_bar.addWidget(self._tag_filter)
        root_layout.addLayout(filter_bar)

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
        self._last_device_status_text = text
        color = AppColors.APPROVE_GREEN if live else AppColors.TEXT_TERTIARY
        self._device_pill.setText(f"<span style='color:{color};'>●</span> {text}")

    def reload_sessions(self) -> None:
        if self.root_dir is None:
            self._all_sessions, self._groups = [], []
        else:
            self._all_sessions = SessionFileManager.load_sessions(self.root_dir)
            self._groups = load_master_groups(self.root_dir)
        self._sync_filter_combos()
        self._render_filtered_grid()

    def _sync_filter_combos(self) -> None:
        prev_group = self._group_filter.currentData()
        prev_tag = self._tag_filter.currentData()

        self._group_filter.blockSignals(True)
        self._group_filter.clear()
        self._group_filter.addItem("Todos los grupos", "__ALL__")
        self._group_filter.addItem("Sin grupo (Raíz)", "__UNGROUPED__")
        for g in self._groups:
            self._group_filter.addItem(f"📁 {g}", g)
        if prev_group is not None and (idx := self._group_filter.findData(prev_group)) >= 0:
            self._group_filter.setCurrentIndex(idx)
        self._group_filter.blockSignals(False)

        tags = sorted({t for s in self._all_sessions for t in s.tags}, key=str.casefold)
        self._tag_filter.blockSignals(True)
        self._tag_filter.clear()
        self._tag_filter.addItem("Todas las etiquetas", "__ALL__")
        for t in tags:
            self._tag_filter.addItem(f"#{t}", t)
        if prev_tag is not None and (tidx := self._tag_filter.findData(prev_tag)) >= 0:
            self._tag_filter.setCurrentIndex(tidx)
        self._tag_filter.blockSignals(False)

    def _filtered_sessions(self) -> list[PhotoSession]:
        q = self._search_input.text().strip().lower()
        gf = self._group_filter.currentData() or "__ALL__"
        tf = self._tag_filter.currentData() or "__ALL__"
        out: list[PhotoSession] = []
        for s in self._all_sessions:
            if gf == "__UNGROUPED__" and s.group_name is not None:
                continue
            if gf not in ("__ALL__", "__UNGROUPED__") and (s.group_name or "").lower() != str(gf).lower():
                continue
            if tf != "__ALL__" and all(t.lower() != str(tf).lower() for t in s.tags):
                continue
            if q:
                hay = f"{s.name} {s.group_name or ''} {' '.join(s.tags)}".lower()
                if q not in hay:
                    continue
            out.append(s)
        return out

    def _render_filtered_grid(self) -> None:
        while self._grid.count():
            item = self._grid.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        if self.root_dir is None:
            return
        sessions = self._filtered_sessions()
        if not sessions:
            msg = (
                "Todavía no hay sesiones. Creá una con '+ Nueva Sesión de Filtrado'."
                if not self._all_sessions
                else "Ninguna sesión coincide con tu búsqueda o filtros actuales."
            )
            empty = QLabel(msg)
            empty.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; padding: 36px;")
            empty.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self._grid.addWidget(empty, 0, 0)
            return

        for idx, session in enumerate(sessions):
            card = build_session_card(session, self.on_open_session, self._organize_session, self._delete_session)
            self._grid.addWidget(card, idx // 3, idx % 3)

    def _pick_root(self) -> None:
        chosen = QFileDialog.getExistingDirectory(self, "Elegir Carpeta Raíz Global")
        if chosen:
            self.on_change_root(Path(chosen))

    def _open_help(self) -> None:
        from .ui_help_dialog import HelpCenterDialog
        HelpCenterDialog(parent=self).exec()

    def _open_connection_validator(self) -> None:
        from .ui_connection_guide import ConnectionValidatorDialog
        ConnectionValidatorDialog(self._last_device_status_text, parent=self).exec()

    def _create_new_group(self) -> None:
        if self.root_dir is None:
            self._pick_root()
            return
        name, ok = QInputDialog.getText(self, "Nueva Carpeta Máster", "Nombre del grupo (ej. Sesiones Navideñas 2026):")
        if ok and name.strip():
            create_master_group(name.strip(), self.root_dir)
            self.reload_sessions()

    def _create_new_session(self) -> None:
        if self.root_dir is None:
            self._pick_root()
            return
        active_group = str(self._group_filter.currentData() or "")
        default_g = "" if active_group in ("__ALL__", "__UNGROUPED__") else active_group
        dlg = NewSessionDialog(self._groups, default_group=default_g, parent=self)
        if dlg.exec():
            name, group, tags = dlg.values()
            created = SessionFileManager.create_session(name, self.root_dir, group_name=group, initial_tags=tags)
            self.reload_sessions()
            self.on_open_session(created)

    def _organize_session(self, session: PhotoSession) -> None:
        if self.root_dir is None:
            return
        dlg = SessionOrganizationDialog(session, self._groups, parent=self)
        if dlg.exec():
            tags, target_group = dlg.result_values()
            meta = SessionMetadataStore.load(session.directory)
            meta.tags = tags
            SessionMetadataStore.save(meta, session.directory)
            SessionFileManager.move_session_to_group(session, target_group, self.root_dir)
            self.reload_sessions()

    def _delete_session(self, session: PhotoSession) -> None:
        if self.root_dir is None:
            return
        if confirm_permanent_delete_session(session, parent=self):
            try:
                SessionFileManager.permanently_delete_session(session, self.root_dir)
                self.reload_sessions()
            except Exception as exc:
                QMessageBox.critical(self, "Error al eliminar", str(exc))
