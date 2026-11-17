"""Guided hardware audit setup wizard, performance settings dialog, and Archive delete popover."""

from __future__ import annotations

from pathlib import Path
from PySide6.QtCore import QPoint, Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .design_system import AppColors, AppSpacing
from .hardware_auditor import HardwareAuditReport, PerformancePreferences, PerformanceTier


class _AuditConfigPanel(QWidget):
    """Shared hardware telemetry + tier + AI toggles panel for Wizard and Settings."""

    def __init__(self, audit: HardwareAuditReport, prefs: PerformancePreferences, parent=None) -> None:
        super().__init__(parent)
        self._audit = audit
        self._prefs = prefs

        layout = QVBoxLayout(self)
        layout.setSpacing(AppSpacing.MD)

        card = QFrame()
        card.setObjectName("PanelSurface")
        cl = QVBoxLayout(card)
        cl.setContentsMargins(AppSpacing.LG, AppSpacing.LG, AppSpacing.LG, AppSpacing.LG)
        cl.setSpacing(AppSpacing.SM)

        hw = QLabel(
            f"CPU: {audit.cpu_brand} ({audit.architecture})  ·  RAM: {audit.ram_gb} GB  ·  "
            f"Núcleos: {audit.cpu_cores}\n"
            f"Motores IA: MediaPipe={'Sí' if audit.has_mediapipe else 'No'} · "
            f"OpenCV={'Sí' if audit.has_opencv else 'No'} (sin Neural Engine de Apple, corre en CPU)"
        )
        hw.setStyleSheet(f"color: {AppColors.TEXT_PRIMARY}; font-size: 12px;")
        cl.addWidget(hw)

        reason = QLabel(f"Recomendación automática: {audit.recommendation_reason}")
        reason.setWordWrap(True)
        reason.setStyleSheet(f"color: {AppColors.APPROVE_GREEN}; font-size: 12px;")
        cl.addWidget(reason)

        self._tier_combo = QComboBox()
        for tier in PerformanceTier:
            tag = " [Recomendado]" if tier == audit.recommended_tier else ""
            self._tier_combo.addItem(f"{tier.title}{tag}", tier.value)
        idx = max(0, self._tier_combo.findData(prefs.tier))
        self._tier_combo.setCurrentIndex(idx)
        self._tier_combo.currentIndexChanged.connect(self._on_tier_changed)
        cl.addWidget(self._tier_combo)

        self._chk_ai = QCheckBox("Activar auto-etiquetado IA de rostros y personas al capturar")
        self._chk_ai.setChecked(prefs.enable_vision_autotagging)
        self._chk_ai.toggled.connect(self._on_toggles_changed)
        cl.addWidget(self._chk_ai)

        self._chk_pose = QCheckBox("Incluir detección corporal de poses (MediaPipe Pose)")
        self._chk_pose.setChecked(prefs.detect_body_poses)
        self._chk_pose.setEnabled(prefs.enable_vision_autotagging)
        self._chk_pose.toggled.connect(self._on_toggles_changed)
        cl.addWidget(self._chk_pose)

        self._chk_auto_timer = QCheckBox(
            "Auto-iniciar temporizador de sesión con la hora de captura de la primera foto"
        )
        self._chk_auto_timer.setChecked(prefs.auto_start_session_timer)
        cl.addWidget(self._chk_auto_timer)

        layout.addWidget(card)

    def current_preferences(self, completed_setup: bool) -> PerformancePreferences:
        tier_val = self._tier_combo.currentData() or PerformanceTier.BALANCED_AI.value
        tier = PerformanceTier(tier_val)
        preset = PerformancePreferences.preset(
            tier,
            completed=completed_setup,
            auto_start_timer=self._chk_auto_timer.isChecked(),
        )
        preset.enable_vision_autotagging = self._chk_ai.isChecked()
        preset.detect_body_poses = self._chk_ai.isChecked() and self._chk_pose.isChecked()
        return preset

    def _on_tier_changed(self) -> None:
        tier = PerformanceTier(self._tier_combo.currentData())
        preset = PerformancePreferences.preset(tier)
        self._chk_ai.blockSignals(True)
        self._chk_pose.blockSignals(True)
        self._chk_ai.setChecked(preset.enable_vision_autotagging)
        self._chk_pose.setChecked(preset.detect_body_poses)
        self._chk_pose.setEnabled(preset.enable_vision_autotagging)
        self._chk_ai.blockSignals(False)
        self._chk_pose.blockSignals(False)

    def _on_toggles_changed(self) -> None:
        self._chk_pose.setEnabled(self._chk_ai.isChecked())
        if not self._chk_ai.isChecked():
            self._chk_pose.setChecked(False)


