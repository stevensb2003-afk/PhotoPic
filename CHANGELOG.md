# Changelog — PhotoPic

## v2.1.0 — Auditor de Hardware, Asistente Guiado Inicial, Modo Sin IA y Limpieza en Archivadas
- **Auditor de Capacidad de Hardware (`HardwareCapabilityAuditor`):** En macOS y Windows inspecciona al arrancar procesador, núcleos, memoria RAM física, disponibilidad de GPU Metal, presencia física de **Apple Neural Engine** (`arm64` vs Intel) o `MediaPipe`/`OpenCV`.
- **Asistente Guiado Inicial de Instalación (2 pasos):** Antes de empezar, muestra el diagnóstico del equipo, recomienda el perfil óptimo (`Estudio Completo`, `Equilibrado` o `Modo Ligero sin IA`), y permite activar o apagar por completo el auto-etiquetado de caras y las poses de 19 puntos desde el arranque (además de re-editarlo en **Configuración → General y Rendimiento**).
- **Eliminación definitiva con Popover de confirmación en `Archivadas`:** Nuevos botones **`Eliminar archivo...`** (individual) y **`Vaciar carpeta...`** en macOS y Windows con Popover nativo de advertencia, borrado físico seguro restringido a `Archivadas/`, limpieza de `.xmp` + `.photopic_tags.json` y opción para borrar o conservar la copia `.JPG` paralela.

## v2.0.0 — Rebrand a PhotoPic, IA Offline, 36 Formatos y Edición Windows
- **Identidad PhotoPic & Pictogrammers:** Nuevo nombre oficial **PhotoPic**, iconografía vectorial integrada de `@mdi/svg` (`PictogrammersIcons.swift` + `assets/icons/`) e ícono nativo `.svg` / `.icns` / `.ico`.
- **Cobertura ampliada de 36 formatos:** 25 formatos RAW (`CR2`, `CR3`, `CRW`, `DNG`, `NEF`, `NRW`, `ARW`, `SRF`, `SR2`, `RAF`, `ORF`, `ORI`, `RW2`, `RAW`, `PEF`, `SRW`, `3FR`, `FFF`, `IIQ`, `RWL`, `ERF`, `MOS`, `MRW`, `DCR`, `KDC`) y 11 formatos comprimidos/móviles (`JPG`, `JPEG`, `HEIC`, `HEIF`, `HIF`, `AVIF`, `JXL`, `WEBP`, `PNG`, `TIF`, `TIFF`).
- **Auto-etiquetado IA 100% offline (`Vision` / `MediaPipe`):** Detección automática al vuelo de cantidad de personas (`Sin personas`, `Individual`, `Pareja`, `Grupo`), encuadre (`Primer plano`, `Plano medio`, `Cuerpo entero`), estado de ojos (`Ojos abiertos` / alerta `Ojos cerrados`) y poses (`De pie`, `Sentado`, `Brazos arriba`, `Manos en cintura`, `Pose dinámica`), con filtros rápidos en vivo y persistencia en `.photopic_tags.json`, sidecars `.xmp` y Finder tags.
- **Edición nativa para Windows 10/11 (`windows/`):** Interfaz Qt 6 (`PySide6`), revelado puro con `LibRaw` (`rawpy`), WPD COM (MTP/PTP) + watchfolder y empaquetado a `PhotoPic.exe`.
- **CI Multiplataforma:** Pipeline GitHub Actions generando artefactos instalables para macOS (`.dmg`) y Windows (`.zip`).

## v1.0.0 — Estudio Base macOS Tethering & Culling RAW
- Captura tethered en vivo con `ImageCaptureCore` + Smart Delta Watcher y escudo anti-galería antigua.
- Motor de revelado GPU Metal con `CIRAWFilter` y zoom real 1:1 píxel por píxel.
- Clasificación física en disco (`RAW/`, `JPG/`, `Para_Edicion/`, `Archivadas/`) con deshacer `⌘Z` y recuperación desde `Archivadas/`.
