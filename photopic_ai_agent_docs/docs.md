# Base Documental Funcional de PhotoPic (`v2.6.24`)
> **Propósito**: Documentación operativa estilo BRD paso a paso para el Centro de Ayuda interno y Agentes IA de soporte, cubriendo macOS (`Swift 6 / SwiftUI / IOUSBHost`) y Windows (`PySide6 Qt6`).
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

PhotoPic es una aplicación de escritorio 100% offline y nativa. Recibe capturas en vivo desde cámaras DSLR/Mirrorless (incluyendo enlace directo `IOUSBHost` Canon EOS con controles adaptativos y protección para flash externo de zapata), teléfonos Android/iPhone, cámaras de acción UVC o una **Carpeta puente**. Clasifica en los módulos **Filtrar**, **Vista en Vivo**, **Seleccionadas** y **Archivadas**, moviendo pares **RAW + JPG** y sidecars `.xmp` en disco (`RAW/`, `JPG/`, `Para_Edicion/{RAW,JPG}` y `Archivadas/{RAW,JPG}`).

## 2. Cómo Usar esta Documentación [ROL: TODOS]

1. Consulta primero `00-CONTENT-TABLE.md` para localizar el documento exacto y el rango de líneas `Lxxx-Lyyy` correspondiente a tu consulta.
2. Verifica la etiqueta `[ROL: ...]` de cada sección para responder acorde al perfil del usuario (`FOTOGRAFO`, `ASISTENTE`, `ADMIN-EQUIPO`, `SISTEMA-AUTO` o `TODOS`).
3. Para el mapa exacto hacia archivos fuente Swift y Python (`<= 300` líneas por archivo), revisa `07-mapa-capas-egm-referencia.md`.
