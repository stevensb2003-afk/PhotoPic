"""Swipeable unobstructed photo stage, floating right EXIF card, and shooting timer bar for Windows."""

from __future__ import annotations

from datetime import datetime
from PySide6.QtCore import QPoint, Qt, QTimer
from PySide6.QtGui import QMouseEvent
from PySide6.QtWidgets import (
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .design_system import AppColors, AppSpacing
from .models import PhotoExifMetadata, PhotoItem, PhotoSession
from .session_metadata import SessionMetadata, SessionMetadataStore


class SwipeablePhotoStage(QLabel):
    """Photo canvas preserving horizontal mouse drag gestures (Left=Archive, Right=Approve)."""

    def __init__(self, on_swipe_left, on_swipe_right, parent=None) -> None:
        super().__init__(parent)
        self._on_swipe_left = on_swipe_left
        self._on_swipe_right = on_swipe_right
        self._press_pos: QPoint | None = None
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setStyleSheet(f"background: {AppColors.STAGE_BG}; border-radius: 12px;")

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self._press_pos = event.position().toPoint()
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton and self._press_pos is not None:
            dx = event.position().toPoint().x() - self._press_pos.x()
            self._press_pos = None
            if dx > 110:
                self._on_swipe_right()
                return
            if dx < -110:
                self._on_swipe_left()
                return
        super().mouseReleaseEvent(event)


class FloatingPhotoInspectorCard(QFrame):
    """Isolated right-side floating rounded card displaying EXIF telemetry and tags without overlap."""

    def __init__(self, on_add_custom_tag, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("PanelSurface")
        self.setFixedWidth(256)
        self.setStyleSheet(
            f"#PanelSurface {{ background: {AppColors.PANEL_SURFACE}; "
            f"border: 1px solid {AppColors.BORDER_STRONG}; border-radius: 16px; }}"
        )

        lay = QVBoxLayout(self)
        lay.setContentsMargins(AppSpacing.LG, AppSpacing.LG, AppSpacing.LG, AppSpacing.LG)
        lay.setSpacing(AppSpacing.SM)

        top_row = QHBoxLayout()
        self._pos_lbl = QLabel("Sin imagen")
        self._pos_lbl.setStyleSheet(f"color: {AppColors.TEXT_PRIMARY}; font-size: 11px; font-weight: 600;")
        self._fmt_lbl = QLabel("—")
        self._fmt_lbl.setStyleSheet(f"color: {AppColors.WARNING_AMBER}; font-size: 11px; font-weight: 600;")
        top_row.addWidget(self._pos_lbl)
        top_row.addStretch()
        top_row.addWidget(self._fmt_lbl)
        lay.addLayout(top_row)

        self._name_lbl = QLabel("—")
        self._name_lbl.setWordWrap(True)
        self._name_lbl.setStyleSheet("font-weight: 600; font-size: 13px;")
        lay.addWidget(self._name_lbl)

        self._meta_lbl = QLabel("Tamaño: —\nResolución: —\nCaptura: —")
        self._meta_lbl.setWordWrap(True)
        self._meta_lbl.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 11px;")
        lay.addWidget(self._meta_lbl)

        grid = QGridLayout()
        grid.setSpacing(6)
        self._exif_cells: dict[str, QLabel] = {}
        for idx, (key, title) in enumerate((("iso", "ISO"), ("ap", "Apertura"), ("sh", "Obturación"), ("fl", "Focal"))):
            cell = QFrame()
            cell.setStyleSheet(f"background: {AppColors.STAGE_BG}; border-radius: 6px; padding: 4px;")
            cl = QVBoxLayout(cell)
            cl.setContentsMargins(6, 4, 6, 4)
            cl.setSpacing(1)
            t = QLabel(title)
            t.setStyleSheet(f"color: {AppColors.TEXT_TERTIARY}; font-size: 10px;")
            v = QLabel("—")
            v.setStyleSheet(f"color: {AppColors.TEXT_PRIMARY}; font-size: 12px; font-weight: 600;")
            cl.addWidget(t)
            cl.addWidget(v)
            grid.addWidget(cell, idx // 2, idx % 2)
            self._exif_cells[key] = v
        lay.addLayout(grid)

        self._cam_lbl = QLabel("Cámara: —")
        self._cam_lbl.setWordWrap(True)
        self._cam_lbl.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 11px;")
        lay.addWidget(self._cam_lbl)

        self._tags_lbl = QLabel("Sin etiquetas IA")
        self._tags_lbl.setWordWrap(True)
        self._tags_lbl.setStyleSheet(f"color: {AppColors.INFO_BLUE}; font-size: 11px;")
        lay.addWidget(self._tags_lbl)

        lay.addStretch()
        add_btn = QPushButton("+ Etiqueta")
        add_btn.clicked.connect(on_add_custom_tag)
        lay.addWidget(add_btn)

    def clear_state(self) -> None:
        self._pos_lbl.setText("Cola vacía")
        self._fmt_lbl.setText("—")
        self._name_lbl.setText("Sin imagen")
        self._meta_lbl.setText("Tamaño: —\nResolución: —\nCaptura: —")
        for lbl in self._exif_cells.values():
            lbl.setText("—")
        self._cam_lbl.setText("Cámara: —")
        self._tags_lbl.setText("")

    def update_item(self, item: PhotoItem, exif: PhotoExifMetadata, index: int, total: int, ai_enabled: bool) -> None:
        self._pos_lbl.setText(f"Foto {index + 1} de {total}")
        comp = " +JPG" if item.paired_compressed_path else ""
        self._fmt_lbl.setText(f"{item.format_extension}{comp}")
        self._name_lbl.setText(item.filename)

        size_mb = item.file_size_bytes / (1024 * 1024)
        dims = exif.formatted_dimensions or "—"
        captured_str = datetime.fromtimestamp(item.captured_at).strftime("%H:%M:%S · %d/%m/%Y") if item.captured_at else "—"
        self._meta_lbl.setText(f"Tamaño: {size_mb:.1f} MB\nResolución: {dims}\nCaptura: {captured_str}")

        self._exif_cells["iso"].setText(exif.formatted_iso or "—")
        self._exif_cells["ap"].setText(exif.formatted_aperture or "—")
        self._exif_cells["sh"].setText(exif.formatted_shutter or "—")
        self._exif_cells["fl"].setText(exif.formatted_focal or "—")

        make = (exif.camera_make or "").strip()
        model = (exif.camera_model or "").strip()
        if make and model and make.lower() not in model.lower():
            cam = f"{make} {model}"
        else:
            cam = model or make or item.source_device_alias or "USB / Disco"
        lens = f"\nLente: {exif.lens_model}" if exif.lens_model else ""
        self._cam_lbl.setText(f"Cámara: {cam}{lens}")

        if item.vision_tags and item.vision_tags.all_tags:
            self._tags_lbl.setText("  ".join(f"[{t}]" for t in item.vision_tags.all_tags))
        else:
            self._tags_lbl.setText("Analizando IA..." if ai_enabled else "Sin etiquetas (.XMP)")


class SessionTimerBarWidget(QFrame):
    """Per-session live shooting timer bar with manual controls and 1st-shot auto-start."""

    def __init__(self, session: PhotoSession, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session = session
        self.metadata: SessionMetadata = SessionMetadataStore.load(session.directory)

        lay = QHBoxLayout(self)
        lay.setContentsMargins(10, 2, 10, 2)
        lay.setSpacing(6)

        self._clock_lbl = QLabel(self.metadata.formatted_duration())
        self._clock_lbl.setStyleSheet("font-family: Consolas, monospace; font-weight: 600; font-size: 13px;")
        self._toggle_btn = QPushButton("Iniciar Timer")
        self._toggle_btn.clicked.connect(self._on_toggle)
        self._reset_btn = QPushButton("↺")
        self._reset_btn.setFixedWidth(28)
        self._reset_btn.setToolTip("Reiniciar temporizador")
        self._reset_btn.clicked.connect(self._on_reset)

        lay.addWidget(QLabel("⏱"))
        lay.addWidget(self._clock_lbl)
        lay.addWidget(self._toggle_btn)
        lay.addWidget(self._reset_btn)

        self._qtimer = QTimer(self)
        self._qtimer.setInterval(1000)
        self._qtimer.timeout.connect(self._refresh_ui)
        self._refresh_ui()

    def auto_start_if_first_shot(self, captured_at: float, enabled: bool) -> None:
        if enabled and self.metadata.has_never_started_timer:
            self.metadata.auto_start_from_first_shot(captured_at=captured_at)
            SessionMetadataStore.save(self.metadata, self.session.directory)
            self._refresh_ui()

    def stop_ticker(self) -> None:
        self._qtimer.stop()

    def _on_toggle(self) -> None:
        if self.metadata.is_timer_running:
            self.metadata.stop_and_finish()
        else:
            self.metadata.start_manual()
        SessionMetadataStore.save(self.metadata, self.session.directory)
        self._refresh_ui()

    def _on_reset(self) -> None:
        self.metadata.reset_timer()
        SessionMetadataStore.save(self.metadata, self.session.directory)
        self._refresh_ui()

    def _refresh_ui(self) -> None:
        self._clock_lbl.setText(self.metadata.formatted_duration())
        if self.metadata.is_timer_running:
            self._toggle_btn.setText("Finalizar")
            self._reset_btn.setVisible(False)
            if not self._qtimer.isActive():
                self._qtimer.start()
        elif self.metadata.is_timer_finished:
            self._qtimer.stop()
            self._toggle_btn.setText("Reanudar")
            self._reset_btn.setVisible(True)
        else:
            self._qtimer.stop()
            self._toggle_btn.setText("Iniciar Timer")
            self._reset_btn.setVisible(False)
