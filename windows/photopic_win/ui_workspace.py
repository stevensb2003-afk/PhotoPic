"""Real-time RAW culling workspace widget with isolated floating EXIF inspector, timer, and 1:1 zoom."""

from __future__ import annotations

from pathlib import Path
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QImage, QKeyEvent, QPixmap
from PySide6.QtWidgets import (
    QFileDialog,
    QHBoxLayout,
    QInputDialog,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from .design_system import AppSpacing
from .hardware_auditor import PerformancePreferences
from .models import DeviceCategory, KnownDevice, PhotoItem, PhotoSession, PhotoVisionTags
from .raw_renderer import RawImageRendererWin
from .session_manager import MoveRecord, SessionFileManager
from .tag_store import PhotoTagStore
from .ui_archived_tab import ArchivedTabWidget
from .ui_inspector_and_timer import (
    FloatingPhotoInspectorCard,
    SessionTimerBarWidget,
    SwipeablePhotoStage,
)
from .ui_live_view import LiveViewTabWidget
from .ui_workspace_bars import build_workspace_bottom_controls, build_workspace_topbar
from .vision_autotagger import VisionAutoTaggerWin


class SessionWorkspaceWidget(QWidget):
    def __init__(
        self,
        session: PhotoSession,
        tether_service,
        on_back,
        performance_prefs: PerformancePreferences | None = None,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.session = session
        self.tether_service = tether_service
        self.on_back = on_back
        self.perf_prefs = performance_prefs or PerformancePreferences()
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

        self._timer_bar = SessionTimerBarWidget(self.session)
        top, refs = build_workspace_topbar(
            self.session.name,
            self._handle_back,
            self._switch_tab,
            self._attach_watch_folder,
            self._open_help,
            timer_widget=self._timer_bar,
        )
        self._tab_cull_btn = refs["tab_cull"]
        self._tab_arch_btn = refs["tab_arch"]
        self._editing_badge = refs["edit_badge"]
        root.addWidget(top)

        self._stack = QStackedWidget()

        cull_page = QWidget()
        cull_lay = QHBoxLayout(cull_page)
        cull_lay.setContentsMargins(AppSpacing.MD, AppSpacing.MD, AppSpacing.LG, AppSpacing.MD)
        cull_lay.setSpacing(AppSpacing.MD)

        self._stage_label = SwipeablePhotoStage(
            on_swipe_left=self.archive_current,
            on_swipe_right=self.approve_current,
        )
        self._stage_label.setText("Cola de pendientes vacía")
        cull_lay.addWidget(self._stage_label, stretch=1)

        self._inspector_card = FloatingPhotoInspectorCard(on_add_custom_tag=self._prompt_custom_tag)
        cull_lay.addWidget(self._inspector_card)
        self._stack.addWidget(cull_page)

        self._live_tab = LiveViewTabWidget(on_reference_saved=self.handle_staged_file)
        self._stack.addWidget(self._live_tab)

        self._archived_tab = ArchivedTabWidget(self.session, on_items_changed=self._on_archived_changed)
        self._stack.addWidget(self._archived_tab)
        root.addWidget(self._stack, stretch=1)

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

    def _handle_back(self) -> None:
        self._timer_bar.stop_ticker()
        self.on_back()

    def reload_from_disk(self) -> None:
        tag_map = PhotoTagStore.load_all(self.session)
        self.pending_items = SessionFileManager.load_photo_items(self.session.raw_folder, self.session.jpg_folder, tag_map)
        self.archived_items = SessionFileManager.load_archived_items(self.session, tag_map)
        self._refresh_counters_and_stage()
        if self.perf_prefs.enable_vision_autotagging:
            QTimer.singleShot(50, self._analyze_unanalyzed_pending)

    def apply_performance_preferences(self, prefs: PerformancePreferences) -> None:
        self.perf_prefs = prefs
        if prefs.enable_vision_autotagging:
            self._analyze_unanalyzed_pending()
        else:
            self._refresh_counters_and_stage()

    def handle_staged_file(self, staged_path: Path, filename: str, profile: KnownDevice) -> None:
        outcome = SessionFileManager.ingest_captured_file(
            staged_path, filename, profile.alias, profile.allow_jpg_when_no_raw, self.session
        )
        if outcome.item is not None:
            self.pending_items.append(outcome.item)
            self._timer_bar.auto_start_if_first_shot(
                outcome.item.captured_at,
                self.perf_prefs.auto_start_session_timer,
            )
            if self.perf_prefs.enable_vision_autotagging:
                self._analyze_item(outcome.item)
            if self.follow_latest or len(self.pending_items) == 1:
                self.current_index = len(self.pending_items) - 1
        elif outcome.kind == "separated_jpg" and outcome.destination_path is not None:
            base = outcome.destination_path.stem.lower()
            for pending in self.pending_items:
                if pending.base_filename == base:
                    pending.paired_compressed_path = outcome.destination_path
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

    def _on_archived_changed(self, removed_ids: set[str]) -> None:
        self.undo_stack = [r for r in self.undo_stack if r.item.id not in removed_ids]
        self._refresh_counters_and_stage()

    def _refresh_counters_and_stage(self) -> None:
        self.session.counts = SessionFileManager.read_disk_counts(self.session)
        self._tab_cull_btn.setText(f"Filtrar ({self.session.counts.pending})")
        self._tab_arch_btn.setText(f"Archivadas ({self.session.counts.archived})")
        self._editing_badge.setText(f"Para Edición: {self.session.counts.for_editing}")
        self._archived_tab.set_items(self.archived_items)

        if not (0 <= self.current_index < len(self.pending_items)):
            self._stage_label.setPixmap(QPixmap())
            self._stage_label.setText("Cola de pendientes vacía")
            self._inspector_card.clear_state()
            return

        current = self.pending_items[self.current_index]
        exif = RawImageRendererWin.read_exif(current.file_path, current.paired_compressed_path)
        self._inspector_card.update_item(
            current, exif, self.current_index, len(self.pending_items), self.perf_prefs.enable_vision_autotagging
        )

        payload = self.renderer.render_image(
            current,
            max_dimension=self.perf_prefs.preview_max_dimension,
            full_sensor=self.zoom_one_to_one,
        )
        if payload:
            qimg = QImage(payload.rgb_bytes, payload.width, payload.height, payload.width * 3, QImage.Format.Format_RGB888)
            pix = QPixmap.fromImage(qimg)
            if not self.zoom_one_to_one:
                pix = pix.scaled(self._stage_label.size(), Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
            self._stage_label.setPixmap(pix)

    def _analyze_unanalyzed_pending(self) -> None:
        if not self.perf_prefs.enable_vision_autotagging:
            return
        for item in self.pending_items:
            if item.vision_tags is None:
                self._analyze_item(item)
        self._refresh_counters_and_stage()

    def _analyze_item(self, item: PhotoItem) -> None:
        if not self.perf_prefs.enable_vision_autotagging:
            return
        payload = self.renderer.render_image(item, max_dimension=960, full_sensor=False)
        if payload:
            tags = self.tagger.analyze_rgb_bytes(
                payload.rgb_bytes, payload.width, payload.height, include_body_pose=self.perf_prefs.detect_body_poses
            )
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

    def _open_help(self) -> None:
        from .ui_help_dialog import HelpCenterDialog
        HelpCenterDialog(parent=self).exec()

    def _switch_tab(self, idx: int) -> None:
        if idx != 1:
            self._live_tab.stop_stream()
        self._stack.setCurrentIndex(idx)
        self._refresh_counters_and_stage()
