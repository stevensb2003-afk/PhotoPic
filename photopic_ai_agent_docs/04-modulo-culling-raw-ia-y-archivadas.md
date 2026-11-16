# Módulo: Culling RAW GPU, Auto-Etiquetado IA y Limpieza en Archivadas
> **ID Documento**: `DOC-04` | **Módulo Sistema**: `culling-workspace` | **Pestañas**: `Filtrar (Pendientes)`, `Archivadas`
> **Roles con Acceso**: `FOTOGRAFO`, `ASISTENTE` (culling/recuperación), `ADMIN-EQUIPO` (borrado definitivo)
> **Propósito LLM**: Explica paso a paso el visor RAW GPU, Zoom 1:1, filtros IA, movimiento sincronizado RAW+JPG y borrado definitivo.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Visor Central RAW GPU y Atajos de Estudio | `FOTOGRAFO` | `L021-L032` |
| 2 | 2. Filtros de IA Offline y Etiquetas Personalizadas | `FOTOGRAFO` | `L033-L043` |
| 3 | ↳ 2.1 Cómo filtrar la cola pendiente por etiquetas | `FOTOGRAFO` | `L035-L039` |
| 4 | ↳ 2.2 Cómo agregar etiquetas manuales y exportar `.xmp` | `FOTOGRAFO` | `L040-L043` |
| 5 | 3. Gestión de `Archivadas`: Recuperar o Eliminar Definitivamente | `ADMIN-EQUIPO` | `L044-L055` |
| 6 | ↳ 3.1 Recuperar una foto hacia `Para_Edicion` | `FOTOGRAFO` | `L046-L050` |
| 7 | ↳ 3.2 Eliminar una foto o vaciar `Archivadas` con Popover de confirmación | `ADMIN-EQUIPO` | `L051-L055` |
<!-- TOC:END -->

## 1. Visor Central RAW GPU y Atajos de Estudio [ROL: FOTOGRAFO]

PhotoPic prohíbe usar miniaturas JPG incrustadas cuando existe un archivo RAW maestro: revela directamente desde el sensor mediante `CIRAWFilter` sobre Metal (macOS) o `LibRaw` (Windows).

| Atajo / Gesto | Acción | Efecto en Disco |
| :--- | :--- | :--- |
| **`↑` / `↓`** | Navegar cola pendiente | Ninguno (no mueve archivos) |
| **`→` / Swipe Derecha** | Aprobar foto | Mueve RAW (+ `.xmp`) a `Para_Edicion/RAW/` y su copia JPG a `Para_Edicion/JPG/` |
| **`←` / Swipe Izquierda** | Archivar foto | Mueve RAW (+ `.xmp`) a `Archivadas/RAW/` y su copia JPG a `Archivadas/JPG/` |
| **`Espacio` / Clic + Arrastrar** | Zoom 1:1 píxel real (`100%`) | Carga resolución nativa completa del sensor para revisar foco en ojos |
| **`⌘Z` / `Ctrl+Z`** | Deshacer última clasificación | Devuelve RAW (+ `.xmp`) y JPG juntos a su carpeta anterior |

## 2. Filtros de IA Offline y Etiquetas Personalizadas [ROL: FOTOGRAFO]

### 2.1 Cómo filtrar la cola pendiente por etiquetas [ROL: FOTOGRAFO]
1. Cuando la IA está habilitada, observa la barra **`IA:`** sobre el visor con los chips detectados (`1 persona`, `Pareja`, `Grupo`, `Primer plano`, `Ojos abiertos`, alerta ámbar `Ojos cerrados`, `Brazos arriba`, `De pie`, `Sentado`).
2. Haz clic en cualquier chip para mostrar únicamente las fotos coincidentes sin mover archivos del disco.
3. Haz clic en **`Todas`** para restaurar la vista completa.

### 2.2 Cómo agregar etiquetas manuales y exportar `.xmp` [ROL: FOTOGRAFO]
1. En el HUD inferior de la foto actual, pulsa **`+ Etiqueta`**, escribe el texto (ej. `Favorita`, `Novia`) y confirma.
2. La etiqueta se guarda al instante en `.photopic_tags.json`, se escribe en el sidecar `<foto>.xmp` junto al RAW (compatible con Lightroom/Capture One) y se aplica como Finder Tag en macOS.

## 3. Gestión de `Archivadas`: Recuperar o Eliminar Definitivamente [ROL: ADMIN-EQUIPO]

### 3.1 Recuperar una foto hacia `Para_Edicion` [ROL: FOTOGRAFO]
1. Abre la pestaña **`Archivadas`** en la barra superior de la sesión.
2. Selecciona la miniatura deseada en la grilla izquierda para inspeccionarla en GPU a la derecha.
3. Pulsa **`Recuperar para Edición`**: mueve el RAW (+ `.xmp`) a `Para_Edicion/RAW/` y su JPG a `Para_Edicion/JPG/`.

### 3.2 Eliminar una foto o vaciar `Archivadas` con Popover de confirmación [ROL: ADMIN-EQUIPO]
1. Para eliminar una sola foto descartada, selecciónala y pulsa **`Eliminar archivo...`**.
2. En el **Popover de confirmación**, revisa nombre y tamaño, decide si querés borrar también copias JPG asociadas y confirma con **`Eliminar para siempre`**.
3. Para liberar todo el espacio de descartes de la sesión, pulsa **`Vaciar carpeta...`** (`Vaciar Archivadas...` en Windows) y confirma en el Popover **`Vaciar (N)`**.
4. Por seguridad, `SessionArchiveCleaner` bloquea cualquier intento de borrado fuera de `Archivadas/` y limpia automáticamente la pila de `⌘Z` para las fotos eliminadas.
