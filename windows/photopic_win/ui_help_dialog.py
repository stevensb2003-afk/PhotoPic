"""Built-in offline Help Center dialog for PhotoPic Windows."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QPushButton,
    QTextBrowser,
    QVBoxLayout,
)

from .design_system import AppColors, AppSpacing

_HELP_TOPICS: list[tuple[str, str, str]] = [
    (
        "DOC-01 · Flujo Completo de Estudio (E2E)",
        "Flujo de trabajo de principio a fin",
        "<p><b>PhotoPic</b> lee tus carpetas directamente en disco y nunca encierra tus fotos en un catálogo interno.</p>"
        "<ol>"
        "<li>En el <b>Asistente Inicial</b>, revisá la auditoría de CPU/RAM y elegí tu perfil IA (o Modo Ligero sin IA).</li>"
        "<li>Elegí tu <b>Carpeta Raíz Global</b>.</li>"
        "<li>Creá una sesión nueva: se generan <code>RAW/</code>, <code>JPG/</code>, <code>Para_Edicion/{RAW,JPG}</code> y <code>Archivadas/{RAW,JPG}</code>.</li>"
        "<li>Conectá tu cámara/celular USB (WPD) o vinculá una carpeta Wi-Fi/SD con <b>Vincular Carpeta/SD USB...</b>.</li>"
        "<li>Clasificá con <b>→</b> (Aprobar) o <b>←</b> (Archivar) y verificá foco 1:1 con <b>Espacio</b>.</li>"
        "</ol>",
    ),
    (
        "DOC-02 · Auditor de Hardware y Modo Sin IA",
        "Perfiles y desactivación de IA",
        "<p>En Windows, la IA corre en CPU mediante MediaPipe/OpenCV. Podés cambiar de perfil en cualquier momento desde <b>Rendimiento e IA...</b>.</p>"
        "<ul>"
        "<li><b>Estudio Completo:</b> rostros, ojos y poses corporales.</li>"
        "<li><b>Equilibrado:</b> solo rostros/ojos rápidos.</li>"
        "<li><b>Modo Ligero (Sin IA):</b> apaga la IA por completo para PCs modestas.</li>"
        "</ul>",
    ),
    (
        "DOC-03 · Tethering USB WPD y Watchfolder Wi-Fi",
        "Conexión de cámaras y transmisores inalámbricos",
        "<p>Windows soporta teléfonos Android (MTP/PTP), iPhone y cámaras PTP mediante WPD, además de monitoreo en vivo de carpetas (Watchfolder).</p>"
        "<p>Para transmisores Wi-Fi (Air Direct, CamRanger, FTP local o EOS Utility/NX Tether), pulsá <b>Vincular Carpeta/SD USB...</b> y elegí la carpeta de destino.</p>",
    ),
    (
        "DOC-04 · Pares RAW + JPG y Atajos de Estudio",
        "Clasificación sincronizada RAW + JPG",
        "<p>Cuando aprobás (<b>→</b>) o archivás (<b>←</b>), PhotoPic mueve el <b>RAW</b> (y su <code>.xmp</code>) a <code>RAW/</code> dentro de la carpeta destino y también mueve automáticamente su copia <b>JPG</b> a <code>JPG/</code> dentro de esa misma carpeta.</p>"
        "<p><b>Atajos:</b> <code>↑/↓</code> navegar · <code>→</code> Para Edición · <code>←</code> Archivar · <code>Espacio</code> Zoom 1:1 · <code>Ctrl+Z</code> Deshacer.</p>",
    ),
    (
        "DOC-05 · Limpieza Segura en Archivadas",
        "Recuperar o eliminar archivos definitivamente",
        "<p>En la pestaña <b>Archivadas</b> podés rescatar una foto con <b>Recuperar para Edición</b> o liberar espacio en disco con <b>Eliminar archivo...</b> y <b>Vaciar Archivadas...</b> mediante un Popover de confirmación.</p>",
    ),
]


class HelpCenterDialog(QDialog):
    """Offline searchable Help Center modal for Windows."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Centro de Ayuda de PhotoPic")
        self.resize(780, 520)

        root = QVBoxLayout(self)
        root.setSpacing(AppSpacing.MD)

        self._search = QLineEdit()
        self._search.setPlaceholderText("Buscar tema o atajo...")
        self._search.textChanged.connect(self._populate_list)
        root.addWidget(self._search)

        split = QHBoxLayout()
        self._list = QListWidget()
        self._list.setFixedWidth(280)
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
        self._populate_list("")

    def _populate_list(self, query: str) -> None:
        q = query.strip().lower()
        self._filtered = [t for t in _HELP_TOPICS if not q or q in t[0].lower() or q in t[2].lower()]
        self._list.clear()
        for title, _, _ in self._filtered:
            QListWidgetItem(title, self._list)
        if self._filtered:
            self._list.setCurrentRow(0)
        else:
            self._viewer.setHtml("<p>Sin resultados.</p>")

    def _show_selected(self, row: int) -> None:
        if 0 <= row < len(self._filtered):
            title, subtitle, body = self._filtered[row]
            self._viewer.setHtml(f"<h2>{title}</h2><p style='color:{AppColors.TEXT_SECONDARY};'>{subtitle}</p>{body}")
