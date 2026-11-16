# Módulo: Arquitectura Global, Perfiles de Uso y Centro de Ayuda
> **ID Documento**: `DOC-01` | **Módulo Sistema**: `global` | **Pantallas**: `Inicio`, `Sesiones`, `Centro de Ayuda (⌘?)`
> **Roles con Acceso**: `TODOS` (`FOTOGRAFO`, `ASISTENTE`, `ADMIN-EQUIPO`)
> **Propósito LLM**: Explica la navegación general de PhotoPic, perfiles de uso en estudio y operación del Centro de Ayuda interno.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Propósito de Negocio y Principio Sin Catálogo Cerrado | `TODOS` | `L019-L022` |
| 2 | 2. Matriz de Perfiles de Trabajo en Estudio | `REFERENCIA-RBAC` | `L023-L030` |
| 3 | 3. Navegación Principal y Centro de Ayuda Interno | `TODOS` | `L031-L037` |
| 4 | ↳ 3.1 Cómo abrir y buscar en el Centro de Ayuda | `TODOS` | `L033-L037` |
| 5 | 4. Estructura de Carpetas por Sesión | `TODOS` | `L038-L046` |
<!-- TOC:END -->

## 1. Propósito de Negocio y Principio Sin Catálogo Cerrado [ROL: TODOS]

PhotoPic resuelve el cuello de botella entre la captura en sesión y la selección de imágenes antes de editar. A diferencia de herramientas con catálogo propietario, PhotoPic nunca importa ni encierra tus fotos dentro de la app: trabaja directamente sobre carpetas reales del sistema de archivos, de modo que cualquier sesión puede abrirse de inmediato en Lightroom Classic, Capture One, Bridge o Affinity.

## 2. Matriz de Perfiles de Trabajo en Estudio [ROL: REFERENCIA-RBAC]

| Perfil | Responsabilidad Principal | Acciones Permitidas |
| :--- | :--- | :--- |
| `FOTOGRAFO` / `ASISTENTE` | Operación en vivo dentro de la sesión | Crear/abrir sesiones, vincular Watchfolder Wi-Fi/SD, navegar cola, Zoom 1:1, aprobar (`→`), archivar (`←`), deshacer (`⌘Z`/`Ctrl+Z`), filtrar por etiquetas IA, recuperar descartes. |
| `ADMIN-EQUIPO` | Configuración de estación y limpieza destructiva | Cambiar Carpeta Raíz Global, re-auditar hardware, activar/desactivar IA y poses, administrar alias/auto-conexión USB, olvidar dispositivos, eliminar definitivamente archivos en `Archivadas/`. |
| `SISTEMA-AUTO` | Servicios en segundo plano | Escudo anti-galería vieja, separación RAW+JPG, revelado GPU Metal/`LibRaw`, etiquetado `Vision`/`MediaPipe`, escritura de `.photopic_tags.json` y sidecars `.xmp`. |

## 3. Navegación Principal y Centro de Ayuda Interno [ROL: TODOS]

### 3.1 Cómo abrir y buscar en el Centro de Ayuda [ROL: TODOS]
1. En macOS, haz clic en el botón de interrogación **`?`** ubicado en la barra superior derecha (junto al botón de Configuración) o presiona **`⌘?`**. En Windows, pulsa **`Ayuda (?)`** en la barra superior de Inicio.
2. Utiliza el campo **Buscar tema o atajo...** en la columna izquierda para filtrar por palabras clave como `Zoom`, `PTP`, `Wi-Fi`, `Neural Engine`, `RAW` o `Archivadas`.
3. Selecciona cualquiera de las guías `DOC-01` a `DOC-06` para ver el procedimiento paso a paso y los consejos operativos sin necesidad de internet.

## 4. Estructura de Carpetas por Sesión [ROL: TODOS]

1. **Carpeta Raíz Global:** Directorio maestro elegido una sola vez en el Paso 2 del Asistente Inicial (persistido con Security-Scoped Bookmark en macOS o en `~/.photopic_windows.json` en Windows).
2. **Subcarpetas automáticas de cada sesión:**
   - `RAW/`: cola de pendientes (RAWs nuevos o JPGs fallback móvil).
   - `JPG/`: copias comprimidas pendientes asociadas a `RAW/`.
   - `Para_Edicion/RAW/` y `Para_Edicion/JPG/`: fotografías aprobadas con sus `.xmp` y copias JPG sincronizadas.
   - `Archivadas/RAW/` y `Archivadas/JPG/`: fotografías descartadas con sus `.xmp` y copias JPG sincronizadas.
   - `.photopic_tags.json`: índice persistente de etiquetas IA y personalizadas.
