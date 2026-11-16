# Guía de Instalación y Uso — macOS (Apple Silicon & Intel)

## 1. Instalación Rápida (`.dmg` o `.app`) y Asistente Guiado Inicial
1. Descargá `PhotoPic-Installer.dmg` desde **Releases** (o compilalo localmente con `bash macos/Scripts/package_macos_app.sh`).
2. Abrí el `.dmg` y arrastrá **PhotoPic.app** a tu carpeta **Aplicaciones (`/Applications`)**.
3. En la primera apertura, si macOS muestra aviso de desarrollador no identificado (firma ad-hoc local), hacé **clic derecho sobre PhotoPic.app → Abrir** (una sola vez).
4. Al abrirse, el **Asistente Inicial** audita tu Mac (CPU, RAM, Metal GPU y presencia de Neural Engine), te recomienda el perfil óptimo (con opción de apagar toda la IA desde el paso 1) y luego te pide tu **Carpeta Raíz Global**.

### D. Transmisores Wi-Fi / FTP / Air Direct (`Watchfolder` + `Bonjour`)
- PhotoPic escucha cámaras **Wi-Fi PTP/IP (Bonjour)** compatibles con macOS y además incluye el botón **"Vincular Carpeta / Wi-Fi..."** dentro de la sesión para monitorear al vuelo la carpeta donde tu transmisor o software Wi-Fi deposite los RAW/JPG.

### Gestión de Espacio en `Archivadas/`
Dentro de la pestaña **`Archivadas`** podés recuperar descartes con **`Recuperar para Edición`** (mueve `RAW + JPG` juntos hacia `Para_Edicion/{RAW,JPG}`), o bien eliminar una foto puntual (**`Eliminar archivo...`**) o vaciar todos los descartes de la sesión (**`Vaciar carpeta...`**) mediante un **Popover nativo de confirmación**.

---

## 2. Conectar Cámaras y Teléfonos por USB / Thunderbolt 4

### A. Cámaras DSLR / Mirrorless (Canon EOS 70D, Sony, Nikon, Fujifilm)
- Conectá el cable USB o Thunderbolt 4 directo al Mac.
- Si macOS **Fotos** o **Captura de Imagen (`PTPCamera`)** toma control exclusivo de la cámara, PhotoPic mostrará el estado **"Ocupado por macOS"**: abrí la píldora superior → **Liberar macOS** para reclamar la conexión PTP al instante.

### B. Teléfonos Android (Samsung Galaxy, Z Fold, Pixel, Xiaomi)
1. Conectá un cable de datos USB-C / Thunderbolt 4 y mantené la pantalla desbloqueada.
2. En la notificación USB del teléfono elegí **"Transferir imágenes (PTP)"** *(no uses MTP/"Transferir archivos", porque macOS no soporta MTP nativamente)*.
3. Para capturar RAW desde el celular, activá el modo **Pro** o **Expert RAW (`.DNG`)**. Si disparás en JPEG normal, PhotoPic habilita automáticamente el soporte móvil en el perfil del teléfono.

### C. iPhone / iPad (iOS)
- Conectá por cable Lightning / USB-C / Thunderbolt 4, desbloqueá el iPhone y tocá **Confiar en esta computadora**.
- Para capturar RAW en iPhone Pro, activá **Apple ProRAW (`.DNG`)**.

---

## 3. Compilar desde Código Fuente (SwiftPM / Xcode)
```bash
# Ejecutar suite de pruebas y generar capturas Retina
swift run PhotoPicVerify

# Compilar app firmada + instalador DMG
bash macos/Scripts/package_macos_app.sh
```
También podés abrir **`PhotoPic.xcodeproj`** directamente en Xcode 16+.
