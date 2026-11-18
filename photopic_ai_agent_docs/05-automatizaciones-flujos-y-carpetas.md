# Módulo: Automatizaciones, Flujo End-to-End y Reglas de Carpetas
> **ID Documento**: `DOC-05` | **Módulo Sistema**: `automations` | **Pantallas**: `Transversal`
> **Roles con Acceso**: `SISTEMA-AUTO`, `TODOS`
> **Propósito LLM**: Documenta las reglas automáticas en segundo plano y el flujo completo End-to-End desde la captura hasta la entrega.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Automatizaciones en Segundo Plano | `SISTEMA-AUTO` | `L016-L033` |
| 2 | 2. Flujo End-to-End (E2E) Completo en Estudio | `TODOS` | `L034-L040` |
<!-- TOC:END -->

## 1. Automatizaciones en Segundo Plano [ROL: SISTEMA-AUTO]

1. **Separación automática RAW + JPG al ingresar (`SessionIngestRouter`):**
   - Todo RAW (25 extensiones soportadas) va a `Sesión/RAW/`.
   - Si ya había llegado antes una copia `.JPG` del mismo disparo en modo fallback móvil, se degrada automáticamente a `Sesión/JPG/`.
   - Si llega un `.JPG` tarde después de que su `.RAW` ya fue clasificado en `Para_Edicion/RAW/` o `Archivadas/RAW/`, el router lo envía directamente a `Para_Edicion/JPG/` o `Archivadas/JPG/`.
2. **Movimiento sincronizado de pares (`SessionFileManager+BucketSync`):**
   - Mover un RAW a `Para_Edicion` o `Archivadas` relocaliza simultáneamente: archivo RAW -> `<destino>/RAW/`, sidecar `.xmp` -> `<destino>/RAW/`, y contraparte JPG/HEIC -> `<destino>/JPG/`.
   - Deshacer (`⌘Z` / `Ctrl+Z`) revierte ambos archivos y el `.xmp` exactamente a su ubicación previa.
3. **Estabilidad de escritura en Watchfolder Wi-Fi/SD (`FolderWatchTetherService`):**
   - Espera un ciclo completo (`900 ms`) verificando que el tamaño en bytes del archivo no cambie antes de copiarlo e ingerirlo, evitando leer RAWs truncados durante transferencias inalámbricas.
4. **Resiliencia de cola en vivo (`CullingSessionViewModel`):**
   - Cuando entra un disparo nuevo mientras el usuario inspecciona una foto anterior, se agrega al final sin interrumpir la pantalla actual (a menos que esté activo el switch **`Seguir última captura`**).
5. **Importación de carpetas existentes en 2 pasadas (`SessionFolderImporter`):**
   - Al elegir **`Importar carpeta` (`⌘I` / `Ctrl+I`)**, escanea la carpeta (con o sin subcarpetas, omitiendo sesiones ya inicializadas y validando que origen y destino no se superpongan).
   - Pasada 1 empareja `RAW + JPG` dentro del mismo directorio; Pasada 2 empareja `RAW/` + `JPG/` entre subcarpetas separadas; Pasada 3 envía fotos comprimidas sueltas directo a `RAW/` (`Filtrar`).
   - Resuelve nombres repetidos asignando sufijos sincronizados (`_2`) a ambos archivos del par, conserva `.xmp` existentes, sugiere el nombre de la carpeta padre si se importa una subcarpeta genérica (`RAW`, `JPG`, `DCIM`, `Fotos`) y puede disparar detección facial IA en lote al abrir.

## 2. Flujo End-to-End (E2E) Completo en Estudio [ROL: TODOS]

1. **Instalación limpia:** Abrir `PhotoPic-Installer.dmg` (macOS) o `PhotoPic.exe` (Windows).
2. **Asistente Inicial:** Revisar diagnóstico de hardware, mantener IA activa o seleccionar `Modo Ligero (Sin IA)` y elegir Carpeta Raíz Global.
3. **Conexión o Importación:** Enchufar cámara o Android en modo PTP por USB/Thunderbolt 4, vincular una **`Carpeta puente`**, o importar una carpeta existente del disco con **`Importar carpeta` (`⌘I` / `Ctrl+I`)**.
4. **Sesión y Grupos:** Organizar clientes con **`Crear grupo`**, crear con **`Nueva sesión`** (`⌘N` / `Ctrl+N`) o renombrar carpetas directo desde la interfaz.
5. **Culling, Rotación y Entrega:** Inspeccionar al Zoom 1:1 (`Espacio`), rotar 90° persistente en disco con **`Shift`**, filtrar por etiquetas IA (`Detectar rostros`), aprobar con `→` hacia **`Seleccionadas`** (`Para_Edicion/RAW/` + `Para_Edicion/JPG/`) y limpiar descartes desde **`Archivadas`** con el Popover de confirmación.