class GuidedSetupWizardWidget(QWidget):
    """First-run guided installation wizard checking PC specs before picking root folder."""

    def __init__(self, audit: HardwareAuditReport, prefs: PerformancePreferences, on_complete, parent=None) -> None:
        super().__init__(parent)
        self.on_complete = on_complete
        self.chosen_root = Path.home() / "Pictures" / "Sesiones_PhotoPic"

        outer = QVBoxLayout(self)
        outer.setAlignment(Qt.AlignmentFlag.AlignCenter)

        container = QFrame()
        container.setObjectName("PanelSurface")
        container.setFixedWidth(640)
        lay = QVBoxLayout(container)
        lay.setContentsMargins(AppSpacing.XL, AppSpacing.XL, AppSpacing.XL, AppSpacing.XL)
        lay.setSpacing(AppSpacing.MD)

        title = QLabel("PhotoPic · Asistente de Instalación Inicial")
        title.setStyleSheet("font-size: 20px; font-weight: 600;")
        sub = QLabel("Paso 1: Auditoría de PC e IA  ·  Paso 2: Carpeta Raíz Global")
        sub.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 12px;")
        lay.addWidget(title)
        lay.addWidget(sub)

        self._panel = _AuditConfigPanel(audit, prefs)
        lay.addWidget(self._panel)

        folder_row = QHBoxLayout()
        self._root_lbl = QLabel(str(self.chosen_root))
        self._root_lbl.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 12px;")
        pick_btn = QPushButton("Elegir Carpeta Raíz...")
        pick_btn.clicked.connect(self._pick_folder)
        folder_row.addWidget(self._root_lbl, stretch=1)
        folder_row.addWidget(pick_btn)
        lay.addLayout(folder_row)

        finish_btn = QPushButton("Guardar Perfil e Iniciar Estudio")
        finish_btn.setObjectName("PrimaryButton")
        finish_btn.clicked.connect(self._finish)
        lay.addWidget(finish_btn)
        outer.addWidget(container)

    def _pick_folder(self) -> None:
        chosen = QFileDialog.getExistingDirectory(self, "Elegir Carpeta Raíz Global")
        if chosen:
            self.chosen_root = Path(chosen)
            self._root_lbl.setText(chosen)

    def _finish(self) -> None:
        self.chosen_root.mkdir(parents=True, exist_ok=True)
        self.on_complete(self.chosen_root, self._panel.current_preferences(completed_setup=True))


class HardwareSettingsDialog(QDialog):
    """Settings modal allowing re-configuration of AI / hardware tiers anytime."""

    def __init__(self, audit: HardwareAuditReport, prefs: PerformancePreferences, on_apply, parent=None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Auditoría de Hardware y Rendimiento IA")
        self.setFixedWidth(600)
        lay = QVBoxLayout(self)
        self._panel = _AuditConfigPanel(audit, prefs)
        lay.addWidget(self._panel)

        btns = QHBoxLayout()
        btns.addStretch()
        cancel_btn = QPushButton("Cancelar")
        cancel_btn.clicked.connect(self.reject)
        save_btn = QPushButton("Aplicar Cambios")
        save_btn.setObjectName("PrimaryButton")
        save_btn.clicked.connect(lambda: (on_apply(self._panel.current_preferences(True)), self.accept()))
        btns.addWidget(cancel_btn)
        btns.addWidget(save_btn)
        lay.addLayout(btns)


class ArchiveDeletePopover(QFrame):
    """Frameless confirmation popover anchored near Delete / Empty buttons in Archivadas."""

    def __init__(self, title_text: str, warning_text: str, confirm_label: str, on_confirm, parent=None) -> None:
        super().__init__(parent, Qt.WindowType.Popup)
        self.setObjectName("PanelSurface")
        self.setFixedWidth(340)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(AppSpacing.LG, AppSpacing.LG, AppSpacing.LG, AppSpacing.LG)
        lay.setSpacing(AppSpacing.SM)

        t_lbl = QLabel(title_text)
        t_lbl.setStyleSheet(f"color: {AppColors.ARCHIVE_RED}; font-weight: 600; font-size: 13px;")
        lay.addWidget(t_lbl)

        w_lbl = QLabel(warning_text)
        w_lbl.setWordWrap(True)
        w_lbl.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 12px;")
        lay.addWidget(w_lbl)

        self._chk_jpg = QCheckBox("Eliminar también copia JPG asociada en JPG/")
        lay.addWidget(self._chk_jpg)

        row = QHBoxLayout()
        cancel_btn = QPushButton("Cancelar")
        cancel_btn.clicked.connect(self.close)
        confirm_btn = QPushButton(confirm_label)
        confirm_btn.setObjectName("ArchiveButton")
        confirm_btn.clicked.connect(lambda: (on_confirm(self._chk_jpg.isChecked()), self.close()))
        row.addWidget(cancel_btn)
        row.addStretch()
        row.addWidget(confirm_btn)
        lay.addLayout(row)

    def show_above(self, anchor_widget: QWidget) -> None:
        self.adjustSize()
        global_pos = anchor_widget.mapToGlobal(QPoint(0, -self.height() - 6))
        self.move(global_pos)
        self.show()
