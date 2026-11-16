# Changelog — PhotoPic

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
