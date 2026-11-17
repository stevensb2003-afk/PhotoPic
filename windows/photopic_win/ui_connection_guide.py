"""Interactive USB Connection Validator & Brand Guide dialog for PhotoPic Windows."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QTextBrowser,
    QVBoxLayout,
)

from .design_system import AppColors, AppSpacing

_BRAND_GUIDES: list[tuple[str, str, str, list[str], str]] = [
    (
        "Samsung Galaxy",
        "Notificación USB → 'Transferir archivos (MTP)' o 'Transferir imágenes (PTP)' + 'Permitir'",
        "Evitar: 'Solo carga', 'USB Tethering' y 'MIDI'",
        [
            "Desbloqueá tu Samsung y revisá la notificación del sistema Android.",
            "Cambiá de 'Solo carga' a 'Transferir archivos' (WPD/MTP) o 'Transferir imágenes (PTP)'.",
            "Tocá 'Permitir' si aparece '¿Permitir acceso a los datos del teléfono?'.",
        ],
        "Para RAW instantáneo (~1s), usá Cámara nativa → Modo Pro (DNG). Expert RAW puede tardar ~40s en fusionar HDR.",
    ),
    (
        "Pixel / Motorola / Nothing",
        "Tocar 2 veces 'Cargando este dispositivo por USB' → 'Transferencia de archivos' / 'PTP'",
        "Evitar: 'Sin transferencia de datos'",
        [
            "Desbloqueá el celular y abrí las opciones USB desde la cortina superior.",
            "Elegí 'Transferencia de archivos' o 'PTP' para exponer DCIM en Este equipo.",
        ],
        "Activá RAW+JPEG (.DNG) en la cámara para recibir negativos digitales reales.",
    ),
    (
        "Xiaomi / OnePlus / OPPO",
        "Elegir 'Transferir archivos' o 'Transferir fotos (PTP)' al conectar el cable",
        "Evitar: 'Solo cargar' y bloqueo de pantalla largo",
        [
            "Aceptá el aviso USB emergente de HyperOS / MIUI / ColorOS.",
            "Mantené la pantalla activa o ampliá el tiempo de suspensión USB.",
        ],
        "PhotoPic ignora automáticamente .thumbnails y espera a que el archivo termine de escribirse.",
    ),
    (
        "iPhone / iPad (iOS)",
        "Desbloquear pantalla → Tocar 'Confiar' → Ingresar código del iPhone",
        "Evitar: dejar el iPhone bloqueado o presionar 'No confiar'",
        [
            "Conectá el iPhone desbloqueado con cable USB-C / Lightning original o certificado.",
            "Cuando aparezca '¿Confiar en esta computadora?', tocá 'Confiar' e ingresá tu PIN.",
            "Verificá que aparezca 'Apple iPhone' bajo Este equipo en Windows.",
        ],
        "En iPhone Pro con Apple ProRAW activado, recibís .DNG y .HEIC originales vía WPD.",
    ),
    (
        "Canon EOS / Nikon",
        "Apagar Wi-Fi/NFC en la cámara y cerrar EOS Utility / NX Tether",
        "Evitar: Wi-Fi interno activo en Canon (apaga el puerto USB) o drivers Zadig/WinUSB",
        [
            "En Canon EOS desactivá el Wi-Fi / NFC en el menú para reactivar el USB.",
            "Cerrá EOS Utility, Lightroom Tether o Capture One para no bloquear WPD.",
            "Usá siempre el driver estándar Windows MTP/PTP (no Zadig WinUSB).",
        ],
        "Los RAW (.CR2/.CR3/.NEF) y JPG se separan automáticamente al entrar en la sesión.",
    ),
    (
        "Sony Alpha / Fujifilm",
        "Menú → Conexión USB → Elegir 'MTP' (no 'Almacenamiento masivo' ni 'PC Remote')",
        "Evitar: 'Almacenamiento masivo' y 'PC Remote' sin driver",
        [
            "En Sony Alpha configurá Conexión USB en 'MTP' o 'Auto'.",
            "En Fujifilm usá 'USB CARD READER' o 'AUTO' según soporte MTP.",
        ],
        "Para Live View 60 fps sin conflictos en Windows, usá capturadora HDMI→USB en DirectShow.",
    ),
]


class ConnectionValidatorDialog(QDialog):
    """Guides users through Windows WPD USB permissions, brand modes, and Canon/iOS/Android rules."""

    def __init__(self, current_device_status: str, parent=None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Validador y Guía de Conexión USB — PhotoPic")
        self.resize(780, 520)

        root = QVBoxLayout(self)
        root.setSpacing(AppSpacing.MD)

        status_lbl = QLabel(f"Estado WPD actual: {current_device_status}")
        status_lbl.setStyleSheet(
            f"background: {AppColors.ELEVATED_SURFACE}; border: 1px solid {AppColors.BORDER_SUBTLE}; "
            f"border-radius: 6px; padding: 8px 12px; color: {AppColors.TEXT_PRIMARY}; font-weight: 600;"
        )
        root.addWidget(status_lbl)

        note_lbl = QLabel(
            "Si tu teléfono está en 'Solo carga' o tu iPhone bloqueado sin tocar 'Confiar', "
            "Windows WPD oculta la carpeta DCIM hasta que cambies el modo USB."
        )
        note_lbl.setWordWrap(True)
        note_lbl.setStyleSheet(f"color: {AppColors.TEXT_SECONDARY}; font-size: 12px;")
        root.addWidget(note_lbl)

        selector_row = QHBoxLayout()
        selector_row.addWidget(QLabel("Equipo / Marca:"))
        self._combo = QComboBox()
        for idx, entry in enumerate(_BRAND_GUIDES):
            self._combo.addItem(entry[0], idx)
        self._combo.currentIndexChanged.connect(self._render_guide)
        selector_row.addWidget(self._combo, stretch=1)
        root.addLayout(selector_row)

        self._browser = QTextBrowser()
        self._browser.setStyleSheet(
            f"background: {AppColors.PANEL_SURFACE}; border: 1px solid {AppColors.BORDER_SUBTLE}; "
            "border-radius: 8px; padding: 14px;"
        )
        root.addWidget(self._browser, stretch=1)

        btn_row = QHBoxLayout()
        btn_row.addStretch()
        close_btn = QPushButton("Listo")
        close_btn.setObjectName("PrimaryButton")
        close_btn.clicked.connect(self.accept)
        btn_row.addWidget(close_btn)
        root.addLayout(btn_row)

        self._render_guide(0)

    def _render_guide(self, idx: int) -> None:
        if not (0 <= idx < len(_BRAND_GUIDES)):
            return
        name, path_summary, avoid, steps, raw_tip = _BRAND_GUIDES[idx]
        steps_html = "".join(f"<li>{s}</li>" for s in steps)
        self._browser.setHtml(
            f"<h2>{name}</h2>"
            f"<p><b>Ajuste correcto:</b> {path_summary}</p>"
            f"<p style='color:{AppColors.WARNING_AMBER};'><b>{avoid}</b></p>"
            f"<h4>Pasos en Windows (WPD)</h4><ol>{steps_html}</ol>"
            f"<p style='color:{AppColors.INFO_BLUE};'><b>RAW / Rendimiento:</b> {raw_tip}</p>"
        )
