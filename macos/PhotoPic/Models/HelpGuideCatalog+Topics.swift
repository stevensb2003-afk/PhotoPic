import Foundation

extension HelpGuideCatalog {
    package static let allTopics: [HelpTopic] = [
        HelpTopic(
            id: "e2e-workflow",
            docCode: "DOC-01",
            category: .setupFlow,
            title: "Flujo Completo de Estudio (E2E)",
            subtitle: "Del primer arranque a la entrega organizada",
            iconSystemName: "sparkles.rectangle.stack",
            keywords: ["inicio", "e2e", "sesion", "carpeta raiz", "flujo", "lightroom", "dmg"],
            summary: "PhotoPic no encierra tus fotos en un catálogo cerrado: visualiza directamente tus carpetas en disco y sincroniza pares RAW + JPG conforme trabajás.",
            steps: [
                "1. Revisá el Paso 1 del Asistente Inicial (Auditoría de Hardware) y confirmá si querés IA completa o Modo Ligero.",
                "2. En el Paso 2 elegí tu Carpeta Raíz Global (ej. ~/Pictures/Sesiones_PhotoPic).",
                "3. Creá una sesión con '+ Nueva Sesión de Filtrado' (⌘N): se generan RAW/, JPG/, Para_Edicion/{RAW,JPG} y Archivadas/{RAW,JPG}.",
                "4. Conectá tu cámara o celular USB (o activá Vista en Vivo / Watchfolder) y empezá a disparar.",
                "5. Revisá foco real al Zoom 1:1 (Espacio), aprobá con → o descartá con ←."
            ],
            canDo: [
                "Abrir cualquier carpeta de sesión directo en Lightroom Classic, Capture One o Affinity.",
                "Trabajar 100% sin internet ni servidores web locales."
            ],
            limitations: [
                "PhotoPic no es un editor de color ni revela ajustes permanentes sobre el RAW (solo clasifica, etiqueta y previsualiza en GPU).",
                "Este .dmg actual está compilado solo para Apple Silicon (arm64); no abre en Macs Intel antiguos."
            ],
            tips: [
                "Al instalar en otra Mac por primera vez, abrí con clic derecho → Abrir (una sola vez) porque usa firma local ad-hoc."
            ]
        ),
        HelpTopic(
            id: "hardware-ai-mode",
            docCode: "DOC-02",
            category: .setupFlow,
            title: "Auditor de Hardware y Modo Sin IA",
            subtitle: "Neural Engine, perfiles y cómo apagar la IA",
            iconSystemName: "cpu",
            keywords: ["neural engine", "ram", "cpu", "metal", "lento", "apagar ia", "modo ligero", "equilibrado"],
            summary: "El Apple Neural Engine es silicio físico integrado en chips Apple Silicon (M1–M5). En Intel o Windows la IA corre en CPU/GPU, por eso podés regularla desde el arranque.",
            steps: [
                "1. Estudio Completo: Apple Silicon (>= 12 GB RAM) con GPU RAW + rostros, ojos y poses de 19 puntos.",
                "2. Equilibrado: Intel o 8–11 GB RAM con conteo rápido de rostros y parpadeo, sin poses corporales pesadas.",
                "3. Modo Ligero (Sin IA): 0% IA en segundo plano para máxima fluidez en computadoras modestas.",
                "4. Cambiá el perfil en vivo sin cerrar tu sesión desde Configuración → General y Rendimiento."
            ],
            canDo: [
                "Prender o apagar caras y poses por separado en cualquier instante.",
                "Re-auditar tu equipo con el botón Re-auditar si cambiás de configuración."
            ],
            limitations: [
                "Si tu Mac es Intel (sin Neural Engine) o tu PC Windows tiene <= 4 núcleos, activar poses completas ralentizará el ritmo de ráfagas.",
                "La IA no reconoce identidad de personas por nombre (solo cuenta personas, rostros, parpadeo y postura)."
            ],
            tips: [
                "Apagar la IA jamás detiene el tethering USB ni el revelado RAW en Metal."
            ]
        ),
        HelpTopic(
            id: "usb-wifi-watchfolder",
            docCode: "DOC-03",
            category: .connectionsLive,
            title: "Conexión USB, Android PTP y Wi-Fi",
            subtitle: "Cable directo, Bonjour PTP/IP y Watchfolder",
            iconSystemName: "cable.connector",
            keywords: ["usb", "thunderbolt", "android", "ptp", "mtp", "iphone", "wifi", "bluetooth", "ptpcamera", "watchfolder", "ftp", "expert raw", "tethering", "midi", "canon", "sony", "validador"],
            summary: "Recibe capturas por cable USB-C/Thunderbolt 4, cámaras Bonjour Wi-Fi PTP/IP (macOS) y Watchfolder, con Validador USB físico (IOKit) por marca.",
            steps: [
                "1. Cámara Canon / Nikon: apagá el Wi-Fi/NFC interno de la cámara (en Canon desactiva el puerto USB) y cerrá EOS Utility; si macOS la captura, tocá Liberar macOS.",
                "2. Cámara Sony / Fujifilm: poné Conexión USB en 'MTP' o 'PTP' (no Mass Storage ni PC Remote sin driver).",
                "3. Android USB: elegí 'Transferir imágenes (PTP)' (NO 'USB Tethering' ni 'MIDI'). Usá Modo Pro (RAW/DNG) para descarga ~1s.",
                "4. iPhone / iPad: desbloqueá, tocá 'Confiar' e ingresá tu código; si activás Apple ProRAW (.DNG), PhotoPic fuerza activos originales.",
                "5. Si conectaste el cable y no monta, abrí Configuración → Dispositivos para usar el Validador de 3 etapas y despertar el diálogo de permiso."
            ],
            canDo: [
                "Escudo Anti-Galería Vieja y cero pérdidas: acepta disparos en vivo aunque la cámara tenga la pila de fecha/reloj reiniciada.",
                "Si llega una foto en el Dashboard sin sesión abierta, PhotoPic crea/abre 'Sesion_Rapida_AAAA-MM-DD' automáticamente para no perder el RAW.",
                "Detecta físicamente teléfonos en 'Solo carga' o cámaras ocultas vía IOKit y muestra la guía exacta de esa marca."
            ],
            limitations: [
                "Bluetooth NO sirve para transferir RAWs de cámara a full calidad por falta de ancho de banda.",
                "En Android con Samsung Expert RAW (50MP HDR multiframe), el celular puede tardar ~35–45s en procesar cada toma y dejar el .DNG cacheado en 0 bytes sobre USB PTP; para tethering rápido en RAW usá Modo Pro (.DNG) o Watchfolder Wi-Fi.",
                "En macOS, Android en modo MTP ('Transferir archivos'), USB Tethering o MIDI no sirve para ImageCaptureCore: usá 'Transferir imágenes (PTP)'."
            ],
            tips: [
                "Por seguridad, PhotoPic bloquea vincular como Watchfolder una subcarpeta de tus sesiones para evitar bucles infinitos."
            ]
        ),
        HelpTopic(
            id: "live-view-guide",
            docCode: "DOC-07",
            category: .connectionsLive,
            title: "Vista en Vivo (Live View) por Sistema",
            subtitle: "UVC / HDMI-USB nativo + puente gphoto2 USB",
            iconSystemName: "video.viewfinder",
            keywords: ["live view", "vista en vivo", "hdmi", "uvc", "gphoto2", "canon 70d", "camara en vivo", "disparar", "zadig", "cuadricula"],
            summary: "La pestaña 'Vista en Vivo' muestra el encuadre en tiempo real con cuadrícula 3×3, máscaras 3:2 / 4:5 / 16:9 y disparo remoto, adaptándose al mejor método de cada sistema.",
            steps: [
                "1. Abrí la pestaña 'Vista en Vivo' en la barra superior de cualquier sesión.",
                "2. Método Universal (macOS y Windows): conectá una cámara moderna con USB Streaming (UVC) o una DSLR vieja con capturadora HDMI→USB y pulsá 'Iniciar Vista en Vivo'.",
                "3. Método DSLR USB Clásica (solo macOS opcional): instalá gphoto2 con 'brew install gphoto2', cambiá el selector arriba a 'DSLR USB (gphoto2)' y pulsá Iniciar.",
                "4. Usá 'Disparar Cámara (PTP)' / 'Disparar y Descargar RAW' o 'Guardar Cuadro de Referencia'."
            ],
            canDo: [
                "En modo UVC / HDMI-USB corre hasta 30–60 fps sin cortar el tethering USB de fotos.",
                "Si tu cámara PTP soporta disparo remoto (cameraDeviceCanTakePicture), podés disparar desde PhotoPic mientras ves HDMI.",
                "En macOS con gphoto2 instalado podés ver el visor USB y descargar RAWs con un solo cable en Canon 70D / Nikon / Sony."
            ],
            limitations: [
                "ImageCaptureCore de Apple NO transmite video Live View nativo por USB en DSLRs antiguas sin HDMI ni gphoto2.",
                "El modo 'DSLR USB (gphoto2)' NO viene empaquetado dentro del .dmg (requiere 'brew install gphoto2') y pausa temporalmente el PTP de macOS mientras transmite.",
                "En Windows se usa UVC/HDMI DirectShow por estabilidad; usar libgphoto2 en Windows obligaría a reemplazar el driver USB con Zadig (WinUSB), rompiendo WPD."
            ],
            tips: [
                "La combinación más fluida en sesiones pro es HDMI→USB económico ($20) para Live View 60fps + cable USB para pasar el RAW puro sin conflictos."
            ]
        ),
        HelpTopic(
            id: "culling-raw-folders",
            docCode: "DOC-04",
            category: .foldersLimits,
            title: "Culling RAW GPU, Zoom 1:1 y Pares RAW+JPG",
            subtitle: "Atajos de estudio y separación automática RAW / JPG",
            iconSystemName: "folder.badge.gearshape",
            keywords: ["zoom", "1:1", "atalos", "flechas", "para_edicion", "raw", "jpg", "deshacer", "cmd+z", "formatos"],
            summary: "Cada clasificación mueve simultáneamente el RAW (y su .XMP) a <Destino>/RAW/ y su contraparte JPG/HEIC a <Destino>/JPG/. Admite 25 formatos RAW y 11 móviles.",
            steps: [
                "1. ↑ y ↓: recorrer fotos pendientes sin mover ningún archivo.",
                "2. → o Swipe Derecha: aprueba hacia Para_Edicion/RAW/ + Para_Edicion/JPG/.",
                "3. ← o Swipe Izquierda: archiva hacia Archivadas/RAW/ + Archivadas/JPG/.",
                "4. Espacio o clic sostenido + arrastrar: Zoom 1:1 píxel real sobre el sensor revelado (nunca miniaturas JPG).",
                "5. ⌘Z (Ctrl+Z en Windows): devuelve tanto el RAW (+.xmp) como su JPG a su lugar anterior."
            ],
            canDo: [
                "Enruta automáticamente .JPG/.HEIC tardíos directo a Para_Edicion/JPG/ o Archivadas/JPG/ si ya moviste el RAW.",
                "Revela 25 formatos RAW (.CR2, .CR3, .DNG, .ARW, .NEF, .RAF, .ORF, .RW2, .3FR, .IIQ, etc.) desde datos reales del sensor."
            ],
            limitations: [
                "Si disparás RAW+JPG desde cámaras desconocidas cuyo formato RAW propietario aún no esté decodificado por Core Image del sistema (ej. modelos recién lanzados antes de actualizar macOS), CIRAWFilter no podrá abrir el RAW.",
                "En Windows, archivos muy exóticos pueden depender del soporte de LibRaw incluido."
            ],
            tips: [
                "Activá 'Seguir última captura' en la barra inferior solo cuando quieras que el visor salte automáticamente al disparo más reciente."
            ]
        ),
        HelpTopic(
            id: "ai-tags-xmp",
            docCode: "DOC-05",
            category: .cullingAI,
            title: "Auto-Etiquetado IA, Filtros y Sidecars .XMP",
            subtitle: "Caras, ojos cerrados, poses y Lightroom",
            iconSystemName: "tag.fill",
            keywords: ["tags", "etiquetas", "xmp", "ojos cerrados", "ear", "poses", "pareja", "grupo", "finder"],
            summary: "Cuando la IA está encendida, analiza cada foto en memoria, permite filtrar en vivo y guarda etiquetas estándar Adobe .XMP que viajan con cada RAW.",
            steps: [
                "1. Conteo y encuadre automático: Sin personas, Individual, Pareja, Grupo, Primer plano, Plano medio o Cuerpo entero.",
                "2. Control de ojos (EAR): emite alerta ámbar 'Ojos cerrados' o 'Ojos abiertos'.",
                "3. Poses corporales: De pie, Sentado, Brazos arriba, Manos en cintura, Pose dinámica.",
                "4. Tocá cualquier chip en la barra 'IA:' superior para filtrar pendientes al instante, o agregá tags propios con '+ Etiqueta'."
            ],
            canDo: [
                "Escribe sidecars estándar .xmp compatibles con Adobe Lightroom Classic, Camera Raw y Capture One.",
                "Aplica macOS Finder Tags directos para buscar fotos desde Spotlight."
            ],
            limitations: [
                "No modifica los metadatos EXIF/IPTC incrustados dentro del archivo RAW binario (siempre usa sidecar .xmp no destructivo).",
                "Sujetos muy pequeños de espaldas o en contraluz extremo pueden marcarse como 'Sin personas'."
            ],
            tips: [
                "Si activás modo 'Equilibrado', seguís recibiendo conteo de personas, rostros y 'Ojos cerrados' sin gastar recursos en poses corporales."
            ]
        ),
        HelpTopic(
            id: "archived-cleanup",
            docCode: "DOC-06",
            category: .foldersLimits,
            title: "Recuperación y Limpieza en Archivadas",
            subtitle: "Rescatar descartes o eliminar archivos del disco",
            iconSystemName: "trash",
            keywords: ["archivar", "archivadas", "eliminar", "borrar", "popover", "vaciar", "recuperar", "espacio"],
            summary: "La pestaña Archivadas permite inspeccionar descartes antes de borrarlos del disco con seguridad.",
            steps: [
                "1. Abrí la pestaña 'Archivadas' dentro de tu sesión.",
                "2. Para rescatar una foto: seleccionala y pulsá 'Recuperar para Edición' (mueve RAW + JPG a Para_Edicion/).",
                "3. Para borrar una foto del disco: pulsá 'Eliminar archivo...' y confirmá en el Popover.",
                "4. Para vaciar toda la carpeta: pulsá 'Vaciar carpeta...' y confirmá en el Popover."
            ],
            canDo: [
                "Elimina físicamente el RAW en Archivadas/RAW/, su .XMP, su entrada JSON y también su par en Archivadas/JPG/.",
                "Bloquea cualquier borrado fuera de Archivadas/ para proteger tus fotos en RAW/ y Para_Edicion/."
            ],
            limitations: [
                "La eliminación definitiva borra directo del sistema de archivos (no va a la Papelera ni se deshace con ⌘Z).",
                "No desinstala la aplicación ni borra otras sesiones fuera de la actual."
            ],
            tips: [
                "Revisá siempre el tamaño y nombre en el Popover rojo antes de pulsar 'Eliminar para siempre'."
            ]
        )
    ]
}
