import Foundation

/// A single step-by-step topic inside PhotoPic's built-in offline Help Center,
/// aligned with the formal BRD documentation in `photopic_ai_agent_docs/`.
package struct HelpTopic: Identifiable, Sendable, Equatable, Hashable {
    package let id: String
    package let docCode: String
    package let title: String
    package let subtitle: String
    package let iconSystemName: String
    package let summary: String
    package let steps: [String]
    package let tips: [String]

    package init(
        id: String,
        docCode: String,
        title: String,
        subtitle: String,
        iconSystemName: String,
        summary: String,
        steps: [String],
        tips: [String]
    ) {
        self.id = id
        self.docCode = docCode
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.summary = summary
        self.steps = steps
        self.tips = tips
    }
}

/// Complete offline catalog of operational guides embedded inside PhotoPic.
package enum HelpGuideCatalog {
    package static let allTopics: [HelpTopic] = [
        HelpTopic(
            id: "e2e-workflow",
            docCode: "DOC-01",
            title: "Flujo Completo de Estudio (E2E)",
            subtitle: "Del primer arranque a la entrega organizada",
            iconSystemName: "sparkles.rectangle.stack",
            summary: "PhotoPic no encierra tus fotos en una base de datos interna: visualiza directamente tus carpetas en disco y mueve pares RAW + JPG en tiempo real.",
            steps: [
                "1. Al abrir por primera vez, revisá el Paso 1 del Asistente Inicial (Auditoría de Hardware) y confirmá si querés IA activa o Modo Ligero.",
                "2. En el Paso 2, elegí tu Carpeta Raíz Global (ej. ~/Pictures/Sesiones_PhotoPic).",
                "3. Creá una sesión con '+ Nueva Sesión de Filtrado' (o ⌘N). PhotoPic genera RAW/, JPG/, Para_Edicion/{RAW,JPG} y Archivadas/{RAW,JPG}.",
                "4. Conectá tu cámara o celular por USB/Thunderbolt 4 (o vinculá una carpeta Watchfolder Wi-Fi) y empezá a disparar.",
                "5. Clasificá con → (Aprobar) o ← (Archivar) mientras revisás foco real al Zoom 1:1 con Barra Espaciadora."
            ],
            tips: [
                "Podés cerrar PhotoPic en cualquier momento: tus carpetas RAW/ y JPG/ quedan intactas para abrir en Lightroom, Capture One o Affinity."
            ]
        ),
        HelpTopic(
            id: "hardware-ai-mode",
            docCode: "DOC-02",
            title: "Auditor de Hardware y Modo Sin IA",
            subtitle: "Neural Engine, perfiles y cómo apagar la IA",
            iconSystemName: "cpu",
            summary: "El Apple Neural Engine es hardware físico integrado en chips Apple Silicon (M1–M5). En Macs Intel o PCs modestas la IA corre en CPU/GPU, por eso podés regularla o apagarla.",
            steps: [
                "1. Estudio Completo: recomendado en Apple Silicon con >= 12 GB RAM (revelado GPU + caras, ojos y poses de 19 articulaciones).",
                "2. Equilibrado: recomendado en Intel o equipos con 8–11 GB RAM (analiza rostros y parpadeo sin esqueleto corporal pesado).",
                "3. Modo Ligero (Sin IA): apaga toda la IA en segundo plano para máxima fluidez en equipos antiguos o sesiones masivas.",
                "4. Podés cambiar de perfil o apagar/prender los switches en vivo desde el ícono de engrane → General y Rendimiento."
            ],
            tips: [
                "Desactivar la IA nunca detiene la captura tethered ni el revelado RAW en GPU Metal."
            ]
        ),
        HelpTopic(
            id: "usb-wifi-watchfolder",
            docCode: "DOC-03",
            title: "Conexión USB, Android PTP y Wi-Fi",
            subtitle: "Cable directo, Bonjour PTP/IP y Watchfolder",
            iconSystemName: "cable.connector",
            summary: "Soporta conexión directa USB/Thunderbolt, detección Bonjour PTP/IP por Wi-Fi y monitoreo de carpeta (Watchfolder) para transmisores inalámbricos o FTP.",
            steps: [
                "1. Cámaras DSLR/Mirrorless: conectá por USB/Thunderbolt. Si macOS muestra 'Ocupado por macOS', abrí la píldora superior y tocá 'Liberar macOS'.",
                "2. Android por USB: desbloqueá el teléfono y elegí 'Transferir imágenes (PTP)' en la notificación USB. Activá modo Pro/Expert RAW (.DNG) o permití JPG fallback en Dispositivos.",
                "3. iPhone / iPad: conectá por cable, desbloqueá y tocá 'Confiar en esta computadora'.",
                "4. Transmisor Wi-Fi / FTP / Air Direct: dentro de una sesión, pulsá 'Vincular Carpeta / Wi-Fi...' para monitorear al vuelo la carpeta donde aterrizan tus fotos.",
                "5. Escudo Anti-Galería Vieja: al conectar cámara, celular o carpeta, PhotoPic indexa los archivos previos y jamás descarga fotos antiguas."
            ],
            tips: [
                "El Bluetooth de las cámaras no tiene ancho de banda para RAWs completos; usá USB-C/Thunderbolt o transmisores Wi-Fi / FTP hacia Watchfolder."
            ]
        ),
        HelpTopic(
            id: "culling-raw-folders",
            docCode: "DOC-04",
            title: "Culling RAW, Zoom 1:1 y Pares RAW+JPG",
            subtitle: "Atajos de estudio y carpetas separadas por tipo",
            iconSystemName: "folder.badge.gearshape",
            summary: "Cada decisión en el visor mueve automáticamente el archivo RAW (y su .XMP) junto con su contraparte JPG/HEIC manteniendo RAW/ y JPG/ separados en cada carpeta.",
            steps: [
                "1. Navegar sin mover nada: Flecha Arriba (↑) y Flecha Abajo (↓).",
                "2. Aprobar (→ o Swipe Derecha): mueve el RAW a Para_Edicion/RAW/ y su copia JPG a Para_Edicion/JPG/.",
                "3. Archivar (← o Swipe Izquierda): mueve el RAW a Archivadas/RAW/ y su copia JPG a Archivadas/JPG/.",
                "4. Zoom 1:1 píxel real: presioná Barra Espaciadora (o sostené clic y arrastrá sobre ojos/detalles) para evaluar nitidez del sensor puro sin miniaturas JPG.",
                "5. Deshacer (⌘Z): devuelve tanto el RAW (+ .XMP) como su JPG a su carpeta original."
            ],
            tips: [
                "Si activás 'Seguir última captura', el visor salta automáticamente a cada nuevo disparo que entra por cable o Wi-Fi."
            ]
        ),
        HelpTopic(
            id: "ai-tags-xmp",
            docCode: "DOC-05",
            title: "Auto-Etiquetado IA, Filtros y Sidecars .XMP",
            subtitle: "Caras, ojos cerrados, poses y compatibilidad Lightroom",
            iconSystemName: "tag.fill",
            summary: "Cuando la IA está activa, cada imagen recibe etiquetas automáticas filtrables desde la barra superior y guardadas en formato estándar Adobe .XMP.",
            steps: [
                "1. Conteo y encuadre: Sin personas, 1 persona (Individual), 2 personas (Pareja), Grupo, Primer plano, Plano medio o Cuerpo entero.",
                "2. Control de parpadeo: Ojos abiertos vs alerta ámbar 'Ojos cerrados' calculada con Eye Aspect Ratio (EAR).",
                "3. Poses detectadas: De pie, Sentado, Brazos arriba, Manos en cintura, Pose dinámica.",
                "4. Etiquetas manuales: tocá '+ Etiqueta' en el HUD inferior para agregar tus propios tags (ej. Favorita, Novia).",
                "5. Cada etiqueta viaja en el archivo .xmp junto al RAW cuando lo aprobás o archivás, lista para Lightroom / Capture One."
            ],
            tips: [
                "Hacé clic en cualquier chip de la barra 'IA:' arriba del visor para filtrar al instante solo las fotos con esa etiqueta."
            ]
        ),
        HelpTopic(
            id: "archived-cleanup",
            docCode: "DOC-06",
            title: "Recuperación y Limpieza en Archivadas",
            subtitle: "Recuperar descartes o liberar espacio definitivamente",
            iconSystemName: "trash",
            summary: "La pestaña Archivadas funciona como zona segura de revisión antes de borrar definitivamente archivos del disco.",
            steps: [
                "1. Entrá a la pestaña 'Archivadas' en la barra superior de la sesión.",
                "2. Para rescatar una foto: seleccionala y pulsá 'Recuperar para Edición' (mueve RAW + JPG hacia Para_Edicion/).",
                "3. Para borrar una foto del disco: pulsá 'Eliminar archivo...' y confirmá en el Popover (borra RAW, .XMP y su JPG asociado si corresponde).",
                "4. Para liberar todo el espacio descartado de una vez: pulsá 'Vaciar carpeta...' y confirmá en el Popover. RAW/ y Para_Edicion/ nunca se tocan."
            ],
            tips: [
                "La eliminación definitiva no se puede deshacer con ⌘Z; por seguridad siempre exige confirmación en el Popover."
            ]
        )
    ]
}
