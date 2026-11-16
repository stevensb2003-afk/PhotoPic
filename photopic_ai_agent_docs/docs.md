# Base Documental Funcional de PhotoPic (`v2.2.0`)
> **Propósito**: Documentación operativa estilo BRD paso a paso para el Centro de Ayuda interno y Agentes IA de soporte, cubriendo macOS (`Swift 6 / SwiftUI`) y Windows (`PySide6 Qt6`).
> **Carpeta Exclusiva**: `photopic_ai_agent_docs/` (índice maestro en `00-CONTENT-TABLE.md`).

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Visión General del Sistema y Filosofía de Archivos | `TODOS` | `L015-L018` |
| 2 | 2. Cómo Usar esta Documentación | `TODOS` | `L019-L023` |
<!-- TOC:END -->

## 1. Visión General del Sistema y Filosofía de Archivos [ROL: TODOS]

PhotoPic es una aplicación de escritorio 100% offline, sin servidores web locales (`localhost`) y sin base de datos propietaria cerrada. Su función es recibir fotografías en tiempo real desde cámaras DSLR/Mirrorless, smartphones (Android PTP/MTP o iPhone) o carpetas Watchfolder Wi-Fi/FTP, revelar el sensor RAW puro para revisión 1:1, etiquetar automáticamente mediante IA opcional y mover físicamente pares **RAW + JPG** entre carpetas en disco (`RAW/`, `JPG/`, `Para_Edicion/{RAW,JPG}` y `Archivadas/{RAW,JPG}`).

## 2. Cómo Usar esta Documentación [ROL: TODOS]

1. Consulta primero `00-CONTENT-TABLE.md` para localizar el documento exacto y el rango de líneas `Lxxx-Lyyy` correspondiente a tu consulta.
2. Verifica la etiqueta `[ROL: ...]` de cada sección para responder acorde al perfil del usuario (`FOTOGRAFO`, `ASISTENTE`, `ADMIN-EQUIPO`, `SISTEMA-AUTO` o `TODOS`).
3. Para el mapa exacto hacia archivos fuente Swift y Python (`<= 300` líneas por archivo), revisa `06-mapa-capas-egm-referencia.md`.
