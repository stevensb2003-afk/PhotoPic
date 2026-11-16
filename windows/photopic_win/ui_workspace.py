"""Real-time RAW culling workspace widget with 1:1 zoom, AI tags, and Archived recovery."""

from __future__ import annotations

from pathlib import Path
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QImage, QKeyEvent, QPixmap
from PySide6.QtWidgets import (
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from .design_system import AppColors, AppSpacing
from .models import DeviceCategory, KnownDevice, PhotoItem, PhotoSession, PhotoVisionTags
from .raw_renderer import RawImageRendererWin
from .session_manager import MoveRecord, SessionFileManager
from .tag_store import PhotoTagStore
from .ui_workspace_bars import build_workspace_bottom_controls, build_workspace_topbar
from .vision_autotagger import VisionAutoTaggerWin


class SessionWorkspaceWidget(QWidget):
    def __init__(self, session: PhotoSession, tether_service, on_back, parent=None) -> None:
        super().__init__(parent)
        self.session = session
        self.tether_service = tether_service
        self.on_back = on_back
        self.renderer = RawImageRendererWin()
        self.tagger = VisionAutoTaggerWin()

        self.pending_items: list[PhotoItem] = []
        self.archived_items: list[PhotoItem] = []
        self.undo_stack: list[MoveRecord] = []
        self.current_index = 0
        self.zoom_one_to_one = False
        self.follow_latest = False

        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self._build_ui()
        self.reload_from_disk()

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        top, refs = build_workspace_topbar(
            self.session.name, self.on_back, self._switch_tab, self._attach_watch_folder
        )
        self._tab_cull_btn = refs["tab_cull"]
        self._tab_arch_btn = refs["tab_arch"]
        self._editing_badge = refs["edit_badge"]
        root.addWidget(top)

        self._stack = QStackedWidget()
        self._stage_label = QLabel("Cola de pendientes vacía")
        self._stage_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._stage_label.setStyleSheet(f"background: {AppColors.STAGE_BG};")
        self._stack.addWidget(self._stage_label)

        arch_page = QWidget()
        arch_l = QVBoxLayout(arch_page)
        self._arch_list = QListWidget()
        arch_l.addWidget(self._arch_list)
        recover_btn = QPushButton("Recuperar para Edición")
        recover_btn.setObjectName("ApproveButton")
        recover_btn.clicked.connect(self._recover_selected_archived)
        arch_l.addWidget(recover_btn)
        self._stack.addWidget(arch_page)
        root.addWidget(self._stack, stretch=1)

        hud = QFrame()
        hud.setObjectName("PanelSurface")
        hud_l = QHBoxLayout(hud)
        self._hud_info = QLabel("Sin imagen")
        self._hud_tags = QLabel("")
        self._hud_tags.setStyleSheet(f"color: {AppColors.INFO_BLUE}; font-size: 12px;")
        add_tag_btn = QPushButton("+ Etiqueta")
        add_tag_btn.clicked.connect(self._prompt_custom_tag)
        hud_l.addWidget(self._hud_info)
        hud_l.addSpacing(AppSpacing.MD)
        hud_l.addWidget(self._hud_tags)
        hud_l.addStretch()
        hud_l.addWidget(add_tag_btn)
        root.addWidget(hud)

        ctrl, _ = build_workspace_bottom_controls({
            "prev": self.navigate_prev,
            "next": self.navigate_next,
            "zoom": self.toggle_zoom,
            "undo": self.undo_last,
            "archive": self.archive_current,
            "approve": self.approve_current,
            "follow": lambda v: setattr(self, "follow_latest", v),
        })
        root.addWidget(ctrl)

    def reload_from_disk(self) -> None:
        tag_map = PhotoTagStore.load_all(self.session)
        self.pending_items = SessionFileManager.load_photo_items(self.session.raw_folder, self.session.jpg_folder, tag_map)
        self.archived_items = SessionFileManager.load_photo_items(self.session.archived_folder, self.session.jpg_folder, tag_map)
        self._refresh_counters_and_stage()
        QTimer.singleShot(50, self._analyze_unanalyzed_pending)

    def handle_staged_file(self, staged_path: Path, filename: str, profile: KnownDevice) -> None:
        outcome = SessionFileManager.ingest_captured_file(
            staged_path, filename, profile.alias, profile.allow_jpg_when_no_raw, self.session
        )
        if outcome.item is not None:
            self.pending_items.append(outcome.item)
            self._analyze_item(outcome.item)
            if self.follow_latest or len(self.pending_items) == 1:
                self.current_index = len(self.pending_items) - 1
        self._refresh_counters_and_stage()

    def navigate_prev(self) -> None:
        if self.current_index > 0:
            self.current_index -= 1
            self.zoom_one_to_one = False
            self._refresh_counters_and_stage()

    def navigate_next(self) -> None:
        if self.current_index + 1 < len(self.pending_items):
            self.current_index += 1
            self.zoom_one_to_one = False
            self._refresh_counters_and_stage()

    def toggle_zoom(self) -> None:
        self.zoom_one_to_one = not self.zoom_one_to_one
        self._refresh_counters_and_stage()

    def approve_current(self) -> None:
        self._move_current("Para_Edicion")

    def archive_current(self) -> None:
        self._move_current("Archivadas")

    def undo_last(self) -> None:
        if not self.undo_stack:
            return
        restored = SessionFileManager.undo_move(self.undo_stack.pop())
        self.archived_items = [i for i in self.archived_items if i.id != restored.id]
        self.pending_items.insert(min(self.current_index, len(self.pending_items)), restored)
        self._refresh_counters_and_stage()

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if self._stack.currentIndex() != 0:
            super().keyPressEvent(event)
            return
        key = event.key()
        actions = {
            Qt.Key.Key_Left: self.archive_current,
            Qt.Key.Key_Right: self.approve_current,
            Qt.Key.Key_Up: self.navigate_prev,
            Qt.Key.Key_Down: self.navigate_next,
            Qt.Key.Key_Space: self.toggle_zoom,
        }
        if key in actions:
            actions[key]()
        elif key == Qt.Key.Key_Z and event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            self.undo_last()
        else:
            super().keyPressEvent(event)

    def _move_current(self, dest_folder: str) -> None:
        if not (0 <= self.current_index < len(self.pending_items)):
            return
        item = self.pending_items.pop(self.current_index)
        rec = SessionFileManager.move_item(item, dest_folder, self.session)
        self.undo_stack.append(rec)
        if dest_folder == "Archivadas":
            self.archived_items.append(rec.item)
        self.current_index = min(self.current_index, len(self.pending_items) - 1) if self.pending_items else 0
        self.zoom_one_to_one = False
        self._refresh_counters_and_stage()

    def _recover_selected_archived(self) -> None:
        row = self._arch_list.currentRow()
        if 0 <= row < len(self.archived_items):
            SessionFileManager.move_item(self.archived_items.pop(row), "Para_Edicion", self.session)
            self._refresh_counters_and_stage()

    def _refresh_counters_and_stage(self) -> None:
        self.session.counts = SessionFileManager.read_disk_counts(self.session)
        self._tab_cull_btn.setText(f"Filtrar ({self.session.counts.pending})")
        self._tab_arch_btn.setText(f"Archivadas ({self.session.counts.archived})")
        self._editing_badge.setText(f"Para Edición: {self.session.counts.for_editing}")

        self._arch_list.clear()
        for item in self.archived_items:
            QListWidgetItem(f"{item.filename} ({item.format_extension})", self._arch_list)

        if not (0 <= self.current_index < len(self.pending_items)):
            self._stage_label.setPixmap(QPixmap())
            self._stage_label.setText("Cola de pendientes vacía")
            self._hud_info.setText("Sin imagen en cola")
            self._hud_tags.setText("")
            return

        current = self.pending_items[self.current_index]
        exif = RawImageRendererWin.read_exif(current.file_path, current.paired_compressed_path)
        self._hud_info.setText(
            f"{current.filename} [{current.format_extension}] · {exif.compact_hud_summary} "
            f"· Foto {self.current_index + 1} de {len(self.pending_items)}"
        )
        self._hud_tags.setText("  ".join(f"[{t}]" for t in current.vision_tags.all_tags) if current.vision_tags else "Analizando IA...")

        payload = self.renderer.render_image(current, max_dimension=1800, full_sensor=self.zoom_one_to_one)
        if payload:
            qimg = QImage(payload.rgb_bytes, payload.width, payload.height, payload.width * 3, QImage.Format.Format_RGB888)
            pix = QPixmap.fromImage(qimg)
            if not self.zoom_one_to_one:
                pix = pix.scaled(self._stage_label.size(), Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
            self._stage_label.setPixmap(pix)

    def _analyze_unanalyzed_pending(self) -> None:
        for item in self.pending_items:
            if item.vision_tags is None:
                self._analyze_item(item)
        self._refresh_counters_and_stage()

    def _analyze_item(self, item: PhotoItem) -> None:
        payload = self.renderer.render_image(item, max_dimension=960, full_sensor=False)
        if payload:
            tags = self.tagger.analyze_rgb_bytes(payload.rgb_bytes, payload.width, payload.height)
            item.vision_tags = tags
            PhotoTagStore.save(tags, item, self.session, write_xmp=True)

    def _prompt_custom_tag(self) -> None:
        if not (0 <= self.current_index < len(self.pending_items)):
            return
        current = self.pending_items[self.current_index]
        tag, ok = QInputDialog.getText(self, "Agregar etiqueta", "Etiqueta (ej. Pareja, Favorita):")
        if ok and tag.strip():
            tags = current.vision_tags or PhotoVisionTags()
            tags.add_custom_tag(tag.strip())
            current.vision_tags = tags
            PhotoTagStore.save(tags, current, self.session, write_xmp=True)
            self._refresh_counters_and_stage()

    def _attach_watch_folder(self) -> None:
        folder = QFileDialog.getExistingDirectory(self, "Seleccionar carpeta DCIM / Tarjeta SD / Watchfolder")
        if folder:
            profile = KnownDevice(fingerprint=f"watch:{folder}", display_name=Path(folder).name, alias=Path(folder).name, category=DeviceCategory.DSLR_MIRRORLESS)
            self.tether_service.attach_watch_folder(Path(folder), profile)

    def _switch_tab(self, idx: int) -> None:
        self._stack.setCurrentIndex(idx)
        self._refresh_counters_and_stage()
