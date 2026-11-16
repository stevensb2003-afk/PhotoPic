# Módulo: Automatizaciones, Flujo End-to-End y Reglas de Carpetas
> **ID Documento**: `DOC-05` | **Módulo Sistema**: `automations` | **Pantallas**: `Transversal`
> **Roles con Acceso**: `SISTEMA-AUTO`, `TODOS`
> **Propósito LLM**: Documenta las reglas automáticas en segundo plano y el flujo completo End-to-End desde la captura hasta la entrega.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Automatizaciones en Segundo Plano | `SISTEMA-AUTO` | `L016-L029` |
| 2 | 2. Flujo End-to-End (E2E) Completo en Estudio | `TODOS` | `L030-L036` |
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

## 2. Flujo End-to-End (E2E) Completo en Estudio [ROL: TODOS]

1. **Instalación limpia:** Abrir `PhotoPic-Installer.dmg` (macOS) o `PhotoPic.exe` (Windows).
2. **Asistente Inicial:** Revisar diagnóstico de hardware, mantener IA activa o seleccionar `Modo Ligero (Sin IA)` y elegir Carpeta Raíz Global.
3. **Conexión:** Enchufar cámara o Android en modo PTP por USB/Thunderbolt 4, o vincular carpeta de transmisor Wi-Fi con `Vincular Carpeta / Wi-Fi...`.
4. **Sesión y Captura:** Crear sesión, disparar fotos nuevas y confirmar que las fotos antiguas del carrete/SD no se descargan.
5. **Culling y Entrega:** Inspeccionar al Zoom 1:1 (`Espacio`), filtrar por etiquetas IA, aprobar con `→` (obteniendo carpetas limpias `Para_Edicion/RAW/` + `Para_Edicion/JPG/`) y limpiar descartes desde `Archivadas` con el Popover de confirmación.
