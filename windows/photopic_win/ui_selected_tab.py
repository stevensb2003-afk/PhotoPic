"""Selected (`Para_Edicion`) tab allowing inspection, Explorer reveal, Shift rotation, return to Filtrar, or archive."""

from __future__ import annotations

import os
import subprocess
import sys
from PySide6.QtCore import Qt
from PySide6.QtGui import QImage, QPixmap
from PySide6.QtWidgets import (
    QHBoxLayout,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QSplitter,
    QVBoxLayout,
    QWidget,
)

from .models import PhotoItem, PhotoSession
from .session_manager import SessionFileManager
from .ui_inspector_and_timer import SwipeablePhotoStage


class SelectedTabWidget(QWidget):
    def __init__(
        self,
        session: PhotoSession,
        on_items_changed,
        on_rotate_item=None,
        renderer=None,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.session = session
        self.on_items_changed = on_items_changed
        self.on_rotate_item = on_rotate_item
        self._renderer = renderer
        self._items: list[PhotoItem] = []

        lay = QVBoxLayout(self)
        splitter = QSplitter(Qt.Orientation.Horizontal)
        self._list = QListWidget()
        self._list.currentRowChanged.connect(self._render_selected_preview)
        self._preview = SwipeablePhotoStage()
        self._preview.setText("Seleccioná una foto para inspeccionar (Ctrl + rueda para zoom)")
        splitter.addWidget(self._list)
        splitter.addWidget(self._preview)
        splitter.setSizes([320, 680])
        lay.addWidget(splitter, stretch=1)

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
        self._render_selected_preview(self._list.currentRow())

    def _render_selected_preview(self, row: int) -> None:
        self._preview.reset_zoom()
        if not (0 <= row < len(self._items)) or self._renderer is None:
            self._preview.setPixmap(QPixmap())
            return
        payload = self._renderer.render_image(self._items[row], max_dimension=1600, full_sensor=False)
        if payload:
            qimg = QImage(payload.rgb_bytes, payload.width, payload.height, payload.width * 3, QImage.Format.Format_RGB888)
            self._preview.setPixmap(QPixmap.fromImage(qimg))
        else:
            self._preview.setPixmap(QPixmap())

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
