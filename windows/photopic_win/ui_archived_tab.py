"""Archived photos split pane with Recover to Editing and confirmation Popover permanent delete."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QHBoxLayout,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .archive_cleaner import SessionArchiveCleaner
from .models import PhotoItem, PhotoSession
from .session_manager import SessionFileManager
from .ui_setup_wizard import ArchiveDeletePopover


class ArchivedTabWidget(QWidget):
    def __init__(self, session: PhotoSession, on_items_changed, on_rotate_item=None, parent=None) -> None:
        super().__init__(parent)
        self.session = session
        self.on_items_changed = on_items_changed
        self.on_rotate_item = on_rotate_item
        self._items: list[PhotoItem] = []

        lay = QVBoxLayout(self)
        self._list = QListWidget()
        lay.addWidget(self._list)

        row = QHBoxLayout()
        self._empty_btn = QPushButton("Vaciar Archivadas...")
        self._empty_btn.setObjectName("ArchiveButton")
        self._empty_btn.clicked.connect(self._confirm_empty)

        self._rotate_btn = QPushButton("Rotar 90° (Shift)")
        self._rotate_btn.clicked.connect(self._rotate_selected)

        self._delete_btn = QPushButton("Eliminar archivo...")
        self._delete_btn.setObjectName("ArchiveButton")
        self._delete_btn.clicked.connect(self._confirm_delete_one)

        self._recover_btn = QPushButton("Recuperar a Seleccionadas")
        self._recover_btn.setObjectName("ApproveButton")
        self._recover_btn.clicked.connect(self._recover_selected)

        row.addWidget(self._empty_btn)
        row.addStretch()
        row.addWidget(self._rotate_btn)
        row.addWidget(self._delete_btn)
        row.addWidget(self._recover_btn)
        lay.addLayout(row)

    def current_item(self) -> PhotoItem | None:
        row = self._list.currentRow()
        if 0 <= row < len(self._items):
            return self._items[row]
        return None

    def _rotate_selected(self) -> None:
        item = self.current_item()
        if item is not None and self.on_rotate_item is not None:
            self.on_rotate_item(item)

    def set_items(self, items: list[PhotoItem]) -> None:
        self._items = items
        self._list.clear()
        for item in items:
            QListWidgetItem(f"{item.filename} ({item.format_extension})", self._list)
        if items:
            self._list.setCurrentRow(0)
        has_items = bool(items)
        self._empty_btn.setEnabled(has_items)
        self._rotate_btn.setEnabled(has_items)
        self._delete_btn.setEnabled(has_items)
        self._recover_btn.setEnabled(has_items)

    def _recover_selected(self) -> None:
        row = self._list.currentRow()
        if 0 <= row < len(self._items):
            item = self._items.pop(row)
            SessionFileManager.move_item(item, "Para_Edicion", self.session)
            self.on_items_changed({item.id})

    def _confirm_delete_one(self) -> None:
        row = self._list.currentRow()
        if not (0 <= row < len(self._items)):
            return
        target = self._items[row]
        pop = ArchiveDeletePopover(
            title_text=f"¿Eliminar {target.filename}?",
            warning_text="Se borrará permanentemente de Archivadas/ junto con su .XMP.",
            confirm_label="Eliminar para siempre",
            on_confirm=lambda del_jpg: self._execute_delete_one(row, del_jpg),
            parent=self,
        )
        pop.show_above(self._delete_btn)

    def _execute_delete_one(self, row: int, delete_jpg: bool) -> None:
        if 0 <= row < len(self._items):
            item = self._items.pop(row)
            SessionArchiveCleaner.permanently_delete_archived_item(
                item, self.session, delete_companion_jpg=delete_jpg
            )
            self.on_items_changed({item.id})

    def _confirm_empty(self) -> None:
        if not self._items:
            return
        count = len(self._items)
        pop = ArchiveDeletePopover(
            title_text=f"¿Vaciar {count} fotos archivadas?",
            warning_text="Se eliminarán todos los descartes en Archivadas/ y sus .XMP. RAW/ y Para_Edicion/ quedan intactos.",
            confirm_label=f"Vaciar ({count})",
            on_confirm=self._execute_empty_all,
            parent=self,
        )
        pop.show_above(self._empty_btn)

    def _execute_empty_all(self, delete_jpgs: bool) -> None:
        removed_ids = {i.id for i in self._items}
        SessionArchiveCleaner.permanently_delete_all_archived(self.session, delete_companion_jpgs=delete_jpgs)
        self._items.clear()
        self.on_items_changed(removed_ids)
