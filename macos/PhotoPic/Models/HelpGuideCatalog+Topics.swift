import Foundation

extension HelpGuideCatalog {
    package static let allTopics: [HelpTopic] = [
        HelpTopic(
            id: "e2e-workflow",
            docCode: "DOC-01",
            category: .setupFlow,
            title: "Flujo de Trabajo",
            subtitle: "Del primer arranque a la entrega organizada",
            iconSystemName: "square.stack.3d.up",
            keywords: ["inicio", "e2e", "sesion", "carpeta raiz", "flujo", "lightroom", "dmg", "importar", "carpeta", "offline"],
            summary: "PhotoPic no encierra tus fotos en un catálogo cerrado: trabaja directo sobre tus carpetas, segrega pares RAW + JPG tanto en vivo como al importar carpetas existentes, y sincroniza todo.",
            steps: [
                "1. En el Asistente Inicial confirmá el perfil de hardware (IA completa, Equilibrado o Modo Ligero).",
                "2. Elegí tu Carpeta Raíz Global donde vivirán tus grupos y sesiones.",
                "3. Creá una sesión vacía con 'Nueva sesión' (⌘N) o usá 'Importar carpeta' (⌘I) para traer una carpeta existente de tu Mac: PhotoPic separa RAW/ y JPG/ automáticamente y analiza rostros.",
                "4. También podés conectar tu cámara o teléfono por USB (o vincular una Carpeta puente).",
                "5. Revisá nitidez al Zoom 1:1 (Espacio), aprobá hacia Seleccionadas (→) o descartá con ←."
            ],
            canDo: [
                "Importar carpetas ya guardadas en tu Mac (con o sin subcarpetas) para segregar RAW + JPG y detectar rostros, ojos cerrados y poses en lote.",
                "Abrir cualquier carpeta de sesión directo en Lightroom Classic, Capture One o Affinity.",
                "Trabajar 100% sin internet para captura/culling, y actualizarse automáticamente cuando haya conexión."
            ],
            limitations: [
                "PhotoPic no aplica revelado destructivo ni edición de color sobre el RAW (clasifica, etiqueta y previsualiza en GPU).",
                "La compilación actual de macOS es nativa Apple Silicon (arm64)."
            ],
            tips: [
                "Hacé clic en cualquier parte de la tarjeta de una sesión para abrirla al instante."
            ]
        ),
        HelpTopic(
            id: "hardware-ai-mode",
            docCode: "DOC-02",
            category: .setupFlow,
            title: "Rendimiento e IA",
            subtitle: "Neural Engine, perfiles y cómo apagar la IA",
            iconSystemName: "cpu",
            keywords: ["neural engine", "ram", "cpu", "metal", "lento", "apagar ia", "modo ligero", "equilibrado"],
            summary: "El Apple Neural Engine acelera la detección de rostros y poses en Apple Silicon (M1–M5). En otros equipos podés ajustar el perfil en vivo sin reiniciar.",
            steps: [
                "1. Estudio Completo: Apple Silicon (>= 12 GB RAM) con GPU RAW + rostros, ojos y poses de 19 puntos.",
                "2. Equilibrado: 8–11 GB RAM o Intel con conteo rápido de rostros y parpadeo sin poses pesadas.",
                "3. Modo Ligero (Sin IA): 0% análisis de IA en segundo plano para máxima fluidez.",
                "4. Cambiá el perfil en cualquier momento desde Configuración → General y Rendimiento."
            ],
            canDo: [
                "Prender o apagar detección de caras y poses por separado en tiempo real.",
                "Re-auditar el equipo con un clic."
            ],
            limitations: [
                "Sin Neural Engine físico, activar poses corporales completas puede reducir el ritmo en ráfagas rápidas.",
                "La IA no identifica nombres de personas (solo conteo, ojos abiertos/cerrados y postura)."
            ],
            tips: [
                "Apagar la IA nunca detiene el tethering USB ni el revelado RAW por Metal."
            ]
        ),
        HelpTopic(
            id: "usb-wifi-watchfolder",
            docCode: "DOC-03",
            category: .connectionsLive,
            title: "Conexión USB y Puente",
            subtitle: "USB directo, Carpetas puente y Validador USB",
            iconSystemName: "cable.connector",
            keywords: ["usb", "thunderbolt", "android", "ptp", "mtp", "iphone", "wifi", "bluetooth", "ptpcamera", "watchfolder", "carpeta puente", "ftp", "expert raw", "tethering", "midi", "canon", "sony", "validador"],
            summary: "Recibe capturas por cable USB-C/Thunderbolt 4, Bonjour PTP/IP o Carpeta puente, con diagnóstico físico IOKit y control de originales en SD.",
            steps: [
                "1. Canon EOS (70D y compatibles): apagá el Wi-Fi interno (desactiva el USB en Canon) y cerrá EOS Utility; PhotoPic abre sesión USB directa.",
                "2. Sony / Fujifilm: poné Conexión USB en 'MTP' o 'PTP' (no Mass Storage).",
                "3. Android USB: elegí 'Transferir imágenes (PTP)' y tocá Permitir. Modo Pro (DNG) descarga más rápido que Expert RAW.",
                "4. iPhone / iPad: desbloqueá, tocá 'Confiar' e ingresá tu código.",
                "5. Para importar desde EOS Utility, Capture One o un transmisor Wi-Fi, usá 'Carpeta puente' arriba."
            ],
            canDo: [
                "Escudo Anti-Galería Vieja: indexa el carrete/SD sin descargar fotos previas y solo captura tomas nuevas.",
                "Mantiene o limpia originales en la memoria/SD del dispositivo según tu ajuste por equipo en Dispositivos (0xD11C en Canon).",
                "Diagnostica bloqueos de macOS PTPCamera / Fotos y modos USB incompatibles vía IOKit."
            ],
            limitations: [
                "Bluetooth no tiene ancho de banda suficiente para transferir archivos RAW.",
                "En macOS, Android debe estar en modo PTP (no Solo carga ni USB Tethering)."
            ],
            tips: [
                "Por seguridad, PhotoPic impide elegir como Carpeta puente la misma carpeta raíz de sesiones."
            ]
        ),
        HelpTopic(
            id: "live-view-guide",
            docCode: "DOC-07",
            category: .connectionsLive,
            title: "Vista en Vivo y Flash",
            subtitle: "USB directo Canon, controles adaptativos, flash de zapata y UVC/HDMI",
            iconSystemName: "camera.viewfinder",
            keywords: ["live view", "vista en vivo", "hdmi", "uvc", "gphoto2", "android", "iphone", "continuity", "ip webcam", "droidcam", "samsung", "dji", "osmo", "flash", "zapata", "ttl"],
            summary: "Combina visor directo Canon EOS USB (sin instalar drivers), controles PTP adaptativos por lente/dial, protección para flash externo de zapata y video UVC/HDMI/Continuidad.",
            steps: [
                "1. Canon EOS USB: enchufá la cámara y pulsá 'Iniciar Vista en Vivo'. El panel derecho descubre solo los controles permitidos por tu cuerpo, dial y lente.",
                "2. Flash externo en zapata superior: usá 'Zapata Externa' (nunca levanta el flash pop-up interno). Para flashes manuales de 1 pin, pulsá 'Modo Flash Zapata (Bajar Espejo)' para disparar sin desconectar el Mac.",
                "3. DJI Osmo Action 4 / Cámaras con Webcam USB / iPhone Continuidad: seleccioná la pestaña 'UVC / HDMI'.",
                "4. Android: transmití video por 'Wi-Fi IP' mientras el cable PTP sigue descargando fotos."
            ],
            canDo: [
                "Controlar Velocidad, Apertura, ISO, Balance de Blancos, Medición, Enfoque AF/MF, Zoom 1x/5x/10x y DOF en cámaras Canon compatibles.",
                "Explicar con candado cuando un ajuste lo bloquea el dial físico (ej. Comp. EV en modo M) o el interruptor MF del lente.",
                "Adaptarse a teléfonos iOS/Android o cámaras de acción (DJI/GoPro) ocultando diales DSLR que el equipo no soporta."
            ],
            limitations: [
                "iPhone, Android PTP y cámaras de acción (DJI Osmo / GoPro) no exponen control remoto de exposición ni flash por USB PTP.",
                "En Canon DSLRs, un flash manual de 1 pin no dispara con el espejo arriba ni con Disparo Silencioso LV activo: bajá el espejo con un clic desde el panel Flash."
            ],
            tips: [
                "Podés probar todo el panel de control Canon EOS 70D sin cámara conectada usando 'Ver demo interactiva'."
            ]
        ),
        HelpTopic(
            id: "culling-raw-folders",
            docCode: "DOC-04",
            category: .foldersLimits,
            title: "Filtrar, Seleccionadas y Zoom",
            subtitle: "Atajos rápidos, Zoom 1:1 y módulo de Seleccionadas",
            iconSystemName: "plus.magnifyingglass",
            keywords: ["zoom", "1:1", "atajos", "flechas", "para_edicion", "seleccionadas", "raw", "jpg", "deshacer", "cmd+z", "formatos", "rotar", "shift", "vertical", "horizontal", "orientacion"],
            summary: "Cada clasificación mueve en disco tanto el RAW (+.xmp) como su pareja JPG entre Filtrar, Seleccionadas y Archivadas en 36 formatos compatibles, con rotación 90° persistente mediante Shift.",
            steps: [
                "1. ↑ y ↓: recorrer fotos pendientes sin mover archivos (también navega dentro de Seleccionadas y Archivadas).",
                "2. → o Edición →: aprueba hacia el módulo Seleccionadas (Para_Edicion/{RAW,JPG}).",
                "3. ← o ← Archivar: descarta hacia Archivadas/{RAW,JPG}.",
                "4. Espacio o clic sostenido + arrastrar: Zoom 1:1 píxel real. También podés hacer zoom continuo (100%–800%) con pellizco de 2 dedos en trackpad o Ctrl/⌘ + rueda del mouse, y arrastrar o deslizar 2 dedos para moverte dentro de la foto en Filtrar, Seleccionadas y Archivadas (Esc o doble clic restablece).",
                "5. Shift (toque rápido) o botón ↻ Rotar: rota la foto 90° a la derecha y guarda la orientación EXIF (0x0112) directo en el archivo RAW, su JPG asociado y .xmp para que Finder y Lightroom la abran ya rotada.",
                "6. En Seleccionadas podés inspeccionar tus elegidas, abrirlas en Finder, devolverlas a Filtrar o moverlas a Archivadas; ⌘Z deshace la última acción."
            ],
            canDo: [
                "Rotar sin pérdida archivos RAW TIFF (.CR2/.DNG/.NEF/.ARW), Canon .CR3 y .JPG/.HEIC guardando el cambio directo en disco.",
                "Re-evaluar cualquier foto ya aprobada dentro de la pestaña Seleccionadas sin tocar Finder.",
                "Revelar 25 formatos RAW desde sensor puro (CIRAWFilter Metal en Mac / LibRaw en Windows)."
            ],
            limitations: [
                "Modelos de cámara recién lanzados pueden requerir actualizar macOS para decodificación nativa de su nuevo formato RAW.",
                "Es un estudio de captura y selección rápida 1:1, no un editor de color."
            ],
            tips: [
                "Activá 'Seguir última captura' a la derecha de la barra inferior para saltar directo a cada nueva toma."
            ]
        ),
        HelpTopic(
            id: "ai-tags-xmp",
            docCode: "DOC-05",
            category: .cullingAI,
            title: "Etiquetas IA y Lightroom",
            subtitle: "Caras, ojos cerrados, poses y sidecars .XMP",
            iconSystemName: "tag",
            keywords: ["tags", "etiquetas", "xmp", "ojos cerrados", "ear", "poses", "pareja", "grupo", "finder", "rostros", "detectar", "lote"],
            summary: "La IA local analiza cada foto al instante o por lotes ('Detectar rostros'), habilita chips de filtrado en la barra superior y escribe sidecars .XMP estándar.",
            steps: [
                "1. Conteo y encuadre: Sin personas, Individual, Pareja, Grupo, Primer plano, Plano medio o Cuerpo entero.",
                "2. Detección de ojos (EAR): marca 'Ojos abiertos' o alerta ámbar 'Ojos cerrados'.",
                "3. Poses corporales: De pie, Sentado, Brazos arriba, Manos en cintura, Pose dinámica.",
                "4. Si importaste una carpeta o estás en Modo Ligero, pulsá 'Detectar rostros' en la barra IA: para analizar todas las fotos pendientes bajo demanda.",
                "5. Agregá etiquetas propias con '+ Etiqueta' para organizar tus entregas."
            ],
            canDo: [
                "Exporta sidecars .xmp compatibles con Adobe Lightroom Classic, Camera Raw y Capture One.",
                "Sincroniza macOS Finder Tags automáticamente."
            ],
            limitations: [
                "Nunca modifica el archivo RAW binario original; usa sidecars .xmp no destructivos.",
                "Personas de espaldas o muy pequeñas pueden detectarse como 'Sin personas'."
            ],
            tips: [
                "El modo 'Equilibrado' conserva conteo de personas y alerta de ojos cerrados consumiendo menos batería."
            ]
        ),
        HelpTopic(
            id: "archived-cleanup",
            docCode: "DOC-06",
            category: .foldersLimits,
            title: "Grupos, Timer y Borrado",
            subtitle: "Organización por cliente, cronómetro e inspector EXIF",
            iconSystemName: "folder.badge.gearshape",
            keywords: ["archivar", "archivadas", "eliminar", "borrar", "grupo", "carpeta master", "timer", "temporizador", "exif", "etiquetas", "buscar", "renombrar", "editar"],
            summary: "Creá y renombrá Grupos y Sesiones directo en disco, medí automáticamente el tiempo de sesión y liberá espacio borrando descartes confirmados.",
            steps: [
                "1. En Inicio pulsá 'Crear grupo' para agrupar sesiones; hacé clic en el grupo para entrar y usá '< Regresar' para volver.",
                "2. Usá el ícono de lápiz en cualquier Grupo o Sesión para renombrar su carpeta real en Finder/Explorador.",
                "3. El cronómetro inicia solo con la primera captura (o manualmente) y se guarda por sesión.",
                "4. En Archivadas podés 'Recuperar a Seleccionadas' o usar 'Eliminar archivo...' / 'Vaciar carpeta...'."
            ],
            canDo: [
                "Renombrar grupos y sesiones desde PhotoPic manteniendo 100% sincronizadas las carpetas reales en Finder y Windows.",
                "Navegar dentro de cada grupo para ver únicamente sus sesiones.",
                "Filtrar sesiones por texto, grupo o #etiqueta de proyecto.",
                "Proteger cada eliminación permanente con confirmación explícita en popover."
            ],
            limitations: [
                "La eliminación permanente en Archivadas o proyectos no pasa por la Papelera ni admite ⌘Z."
            ],
            tips: [
                "En Configuración → General podés desactivar el inicio automático del temporizador si preferís cronometrar manual."
            ]
        )
    ]
}
