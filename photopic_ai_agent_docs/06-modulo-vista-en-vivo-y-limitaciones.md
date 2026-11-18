# Módulo: Vista en Vivo (Live View), Disparo Remoto y Limitaciones Reales
> **ID Documento**: `DOC-07` *(archivo `06`)* | **Módulo Sistema**: `live-view` | **Pestaña**: `Vista en Vivo`
> **Roles con Acceso**: `FOTOGRAFO`, `ASISTENTE` (`UVC/HDMI` y disparo), `ADMIN-EQUIPO` (`gphoto2` opcional)
> **Propósito LLM**: Documenta paso a paso la pestaña Vista en Vivo en macOS y Windows, el disparo remoto PTP/gphoto2 y todas las limitaciones reales por sistema operativo.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Propósito de Negocio y Selección de Motor por Sistema Operativo | `TODOS` | `L019-L022` |
| 2 | 2. Procesos Operativos Paso a Paso | `FOTOGRAFO` | `L023-L036` |
| 3 | ↳ 2.1 Vista en Vivo UVC / Capturadora HDMI-USB (macOS y Windows) | `FOTOGRAFO` | `L025-L031` |
| 4 | ↳ 2.2 Vista en Vivo para DSLRs Clásicas por 1 Solo Cable USB (`gphoto2`, solo macOS) | `ADMIN-EQUIPO` | `L032-L036` |
| 5 | 3. Matriz Honesta de Capacidades y Limitaciones Reales | `TODOS` | `L037-L046` |
<!-- TOC:END -->

## 1. Propósito de Negocio y Selección de Motor por Sistema Operativo [ROL: TODOS]

Permite evaluar encuadre, regla de tercios (`3×3`), guías de aspecto (`3:2`, `4:5`, `16:9`, `1:1`) y simetría espejo en tiempo real **antes** de disparar, adaptando el transporte de video al método óptimo de cada sistema sin romper el flujo paralelo de descarga de archivos RAW.

## 2. Procesos Operativos Paso a Paso [ROL: FOTOGRAFO]

### 2.1 Vista en Vivo UVC / Capturadora HDMI-USB (macOS y Windows) [ROL: FOTOGRAFO]
1. Abre cualquier sesión y entra a la pestaña superior **`Vista en Vivo`**.
2. Conecta tu cámara moderna por **USB Streaming (UVC)** o conecta una DSLR clásica mediante capturadora **HDMI → USB-C**.
3. En el selector superior elige la fuente (`AVFoundation` en macOS, `Entrada Video / HDMI #N` en Windows), ajusta **`3×3`**, **`Espejo`** o guía de aspecto y pulsa **`Iniciar Vista en Vivo`**.
4. Si tu cámara conectada por PTP soporta disparo remoto (`cameraDeviceCanTakePicture`), pulsa **`Disparar Cámara (PTP)`** para tomar la foto directo al buffer de captura sin tocar el obturador físico.
5. Para capturar un fotograma rápido de encuadre como referencia, pulsa **`Guardar Cuadro de Referencia`**.

### 2.2 Vista en Vivo para DSLRs Clásicas por 1 Solo Cable USB (`gphoto2`, solo macOS) [ROL: ADMIN-EQUIPO]
1. Si querés encuadre en vivo desde una DSLR sin HDMI ni UVC (por ejemplo Canon EOS 70D) usando solo su cable USB en macOS, instala `gphoto2` vía Homebrew (`brew install gphoto2`).
2. En el selector de la pestaña **`Vista en Vivo`**, cambia a **`DSLR USB (gphoto2)`** y pulsa **`Iniciar Vista en Vivo`**: PhotoPic pausa temporalmente `ImageCaptureCore` para ceder el puerto USB a `gphoto2`.
3. Pulsa **`Disparar y Descargar RAW`** para tomar el disparo y enrutar los archivos directo a `Sesión/RAW/`. Al detener Vista en Vivo o cambiar de pestaña, PhotoPic reactiva `ImageCaptureCore` automáticamente.

## 3. Matriz Honesta de Capacidades y Limitaciones Reales [ROL: TODOS]

| Capacidad / Escenario | macOS (`v2.6.24`) | Windows (`v2.6.24`) | Motivo Técnico Exacto |
| :--- | :--- | :--- | :--- |
| **Canon EOS USB Directo (70D y similares)** | Nativo vía `IOUSBHost` (`DirectCanonUSBPTPService`) + controles `0x9116`/`0x9110` | No habilitado por defecto (requeriría Zadig) | Abre sesión sin catalogar toda la SD, transmite EVF `0x9153`, protege flash de zapata (`Modo Espejo Abajo`) y sincroniza destino SD/RAM (`0xD11C`). |
| **DJI Osmo / GoPro / iPhone / Android** | `UVC / HDMI`, Continuity Camera o `Wi-Fi IP` (panel adaptativo sin diales DSLR) | Nativo (`OpenCV DirectShow`) para UVC / HDMI | Ninguno expone diales de exposición ni flash por USB PTP; el panel lateral se adapta mostrando solo sus capacidades reales. |
| **UVC / Capturadora HDMI-USB (30–60 fps)** | Nativo (`AVFoundation`) sin instalar nada | Nativo (`OpenCV DirectShow`) sin tocar drivers | Usa canales estándar de cámara de video sin interferir con el tethering RAW. |
| **Transferencia RAW en vivo por Bluetooth** | No soportado | No soportado | Bluetooth carece de ancho de banda para RAWs; requiere USB, Bonjour PTP/IP o Carpeta puente. |
| **Android por cable en modo MTP** | Requiere modo **PTP** | Soporta MTP y PTP | macOS `ImageCaptureCore` solo enumera dispositivos PTP; Windows WPD soporta ambos. |
| **Edición destructiva / revelados permanentes** | Solo previsualización GPU + tags `.xmp` | Solo previsualización LibRaw + tags `.xmp` | PhotoPic clasifica entre Filtrar, Seleccionadas y Archivadas; no sustituye a Lightroom, Capture One ni Affinity. |
