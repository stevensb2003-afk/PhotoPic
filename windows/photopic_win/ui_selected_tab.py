"""Selected (`Para_Edicion`) tab allowing inspection, Explorer reveal, Shift rotation, return to Filtrar, or archive."""

from __future__ import annotations

import os
import subprocess
import sys
from PySide6.QtWidgets import (
    QHBoxLayout,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .models import PhotoItem, PhotoSession
from .session_manager import SessionFileManager


class SelectedTabWidget(QWidget):
    def __init__(
        self,
        session: PhotoSession,
        on_items_changed,
        on_rotate_item=None,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.session = session
        self.on_items_changed = on_items_changed
        self.on_rotate_item = on_rotate_item
        self._items: list[PhotoItem] = []

        lay = QVBoxLayout(self)
        self._list = QListWidget()
        lay.addWidget(self._list)

        row = QHBoxLayout()
        self._reveal_btn = QPushButton("Mostrar en Explorador")
        self._reveal_btn.clicked.connect(self._reveal_in_explorer)

        self._rotate_btn = QPushButton("Rotar 90° (Shift)")
        self._rotate_btn.clicked.connect(self._rotate_selected)

        self._return_btn = QPushButton("Devolver a Filtrar")
        self._return_btn.clicked.connect(self._return_to_pending)

        self._archive_btn = QPushButton("Mover a Archivadas")
        self._archive_btn.setObjectName("ArchiveButton")
        self._archive_btn.clicked.connect(self._move_to_archived)

        row.addWidget(self._reveal_btn)
        row.addStretch()
        row.addWidget(self._rotate_btn)
        row.addWidget(self._return_btn)
        row.addWidget(self._archive_btn)
        lay.addLayout(row)

    def set_items(self, items: list[PhotoItem]) -> None:
        prev_id = self.current_item().id if self.current_item() is not None else None
        self._items = list(items)
        self._list.clear()
        selected_row = 0
        for idx, item in enumerate(self._items):
            suffix = " +JPG" if item.paired_compressed_path is not None else ""
            tags_preview = ""
            if item.vision_tags and item.vision_tags.all_tags:
                tags_preview = f"  ·  {', '.join(item.vision_tags.all_tags[:3])}"
            QListWidgetItem(f"{item.filename} ({item.format_extension}{suffix}){tags_preview}", self._list)
            if prev_id and item.id == prev_id:
                selected_row = idx
        if self._items:
            self._list.setCurrentRow(selected_row)
        has_items = bool(self._items)
        self._rotate_btn.setEnabled(has_items)
        self._return_btn.setEnabled(has_items)
        self._archive_btn.setEnabled(has_items)

    def current_item(self) -> PhotoItem | None:
        row = self._list.currentRow()
        if 0 <= row < len(self._items):
            return self._items[row]
        return None

    def _rotate_selected(self) -> None:
        item = self.current_item()
        if item is not None and self.on_rotate_item is not None:
            self.on_rotate_item(item)

    def _return_to_pending(self) -> None:
        row = self._list.currentRow()
        if 0 <= row < len(self._items):
            item = self._items.pop(row)
            SessionFileManager.move_item(item, "RAW", self.session)
            self.on_items_changed({item.id})

    def _move_to_archived(self) -> None:
        row = self._list.currentRow()
        if 0 <= row < len(self._items):
            item = self._items.pop(row)
            SessionFileManager.move_item(item, "Archivadas", self.session)
            self.on_items_changed({item.id})

    def _reveal_in_explorer(self) -> None:
        folder = self.session.for_editing_folder
        folder.mkdir(parents=True, exist_ok=True)
        if sys.platform.startswith("win") and hasattr(os, "startfile"):
            os.startfile(str(folder))  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.Popen(["open", str(folder)])
        else:
            subprocess.Popen(["xdg-open", str(folder)])
