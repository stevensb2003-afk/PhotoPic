# Vista en Vivo (Live View), Disparo Remoto y Limitaciones por Sistema

PhotoPic incluye una pestaña dedicada **`Vista en Vivo`** dentro de cada sesión activa para encuadrar con **cuadrícula 3×3**, **espejo horizontal**, **guías de aspecto (`3:2`, `4:5`, `16:9`, `1:1`)** y disparo/referencia en vivo.

---

## 1. Arquitectura Elegida por Sistema Operativo

| Sistema | Motor Principal (Cero Conflicto USB) | Motor Clásico DSLR USB | Disparo Remoto |
| :--- | :--- | :--- | :--- |
| **macOS 14+** | `AVFoundation` (`AVCaptureSession`) para cámaras **UVC USB Streaming**, **Continuity Camera** y **capturadoras HDMI→USB** | Bridge opcional `gphoto2` (`brew install gphoto2`) para DSLRs antiguas sin HDMI (ej. Canon EOS 70D) | `ICCameraDevice.requestTakePicture()` (PTP), `gphoto2 --capture-image-and-download`, o captura de cuadro UVC |
| **Windows 10/11** | `OpenCV DirectShow` (`cv2.VideoCapture`) para cámaras **UVC** y **capturadoras HDMI→USB** | No se activa `libgphoto2` por defecto porque exigiría reemplazar el driver estándar **WPD** con **Zadig (`WinUSB`)** | Captura de cuadro de referencia JPEG a `RAW/` |

---

## 2. Qué SÍ Podés Hacer vs. Limitaciones Reales

### Qué SÍ hace PhotoPic
1. Ver video en vivo fluido (30–60 fps) por UVC o HDMI→USB **simultáneamente** mientras descargás tus RAWs por cable USB/Thunderbolt o Watchfolder.
2. En macOS, con `gphoto2` instalado vía Homebrew, pausar momentáneamente `ImageCaptureCore` para transmitir el visor en vivo por 1 solo cable USB en DSLRs clásicas y disparar directo a `RAW/`.
3. Evaluar encuadre con regla de tercios, espejo (para retratos frente al modelo) y recorte `4:5` / `16:9` / `3:2` / `1:1`.

### Limitaciones Reales (Qué NO hace)
1. **Sin `ImageCaptureCore` Live View nativo en Apple:** El framework oficial de tethering PTP de macOS no expone streaming de video continuo del sensor; sin UVC/HDMI se requiere `gphoto2` (o SDK propietario).
2. **Sin binarios GPL empaquetados en el `.dmg`:** `gphoto2` se detecta automáticamente en `/opt/homebrew/bin/gphoto2` o `/usr/local/bin/gphoto2` si el usuario lo instala (`brew install gphoto2`), manteniendo el `.dmg` liviano (`~2.4 MB`).
3. **Sin Bluetooth para RAWs ni Android en modo MTP en macOS:** Bluetooth no tiene ancho de banda para archivos RAW; y en macOS Android debe ir en modo **PTP** (*Transferir imágenes*).
4. **No es un editor RAW final:** PhotoPic revela en GPU para validar foco real 1:1 y separa pares `RAW + JPG` con sidecars `.xmp`, pero no reemplaza a Lightroom, Capture One o Affinity.
