# Módulo: Culling RAW GPU, Auto-Etiquetado IA y Limpieza en Archivadas
> **ID Documento**: `DOC-04` | **Módulo Sistema**: `culling-workspace` | **Pestañas**: `Filtrar`, `Seleccionadas`, `Archivadas`
> **Roles con Acceso**: `FOTOGRAFO`, `ASISTENTE` (culling/revisión/recuperación), `ADMIN-EQUIPO` (borrado definitivo)
> **Propósito LLM**: Explica paso a paso el visor RAW GPU, Zoom 1:1, rotación persistente `Shift`, filtros IA manuales/automáticos, módulo `Seleccionadas` y borrado definitivo.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Visor Central RAW GPU y Atajos de Estudio | `FOTOGRAFO` | `L022-L035` |
| 2 | 2. Filtros de IA Offline, Análisis por Lotes y Etiquetas Personalizadas | `FOTOGRAFO` | `L036-L046` |
| 3 | ↳ 2.1 Cómo filtrar la cola pendiente por etiquetas y usar `Detectar rostros` | `FOTOGRAFO` | `L038-L042` |
| 4 | ↳ 2.2 Cómo agregar etiquetas manuales y exportar `.xmp` | `FOTOGRAFO` | `L043-L046` |
| 5 | 3. Módulo `Seleccionadas` (`Para_Edicion`) | `FOTOGRAFO` | `L047-L051` |
| 6 | 4. Gestión de `Archivadas`: Recuperar o Eliminar Definitivamente | `ADMIN-EQUIPO` | `L052-L063` |
| 7 | ↳ 4.1 Recuperar una foto hacia `Seleccionadas` | `FOTOGRAFO` | `L054-L058` |
| 8 | ↳ 4.2 Eliminar una foto o vaciar `Archivadas` con Popover de confirmación | `ADMIN-EQUIPO` | `L059-L063` |
<!-- TOC:END -->

## 1. Visor Central RAW GPU y Atajos de Estudio [ROL: FOTOGRAFO]

PhotoPic prohíbe usar miniaturas JPG incrustadas cuando existe un archivo RAW maestro: revela directamente desde el sensor mediante `CIRAWFilter` sobre Metal (macOS) o `LibRaw` (Windows).

| Atajo / Gesto | Acción | Efecto en Disco |
| :--- | :--- | :--- |
| **`↑` / `↓`** | Navegar cola pendiente | Ninguno (no mueve archivos) |
| **`→` / Swipe Derecha** | Aprobar foto | Mueve RAW (+ `.xmp`) a `Para_Edicion/RAW/` y su copia JPG a `Para_Edicion/JPG/` |
| **`←` / Swipe Izquierda** | Archivar foto | Mueve RAW (+ `.xmp`) a `Archivadas/RAW/` y su copia JPG a `Archivadas/JPG/` |
| **`Espacio` / Clic + Arrastrar** | Zoom 1:1 píxel real (`100%`) | Carga resolución nativa completa del sensor para revisar foco en ojos |
| **`Shift` (toque rápido) / `↻ Rotar`** | Rotar 90° a la derecha | Guarda orientación EXIF (`0x0112`) sin pérdida directo en RAW (`.CR2/.DNG/.NEF/.ARW` o caja `CMT1` en `.CR3`), `.JPG/.HEIC`, par JPG asociado y `.xmp` |
| **`⌘I` / `Ctrl+I`** | Importar carpeta en la sesión | Escanea, segrega `RAW / JPG` y ejecuta detección facial IA en lote |
| **`⌘Z` / `Ctrl+Z`** | Deshacer última clasificación | Devuelve RAW (+ `.xmp`) y JPG juntos a su carpeta anterior |

## 2. Filtros de IA Offline, Análisis por Lotes y Etiquetas Personalizadas [ROL: FOTOGRAFO]

### 2.1 Cómo filtrar la cola pendiente por etiquetas y usar `Detectar rostros` [ROL: FOTOGRAFO]
1. En la barra **`IA:`** sobre el visor aparecen los chips detectados (`1 persona`, `Pareja`, `Grupo`, `Primer plano`, `Ojos abiertos`, alerta ámbar `Ojos cerrados`, `Brazos arriba`, `De pie`, `Sentado`).
2. Si importaste una carpeta desde el disco o tenés activo el *Modo Ligero*, pulsá **`Detectar rostros`** para analizar por lotes todas las fotos pendientes bajo demanda (con progreso visible).
3. Haz clic en cualquier chip para mostrar únicamente las fotos coincidentes sin mover archivos del disco; clic en **`Todas`** restaura la vista completa.

### 2.2 Cómo agregar etiquetas manuales y exportar `.xmp` [ROL: FOTOGRAFO]
1. En el HUD derecho de la foto actual, pulsa **`+ Etiqueta`**, escribe el texto (ej. `Favorita`, `Novia`) y confirma.
2. La etiqueta se guarda al instante en `.photopic_tags.json`, se escribe en el sidecar `<foto>.xmp` junto al RAW (tanto en `Filtrar` como en `Seleccionadas` o `Archivadas`) y se aplica como Finder Tag en macOS.

## 3. Módulo `Seleccionadas` (`Para_Edicion`) [ROL: FOTOGRAFO]

1. Abre la pestaña **`Seleccionadas`** en la barra superior para revisar todas las tomas aprobadas con su badge `+JPG`, metadatos EXIF y etiquetas IA.
2. Navegá con **`↑` / `↓`**, rotá con **`Shift`** o el botón **`Rotar`**, abrí la carpeta directo con **`Mostrar en Finder`** / **`Mostrar en Explorador`**, devolvé cualquier foto a la cola con **`Devolver a Filtrar`** o descartala con **`Mover a Archivadas`** (`←`).

## 4. Gestión de `Archivadas`: Recuperar o Eliminar Definitivamente [ROL: ADMIN-EQUIPO]

### 4.1 Recuperar una foto hacia `Seleccionadas` [ROL: FOTOGRAFO]
1. Abre la pestaña **`Archivadas`** en la barra superior de la sesión.
2. Selecciona la miniatura deseada (o navegá con `↑`/`↓`) para inspeccionarla en GPU a la derecha; también podés rotarla con **`Shift`**.
3. Pulsa **`Recuperar a Seleccionadas`**: mueve el RAW (+ `.xmp`) a `Para_Edicion/RAW/` y su JPG a `Para_Edicion/JPG/`.

### 4.2 Eliminar una foto o vaciar `Archivadas` con Popover de confirmación [ROL: ADMIN-EQUIPO]
1. Para eliminar una sola foto descartada, selecciónala y pulsa **`Eliminar archivo...`**.
2. En el **Popover de confirmación**, revisa nombre y tamaño, decide si querés borrar también copias JPG asociadas y confirma con **`Eliminar para siempre`**.
3. Para liberar todo el espacio de descartes de la sesión, pulsa **`Vaciar carpeta...`** (`Vaciar Archivadas...` en Windows) y confirma en el Popover **`Vaciar (N)`**.
4. Por seguridad, `SessionArchiveCleaner` bloquea cualquier intento de borrado fuera de `Archivadas/` y limpia automáticamente la pila de `⌘Z` para las fotos eliminadas.
