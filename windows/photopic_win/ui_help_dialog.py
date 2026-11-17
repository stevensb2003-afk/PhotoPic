"""Built-in searchable Help Center dialog with categories, capabilities, and limitations."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QHBoxLayout,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QTextBrowser,
    QVBoxLayout,
)

from .design_system import AppColors, AppSpacing

_HELP_TOPICS: list[dict] = [
    {
        "code": "DOC-01",
        "cat": "Inicio y Hardware",
        "title": "Flujo Completo de Estudio (E2E)",
        "kw": "inicio e2e sesion carpeta raiz flujo lightroom exe",
        "summary": "PhotoPic lee y ordena directamente tus carpetas del disco sin encerrar tus fotos en un catálogo interno.",
        "can_do": [
            "Abrir cualquier carpeta de sesión en Lightroom, Capture One o Affinity.",
            "Trabajar 100% offline sin internet ni servidores localhost.",
        ],
        "limits": [
            "No aplica edición de color destructiva: su objetivo es captura, revisión 1:1, etiquetado y clasificación física.",
        ],
        "steps": [
            "Completá la auditoría de hardware en el Asistente Inicial y elegí tu Carpeta Raíz Global.",
            "Creá una sesión con '+ Nueva Sesión de Filtrado' para generar RAW/, JPG/, Para_Edicion/{RAW,JPG} y Archivadas/{RAW,JPG}.",
            "Conectá tu cámara/celular o vinculá un Watchfolder Wi-Fi/SD.",
            "Clasificá con → (Aprobar) o ← (Archivar) y validá foco 1:1 con Espacio.",
        ],
    },
    {
        "code": "DOC-02",
        "cat": "Inicio y Hardware",
        "title": "Auditor de Hardware y Modo Sin IA",
        "kw": "cpu ram mediapipe opencv lento apagar ia modo ligero equilibrado",
        "summary": "En Windows la IA ejecuta sobre CPU con MediaPipe/OpenCV. El auditor evalúa núcleos y RAM para elegir el mejor perfil.",
        "can_do": [
            "Activar o apagar auto-etiquetado facial y poses desde 'Rendimiento e IA...'.",
            "Cambiar a Modo Ligero (Sin IA) en PCs modestas para priorizar tethering y revelado LibRaw.",
        ],
        "limits": [
            "Windows no dispone de Apple Neural Engine físico: activar poses en PCs <= 4 núcleos consumirá más CPU.",
        ],
        "steps": [
            "Abrí 'Rendimiento e IA...' en la barra superior de Inicio.",
            "Elegí entre Estudio Completo, Equilibrado (solo rostros) o Modo Ligero (Sin IA).",
        ],
    },
    {
        "code": "DOC-03",
        "cat": "Conexión y Vivo",
        "title": "Tethering USB WPD y Watchfolder Wi-Fi",
        "kw": "usb wpd mtp ptp android iphone wifi watchfolder ftp canon sony zadig validador",
        "summary": "Windows recibe capturas vía WPD (MTP/PTP) y monitoreo Watchfolder, con botón 'Validar USB...' por marca.",
        "can_do": [
            "Soporta Android tanto en MTP como en PTP, iPhone (tras tocar 'Confiar') y lectores SD/CFexpress.",
            "Protege carretes llenos con el Escudo Anti-Galería Vieja e ignora carpetas ocultas (.thumbnails).",
        ],
        "limits": [
            "Bluetooth no soporta transferencia RAW en vivo; para transmisores inalámbricos usá Watchfolder.",
            "En Canon EOS apagá el Wi-Fi interno para reactivar USB; en Sony elegí USB MTP (evitá Zadig WinUSB).",
            "Samsung Expert RAW puede demorar ~40s procesando HDR; para disparo rápido usá Modo Pro (.DNG).",
        ],
        "steps": [
            "Conectá el cable USB (cambiá Android de 'Solo carga' a MTP/PTP o desbloqueá iPhone y tocá 'Confiar').",
            "Si no aparece, abrí 'Validar USB...' arriba en Inicio o vinculá un Watchfolder Wi-Fi/SD.",
        ],
    },
    {
        "code": "DOC-07",
        "cat": "Conexión y Vivo",
        "title": "Vista en Vivo — Android IP, iOS y Cámaras",
        "kw": "live view vista en vivo hdmi uvc directshow zadig winusb android ip webcam droidcam iphone",
        "summary": "Soporta Stream IP Wi-Fi MJPEG para teléfonos Android en paralelo al cable WPD, además de cámaras UVC / HDMI-USB en DirectShow.",
        "can_do": [
            "Conectar Android mediante 'Stream IP / Android Wi-Fi' (IP Webcam o DroidCam) mientras entran fotos RAW por WPD.",
            "Ver video de cámaras UVC, Pixel/Moto en modo Webcam USB o capturadoras HDMI→USB sin reemplazar drivers.",
        ],
        "limits": [
            "Samsung One UI oculta el modo 'Webcam USB' y USB PTP/MTP solo transporta fotos: usá URL IP Wi-Fi o DroidCam.",
            "La Cámara de Continuidad nativa de Apple solo funciona en Mac (en Windows usá Camo/EpocCam como webcam virtual).",
            "DSLRs clásicas sin HDMI ni UVC no transmiten Live View sin Zadig (WinUSB), lo cual rompería WPD.",
        ],
        "steps": [
            "Android: abrí IP Webcam (:8080/video), pegá la URL en 'Stream IP / Android Wi-Fi' y pulsá 'Iniciar Vista en Vivo'.",
            "Cámaras / HDMI: elegí tu Entrada Video / HDMI y pulsá 'Iniciar Vista en Vivo'.",
        ],
    },
    {
        "code": "DOC-04",
        "cat": "Carpetas y Límites",
        "title": "Grupos Máster, Timer, Inspector y Borrado",
        "kw": "raw jpg para_edicion archivadas eliminar grupo master timer temporizador exif buscar tags",
        "summary": "Aprobar o archivar mueve RAW (+ .xmp) y JPG juntos; ahora además podés agrupar sesiones en Carpetas Máster, cronometrar la sesión desde la 1ª foto, inspeccionar EXIF sin tapar la foto y eliminar proyectos completos con confirmación.",
        "can_do": [
            "Filtrar sesiones por texto, Carpeta Máster o #etiquetas siendo 100% retrocompatible con sesiones planas antiguas.",
            "Ver ISO, apertura, obturación, focal, lente, MP y etiquetas en el panel flotante lateral derecho sin estorbar la foto.",
            "Recuperar descartes en Archivadas o borrar definitivamente un proyecto entero tras confirmar el total de fotos.",
        ],
        "limits": [
            "El borrado definitivo de proyectos o archivos en Archivadas no va a la Papelera ni se deshace con Ctrl+Z.",
        ],
        "steps": [
            "Usá ↑/↓ para navegar, → aprobar, ← archivar, Espacio para Zoom 1:1 y arrastrá con el mouse sobre la foto para swipe.",
            "El timer arranca solo con la 1ª foto (desactivable en 'Rendimiento e IA...') o manualmente arriba.",
        ],
    },
]


class HelpCenterDialog(QDialog):
    """Offline searchable Help Center modal with categories and honest limitations."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Centro de Ayuda y Limitaciones — PhotoPic")
        self.resize(840, 560)

        root = QVBoxLayout(self)
        root.setSpacing(AppSpacing.MD)

        search_row = QHBoxLayout()
        self._category = QComboBox()
        for cat in ("Todos", "Inicio y Hardware", "Conexión y Vivo", "Carpetas y Límites"):
            self._category.addItem(cat, cat)
        self._category.currentIndexChanged.connect(self._refresh_list)
        search_row.addWidget(self._category)

        self._search = QLineEdit()
        self._search.setPlaceholderText("Buscar tema, atajo o limitación (ej. hdmi, gphoto2, raw, ptpcamera)...")
        self._search.textChanged.connect(self._refresh_list)
        search_row.addWidget(self._search, stretch=1)

        clear_btn = QPushButton("Limpiar")
        clear_btn.clicked.connect(lambda: (self._search.clear(), self._category.setCurrentIndex(0)))
        search_row.addWidget(clear_btn)
        root.addLayout(search_row)

        split = QHBoxLayout()
        self._list = QListWidget()
        self._list.setFixedWidth(290)
        self._list.currentRowChanged.connect(self._show_selected)
        split.addWidget(self._list)

        self._viewer = QTextBrowser()
        self._viewer.setStyleSheet(
            f"background: {AppColors.PANEL_SURFACE}; border: 1px solid {AppColors.BORDER_SUBTLE}; "
            "border-radius: 8px; padding: 14px;"
        )
        split.addWidget(self._viewer, stretch=1)
        root.addLayout(split, stretch=1)

        close_row = QHBoxLayout()
        close_row.addStretch()
        close_btn = QPushButton("Listo")
        close_btn.setObjectName("PrimaryButton")
        close_btn.clicked.connect(self.accept)
        close_row.addWidget(close_btn)
        root.addLayout(close_row)

        self._filtered = list(_HELP_TOPICS)
        self._refresh_list()

    def _refresh_list(self) -> None:
        cat = self._category.currentData() or "Todos"
        q = self._search.text().strip().lower()
        self._filtered = [
            t for t in _HELP_TOPICS
            if (cat == "Todos" or t["cat"] == cat)
            and (
                not q
                or q in t["title"].lower()
                or q in t["kw"]
                or q in t["summary"].lower()
                or any(q in s.lower() for s in t["can_do"] + t["limits"] + t["steps"])
            )
        ]
        self._list.clear()
        for t in self._filtered:
            QListWidgetItem(f"{t['code']} · {t['title']}", self._list)
        if self._filtered:
            self._list.setCurrentRow(0)
        else:
            self._viewer.setHtml("<p>No hay temas coincidentes con tu búsqueda.</p>")

    def _show_selected(self, row: int) -> None:
        if not (0 <= row < len(self._filtered)):
            return
        t = self._filtered[row]
        can_html = "".join(f"<li>{x}</li>" for x in t["can_do"])
        lim_html = "".join(f"<li>{x}</li>" for x in t["limits"])
        step_html = "".join(f"<li>{x}</li>" for x in t["steps"])
        self._viewer.setHtml(
            f"<h2>{t['title']}</h2>"
            f"<p style='color:{AppColors.TEXT_SECONDARY};'>{t['summary']}</p>"
            f"<h4 style='color:{AppColors.APPROVE_GREEN};'>Qué SÍ podés hacer</h4><ul>{can_html}</ul>"
            f"<h4 style='color:{AppColors.WARNING_AMBER};'>Limitaciones reales · Qué NO hace</h4><ul>{lim_html}</ul>"
            f"<h4>Guía Paso a Paso</h4><ol>{step_html}</ol>"
        )
