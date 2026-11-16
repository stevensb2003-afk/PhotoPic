"""Native UVC / DirectShow / HDMI-USB Live View widget for PhotoPic Windows."""

from __future__ import annotations

import os
from pathlib import Path
import tempfile
import time
from typing import Any

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QColor, QImage, QPainter, QPen, QPixmap
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .design_system import AppColors, AppSpacing
from .models import DeviceCategory, KnownDevice


class LiveViewTabWidget(QWidget):
    """Streams OpenCV UVC / HDMI-USB capture frames without altering WPD photo drivers."""

    def __init__(self, on_reference_saved, parent=None) -> None:
        super().__init__(parent)
        self._on_reference_saved = on_reference_saved
        self._cap: Any = None
        self._cv2: Any = None
        self._last_bgr: Any = None

        self._timer = QTimer(self)
        self._timer.setInterval(45)
        self._timer.timeout.connect(self._poll_frame)

        try:
            import cv2
            self._cv2 = cv2
        except ImportError:
            pass

        self._build_ui()

    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        bar = QFrame()
        bar.setObjectName("PanelSurface")
        bl = QHBoxLayout(bar)
        bl.setContentsMargins(AppSpacing.LG, AppSpacing.SM, AppSpacing.LG, AppSpacing.SM)

        self._cam_combo = QComboBox()
        for idx in range(4):
            self._cam_combo.addItem(f"Entrada Video / HDMI #{idx}", idx)
        bl.addWidget(self._cam_combo)

        self._chk_grid = QCheckBox("Cuadrícula 3×3")
        self._chk_grid.setChecked(True)
        self._chk_mirror = QCheckBox("Espejo")
        bl.addWidget(self._chk_grid)
        bl.addWidget(self._chk_mirror)
        bl.addStretch()

        self._save_btn = QPushButton("Guardar Cuadro de Referencia")
        self._save_btn.setEnabled(False)
        self._save_btn.clicked.connect(self._save_reference)
        bl.addWidget(self._save_btn)

        self._toggle_btn = QPushButton("Iniciar Vista en Vivo")
        self._toggle_btn.setObjectName("PrimaryButton")
        self._toggle_btn.clicked.connect(self.toggle_stream)
        bl.addWidget(self._toggle_btn)
        root.addWidget(bar)

        self._stage = QLabel(
            "Vista en Vivo UVC / Capturadora HDMI-USB (Windows DirectShow)\n\n"
            "• Funciona con cámaras modernas vía USB Streaming y DSLRs con capturadora HDMI→USB.\n"
            "• Mantiene intacto el driver estándar WPD para que sigan entrando tus RAWs por separado.\n"
            "• Cámaras clásicas sin HDMI ni UVC no transmiten Live View sin reemplazar el driver por WinUSB (Zadig)."
        )
        self._stage.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._stage.setStyleSheet(f"background: {AppColors.STAGE_BG}; color: {AppColors.TEXT_SECONDARY}; padding: 24px;")
        root.addWidget(self._stage, stretch=1)

    def toggle_stream(self) -> None:
        if self._timer.isActive():
            self.stop_stream()
        else:
            self.start_stream()

    def start_stream(self) -> None:
        if self._cv2 is None:
            self._stage.setText("OpenCV no está disponible en este entorno Python para abrir entradas UVC/HDMI.")
            return
        idx = int(self._cam_combo.currentData() or 0)
        backend = getattr(self._cv2, "CAP_DSHOW", 0) if os.name == "nt" else 0
        self._cap = self._cv2.VideoCapture(idx, backend) if backend else self._cv2.VideoCapture(idx)
        if not self._cap or not self._cap.isOpened():
            self.stop_stream()
            self._stage.setText(f"No se detectó señal de video en Entrada #{idx}. Verificá tu cámara UVC o capturadora HDMI.")
            return
        self._timer.start()
        self._toggle_btn.setText("Detener Vista en Vivo")
        self._save_btn.setEnabled(True)

    def stop_stream(self) -> None:
        self._timer.stop()
        if self._cap is not None:
            try:
                self._cap.release()
            except Exception:
                pass
            self._cap = None
        self._toggle_btn.setText("Iniciar Vista en Vivo")
        self._save_btn.setEnabled(False)

    def _poll_frame(self) -> None:
        if self._cap is None or self._cv2 is None:
            return
        ok, frame = self._cap.read()
        if not ok or frame is None:
            return
        self._last_bgr = frame
        rgb = self._cv2.cvtColor(frame, self._cv2.COLOR_BGR2RGB)
        if self._chk_mirror.isChecked():
            rgb = self._cv2.flip(rgb, 1)
        h, w, _ = rgb.shape
        qimg = QImage(rgb.data, w, h, w * 3, QImage.Format.Format_RGB888)
        pix = QPixmap.fromImage(qimg).scaled(
            self._stage.size(),
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation,
        )
        if self._chk_grid.isChecked():
            self._draw_thirds_grid(pix)
        self._stage.setPixmap(pix)

    @staticmethod
    def _draw_thirds_grid(pix: QPixmap) -> None:
        painter = QPainter(pix)
        pen = QPen(QColor(255, 255, 255, 110))
        pen.setWidth(1)
        painter.setPen(pen)
        w, h = pix.width(), pix.height()
        for i in (1, 2):
            painter.drawLine((w * i) // 3, 0, (w * i) // 3, h)
            painter.drawLine(0, (h * i) // 3, w, (h * i) // 3)
        painter.end()

    def _save_reference(self) -> None:
        if self._last_bgr is None or self._cv2 is None:
            return
        stage_dir = Path(tempfile.gettempdir()) / "PhotoPicWinLiveRefs"
        stage_dir.mkdir(parents=True, exist_ok=True)
        fname = f"LIVE_REF_{int(time.time())}.JPG"
        out_path = stage_dir / fname
        if self._cv2.imwrite(str(out_path), self._last_bgr):
            profile = KnownDevice("liveview", "Live View UVC", "Vista en Vivo", DeviceCategory.DSLR_MIRRORLESS, True, True, True)
            self._on_reference_saved(out_path, fname, profile)
