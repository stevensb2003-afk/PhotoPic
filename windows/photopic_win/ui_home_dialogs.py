"""Dialogs for creating sessions in Master Groups, editing project tags, and confirming permanent delete."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .design_system import AppColors, AppSpacing
from .models import PhotoSession
from .session_metadata import SessionMetadata

_NEW_GROUP_SENTINEL = "__PHOTOPIC_NEW_GROUP__"


class NewSessionDialog(QDialog):
    def __init__(self, groups: list[str], default_group: str = "", parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Nueva Sesión de Filtrado")
        self.setFixedWidth(450)

        lay = QVBoxLayout(self)
        lay.setSpacing(AppSpacing.MD)

        lay.addWidget(QLabel("Nombre de la sesión:"))
        self._name = QLineEdit()
        self._name.setPlaceholderText("Ej. Nimrod_Y_Katherine")
        lay.addWidget(self._name)

        lay.addWidget(QLabel("Carpeta Máster / Categoría (opcional):"))
        self._group_combo = QComboBox()
        self._group_combo.addItem("Sin grupo (Carpeta Raíz)", "")
        for g in groups:
            self._group_combo.addItem(f"📁 {g}", g)
        self._group_combo.addItem("+ Nueva Carpeta Máster...", _NEW_GROUP_SENTINEL)
        if default_group and default_group in groups:
            self._group_combo.setCurrentIndex(max(0, self._group_combo.findData(default_group)))
        self._group_combo.currentIndexChanged.connect(self._toggle_custom_group)
        lay.addWidget(self._group_combo)

        self._custom_group = QLineEdit()
        self._custom_group.setPlaceholderText("Ej. Sesiones Navideñas 2026")
        self._custom_group.setVisible(False)
        lay.addWidget(self._custom_group)

        lay.addWidget(QLabel("Etiquetas iniciales (opcional, separadas por coma):"))
        self._tags = QLineEdit()
        self._tags.setPlaceholderText("Ej. Navidad, Familia, VIP")
        lay.addWidget(self._tags)

        btns = QHBoxLayout()
        btns.addStretch()
        cancel_btn = QPushButton("Cancelar")
        cancel_btn.clicked.connect(self.reject)
        ok_btn = QPushButton("Crear y Abrir")
        ok_btn.setObjectName("PrimaryButton")
        ok_btn.clicked.connect(self._on_submit)
        btns.addWidget(cancel_btn)
        btns.addWidget(ok_btn)
        lay.addLayout(btns)

    def _toggle_custom_group(self) -> None:
        self._custom_group.setVisible(self._group_combo.currentData() == _NEW_GROUP_SENTINEL)

    def _on_submit(self) -> None:
        if self._name.text().strip():
            self.accept()

    def values(self) -> tuple[str, str | None, list[str]]:
        data = self._group_combo.currentData()
        group = self._custom_group.text().strip() if data == _NEW_GROUP_SENTINEL else str(data or "").strip()
        tags = SessionMetadata.parse_comma_tags(self._tags.text())
        return self._name.text().strip(), (group or None), tags


class SessionOrganizationDialog(QDialog):
    def __init__(self, session: PhotoSession, groups: list[str], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle(f"Organizar · {session.name}")
        self.setFixedWidth(440)

        lay = QVBoxLayout(self)
        lay.setSpacing(AppSpacing.MD)

        lay.addWidget(QLabel("Etiquetas del proyecto (separadas por coma):"))
        self._tags = QLineEdit(", ".join(session.tags))
        self._tags.setPlaceholderText("Ej. Navidad, Estudio, Entregada")
        lay.addWidget(self._tags)

        lay.addWidget(QLabel("Carpeta Máster / Categoría:"))
        self._group_combo = QComboBox()
        self._group_combo.addItem("Sin grupo (Carpeta Raíz)", "")
        for g in groups:
            self._group_combo.addItem(f"📁 {g}", g)
        self._group_combo.addItem("+ Nueva Carpeta Máster...", _NEW_GROUP_SENTINEL)
        if session.group_name and session.group_name in groups:
            self._group_combo.setCurrentIndex(max(0, self._group_combo.findData(session.group_name)))
        self._group_combo.currentIndexChanged.connect(
            lambda: self._custom_group.setVisible(self._group_combo.currentData() == _NEW_GROUP_SENTINEL)
        )
        lay.addWidget(self._group_combo)

        self._custom_group = QLineEdit()
        self._custom_group.setPlaceholderText("Nombre de nueva Carpeta Máster")
        self._custom_group.setVisible(False)
        lay.addWidget(self._custom_group)

        btns = QHBoxLayout()
        btns.addStretch()
        cancel = QPushButton("Cancelar")
        cancel.clicked.connect(self.reject)
        save = QPushButton("Guardar Cambios")
        save.setObjectName("PrimaryButton")
        save.clicked.connect(self.accept)
        btns.addWidget(cancel)
        btns.addWidget(save)
        lay.addLayout(btns)

    def result_values(self) -> tuple[list[str], str | None]:
        data = self._group_combo.currentData()
        group = self._custom_group.text().strip() if data == _NEW_GROUP_SENTINEL else str(data or "").strip()
        return SessionMetadata.parse_comma_tags(self._tags.text()), (group or None)


def confirm_permanent_delete_session(session: PhotoSession, parent: QWidget | None = None) -> bool:
    box = QMessageBox(parent)
    box.setWindowTitle("¿Eliminar proyecto permanentemente?")
    box.setIcon(QMessageBox.Icon.Warning)
    box.setText(f"Se eliminará definitivamente '{session.name}' y todas sus fotos del disco.")
    box.setInformativeText(
        f"Total a borrar: {session.counts.total_all_images} fotos "
        f"(Pendientes: {session.counts.pending} · Para Edición: {session.counts.for_editing} "
        f"· Archivadas: {session.counts.archived})\n\n"
        f"Carpeta: {session.directory}\n"
        "Esta acción NO va a la Papelera ni se puede deshacer."
    )
    delete_btn = box.addButton("Eliminar Permanentemente", QMessageBox.ButtonRole.DestructiveRole)
    box.addButton("Cancelar", QMessageBox.ButtonRole.RejectRole)
    box.exec()
    return box.clickedButton() == delete_btn


def build_session_card(session: PhotoSession, on_open, on_organize, on_delete) -> QFrame:
    card = QFrame()
    card.setObjectName("PanelSurface")
    layout = QVBoxLayout(card)
    layout.setContentsMargins(AppSpacing.LG, AppSpacing.LG, AppSpacing.LG, AppSpacing.LG)
    layout.setSpacing(AppSpacing.SM)

    if session.group_name:
        grp_lbl = QLabel(f"📁 {session.group_name}")
        grp_lbl.setStyleSheet(f"color: {AppColors.INFO_BLUE}; font-size: 11px; font-weight: 600;")
        layout.addWidget(grp_lbl)

    title_row = QHBoxLayout()
    name_lbl = QLabel(session.name)
    name_lbl.setStyleSheet("font-size: 14px; font-weight: 600;")
    title_row.addWidget(name_lbl, stretch=1)
    if session.formatted_duration:
        dur_lbl = QLabel(f"⏱ {session.formatted_duration}")
        dur_lbl.setStyleSheet(f"color: {AppColors.APPROVE_GREEN}; font-size: 11px;")
        title_row.addWidget(dur_lbl)
    layout.addLayout(title_row)

    if session.tags:
        tags_lbl = QLabel("  ".join(f"#{t}" for t in session.tags))
        tags_lbl.setWordWrap(True)
        tags_lbl.setStyleSheet(f"color: {AppColors.INFO_BLUE}; font-size: 11px;")
        layout.addWidget(tags_lbl)

    counts = QLabel(
        f"Pendientes: {session.counts.pending}  ·  "
        f"Para Edición: {session.counts.for_editing}  ·  "
        f"Archivadas: {session.counts.archived}"
    )
    counts.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 12px;")
    layout.addWidget(counts)

    actions = QHBoxLayout()
    open_btn = QPushButton("Abrir")
    open_btn.setObjectName("PrimaryButton")
    open_btn.clicked.connect(lambda _=False, s=session: on_open(s))
    org_btn = QPushButton("Tags / Grupo")
    org_btn.clicked.connect(lambda _=False, s=session: on_organize(s))
    del_btn = QPushButton("Eliminar")
    del_btn.setObjectName("ArchiveButton")
    del_btn.clicked.connect(lambda _=False, s=session: on_delete(s))
    actions.addWidget(open_btn, stretch=1)
    actions.addWidget(org_btn)
    actions.addWidget(del_btn)
    layout.addLayout(actions)
    return card
