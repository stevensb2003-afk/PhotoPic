"""Dialogs for creating sessions in Master Groups, editing project tags, and confirming permanent delete."""

from __future__ import annotations

from pathlib import Path
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QFileDialog,
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
from .folder_importer import FolderImportScanSummary, FolderImportTransferMode, SessionFolderImporter
from .models import PhotoSession
from .session_metadata import SessionMetadata, suggested_imported_session_name

_NEW_GROUP_SENTINEL = "__PHOTOPIC_NEW_GROUP__"


class NewSessionDialog(QDialog):
    def __init__(self, groups: list[str], default_group: str = "", parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Nueva sesión")
        self.setFixedWidth(450)

        lay = QVBoxLayout(self)
        lay.setSpacing(AppSpacing.MD)

        lay.addWidget(QLabel("Nombre de la sesión:"))
        self._name = QLineEdit()
        self._name.setPlaceholderText("Ej. Nimrod_Y_Katherine")
        lay.addWidget(self._name)

        lay.addWidget(QLabel("Grupo (opcional):"))
        self._group_combo = QComboBox()
        self._group_combo.addItem("Sin grupo", "")
        for g in groups:
            self._group_combo.addItem(f"📁 {g}", g)
        self._group_combo.addItem("+ Nuevo grupo...", _NEW_GROUP_SENTINEL)
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


class ImportSessionDialog(QDialog):
    """Modal dialog to import an existing Windows folder, segregate RAW/JPG, and trigger batch Vision AI."""

    def __init__(
        self,
        source_dir: Path,
        groups: list[str],
        default_group: str = "",
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("Importar carpeta como sesión")
        self.setFixedWidth(520)
        self._source_dir = source_dir
        self._summary: FolderImportScanSummary | None = None

        lay = QVBoxLayout(self)
        lay.setSpacing(AppSpacing.MD)

        src_row = QHBoxLayout()
        self._source_label = QLabel(str(source_dir))
        self._source_label.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 11px;")
        change_btn = QPushButton("Cambiar...")
        change_btn.clicked.connect(self._change_folder)
        src_row.addWidget(self._source_label, stretch=1)
        src_row.addWidget(change_btn)
        lay.addLayout(src_row)

        self._summary_label = QLabel("Escaneando...")
        self._summary_label.setWordWrap(True)
        self._summary_label.setStyleSheet(
            f"background: {AppColors.ELEVATED_SURFACE}; border: 1px solid {AppColors.BORDER_SUBTLE}; "
            "border-radius: 8px; padding: 8px 10px; font-size: 12px;"
        )
        lay.addWidget(self._summary_label)

        lay.addWidget(QLabel("Nombre de la sesión:"))
        self._name = QLineEdit(suggested_imported_session_name(source_dir))
        lay.addWidget(self._name)

        lay.addWidget(QLabel("Grupo (opcional):"))
        self._group_combo = QComboBox()
        self._group_combo.addItem("Sin grupo", "")
        for g in groups:
            self._group_combo.addItem(f"📁 {g}", g)
        self._group_combo.addItem("+ Nuevo grupo...", _NEW_GROUP_SENTINEL)
        if default_group and default_group in groups:
            self._group_combo.setCurrentIndex(max(0, self._group_combo.findData(default_group)))
        self._group_combo.currentIndexChanged.connect(
            lambda: self._custom_group.setVisible(self._group_combo.currentData() == _NEW_GROUP_SENTINEL)
        )
        lay.addWidget(self._group_combo)

        self._custom_group = QLineEdit()
        self._custom_group.setPlaceholderText("Ej. Bodas 2026")
        self._custom_group.setVisible(False)
        lay.addWidget(self._custom_group)

        lay.addWidget(QLabel("Etiquetas iniciales (opcional, separadas por coma):"))
        self._tags = QLineEdit()
        self._tags.setPlaceholderText("Ej. Cliente, Retratos, Exterior")
        lay.addWidget(self._tags)

        lay.addWidget(QLabel("Cómo acomodar los archivos:"))
        self._mode_combo = QComboBox()
        self._mode_combo.addItem("Copiar archivos (seguro)", FolderImportTransferMode.COPY)
        self._mode_combo.addItem("Mover originales", FolderImportTransferMode.MOVE)
        lay.addWidget(self._mode_combo)

        self._subfolders_chk = QCheckBox("Incluir fotos dentro de subcarpetas")
        self._subfolders_chk.setChecked(True)
        self._subfolders_chk.toggled.connect(self._rescan)
        lay.addWidget(self._subfolders_chk)

        self._vision_chk = QCheckBox("Detectar rostros, ojos cerrados y poses con IA al abrir")
        self._vision_chk.setChecked(True)
        lay.addWidget(self._vision_chk)

        btns = QHBoxLayout()
        btns.addStretch()
        cancel = QPushButton("Cancelar")
        cancel.clicked.connect(self.reject)
        self._ok_btn = QPushButton("Importar y abrir sesión")
        self._ok_btn.setObjectName("PrimaryButton")
        self._ok_btn.clicked.connect(self._on_submit)
        btns.addWidget(cancel)
        btns.addWidget(self._ok_btn)
        lay.addLayout(btns)

        self._rescan()

    def _change_folder(self) -> None:
        chosen = QFileDialog.getExistingDirectory(self, "Cambiar carpeta origen")
        if chosen:
            self._source_dir = Path(chosen)
            self._source_label.setText(str(self._source_dir))
            self._name.setText(suggested_imported_session_name(self._source_dir))
            self._rescan()

    def _rescan(self) -> None:
        try:
            summary = SessionFolderImporter.scan_folder(
                self._source_dir, include_subfolders=self._subfolders_chk.isChecked()
            )
            self._summary = summary
            exts = "  ".join(f".{ext}×{cnt}" for ext, cnt in summary.extension_breakdown[:6])
            self._summary_label.setText(
                f"Tomas: {summary.total_photo_units_count}  ·  "
                f"RAW → RAW/: {summary.raw_units_count}  ·  "
                f"Pares → JPG/: {summary.paired_jpg_count}  ·  "
                f"Otros → Filtrar: {summary.standalone_compressed_count}"
                + (f"\n{exts}" if exts else "")
            )
            self._ok_btn.setEnabled(summary.total_photo_units_count > 0)
        except Exception as exc:
            self._summary = None
            self._summary_label.setText(str(exc))
            self._ok_btn.setEnabled(False)

    def _on_submit(self) -> None:
        if self._summary and self._summary.units and self._name.text().strip():
            self.accept()

    def values(self) -> tuple[FolderImportScanSummary, str, str | None, list[str], FolderImportTransferMode, bool]:
        assert self._summary is not None
        data = self._group_combo.currentData()
        group = self._custom_group.text().strip() if data == _NEW_GROUP_SENTINEL else str(data or "").strip()
        tags = SessionMetadata.parse_comma_tags(self._tags.text())
        mode = self._mode_combo.currentData() or FolderImportTransferMode.COPY
        return self._summary, self._name.text().strip(), (group or None), tags, mode, self._vision_chk.isChecked()


def build_group_card(group_name: str, session_count: int, on_open, on_rename) -> QFrame:
    card = QFrame()
    card.setObjectName("PanelSurface")
    lay = QHBoxLayout(card)
    lay.setContentsMargins(AppSpacing.LG, AppSpacing.MD, AppSpacing.LG, AppSpacing.MD)
    lay.setSpacing(AppSpacing.MD)

    info = QVBoxLayout()
    title = QLabel(f"📁  {group_name}")
    title.setStyleSheet("font-size: 14px; font-weight: 600;")
    sub = QLabel("1 sesión" if session_count == 1 else f"{session_count} sesiones")
    sub.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 12px;")
    info.addWidget(title)
    info.addWidget(sub)
    lay.addLayout(info, stretch=1)

    rename_btn = QPushButton("Renombrar")
    rename_btn.clicked.connect(lambda _=False, g=group_name: on_rename(g))
    open_btn = QPushButton("Entrar →")
    open_btn.setObjectName("PrimaryButton")
    open_btn.clicked.connect(lambda _=False, g=group_name: on_open(g))
    lay.addWidget(rename_btn)
    lay.addWidget(open_btn)
    return card


def build_session_card(
    session: PhotoSession,
    on_open,
    on_organize,
    on_delete,
    on_rename=None,
    show_group_badge: bool = True,
) -> QFrame:
    card = QFrame()
    card.setObjectName("PanelSurface")
    layout = QVBoxLayout(card)
    layout.setContentsMargins(AppSpacing.LG, AppSpacing.LG, AppSpacing.LG, AppSpacing.LG)
    layout.setSpacing(AppSpacing.SM)

    if show_group_badge and session.group_name:
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
        f"Seleccionadas: {session.counts.for_editing}  ·  "
        f"Archivadas: {session.counts.archived}"
    )
    counts.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 12px;")
    layout.addWidget(counts)

    actions = QHBoxLayout()
    open_btn = QPushButton("Abrir")
    open_btn.setObjectName("PrimaryButton")
    open_btn.clicked.connect(lambda _=False, s=session: on_open(s))
    actions.addWidget(open_btn, stretch=1)
    if on_rename is not None:
        ren_btn = QPushButton("Renombrar")
        ren_btn.clicked.connect(lambda _=False, s=session: on_rename(s))
        actions.addWidget(ren_btn)
    org_btn = QPushButton("Tags / Grupo")
    org_btn.clicked.connect(lambda _=False, s=session: on_organize(s))
    del_btn = QPushButton("Eliminar")
    del_btn.setObjectName("ArchiveButton")
    del_btn.clicked.connect(lambda _=False, s=session: on_delete(s))
    actions.addWidget(org_btn)
    actions.addWidget(del_btn)
    layout.addLayout(actions)
    return card
