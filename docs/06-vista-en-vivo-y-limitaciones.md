# Vista en Vivo (Live View), Controles PTP y Limitaciones (`v2.6.24`)

PhotoPic incluye una pestaña dedicada **`Vista en Vivo`** dentro de cada sesión activa para encuadrar con **cuadrícula 3×3**, **espejo horizontal**, **guías de aspecto (`3:2`, `4:5`, `16:9`, `1:1`)**, **controles remotos PTP adaptativos** y protección dedicada para **flash externo en zapata superior**.

---

## 1. Arquitectura Elegida por Sistema Operativo

| Sistema | Motor Principal (Cero Conflicto USB) | Motor Directo Canon USB / DSLR | Disparo y Controles Remotos |
| :--- | :--- | :--- | :--- |
| **macOS 14+** | `AVFoundation` (`AVCaptureSession`) para **DJI Osmo / Webcam UVC**, **Continuity Camera** y **HDMI→USB** | **`DirectCanonUSBPTPService` (`IOUSBHost`)** nativo sin drivers externos ni `gphoto2` obligatorio | Eventos binarios `0x9116` + escritura `0x9110`, Live View `0x9153`, AF/MF (`0x9154`/`0x9155`), Zoom `1×/5×/10×`, DOF, y modo **`Flash Zapata (Bajar Espejo)`** |
| **Windows 10/11** | `OpenCV DirectShow` (`cv2.VideoCapture`) para cámaras **UVC** y **HDMI→USB** | WPD nativo sin reemplazar drivers con **Zadig (`WinUSB`)** | Captura de cuadro de referencia JPEG a `RAW/` |

---

## 2. Qué SÍ Podés Hacer vs. Limitaciones Reales

### Qué SÍ hace PhotoPic
1. En Canon EOS USB (`70D` y compatibles), abrir sesión directa por `IOUSBHost`, ver Live View sin instalar programas externos y descubrir solo las propiedades permitidas por el dial y el lente (`Velocidad`, `Apertura`, `ISO`, `Comp. EV`, `WB`, `Kelvin`, `Medición`, `Enfoque`, `Disparo`, `Estilo`) más guardado opcional de originales en la SD (`0xD11C`).
2. Proteger tu flash externo de zapata manteniendo el pop-up interno siempre cerrado y ofreciendo **`Modo Flash Zapata (Bajar Espejo)`** para sincronizar flashes manuales de 1 pin sin desconectar el Mac.
3. Detectar teléfonos iOS/Android o cámaras de acción (`DJI Osmo`, `GoPro`), ocultando controles de DSLR no soportados y guiando hacia `UVC / HDMI` o `Wi-Fi IP`.
4. Trabajar por un solo clic en **`Seleccionadas`** (con re-archivo directo a `Archivadas` o vuelta a `Filtrar`), **`Grupos`** visuales y **`Carpeta puente`**.

### Limitaciones Reales (Qué NO hace)
1. **Teléfonos y cámaras de acción:** Ni iOS, ni Android por PTP, ni cámaras como DJI Osmo Action 4 exponen diales de exposición o flash por USB PTP.
2. **Flash manual 1-pin en Live View Canon DSLR:** El firmware Canon con espejo arriba y un flash manual simple no sincroniza en Live View; por eso existe el botón dedicado **`Modo Flash Zapata (Bajar Espejo)`** que conserva el USB vivo.
3. **Sin Bluetooth para RAWs ni Android en modo MTP en macOS:** Bluetooth no tiene ancho de banda para RAWs; en macOS Android debe ir en modo **PTP** (*Transferir imágenes*).
4. **No es un editor RAW final:** PhotoPic revela en GPU para validar nitidez real 1:1 y separa pares `RAW + JPG` con sidecars `.xmp`, pero no reemplaza a Lightroom, Capture One o Affinity.
