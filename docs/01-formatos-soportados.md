# Formatos de Imagen Soportados en PhotoPic

PhotoPic clasifica automáticamente cada archivo entrante en **RAW maestro de sensor** (entra a `RAW/` para revelado puro y culling 1:1) o **formato comprimido/móvil** (se separa en `JPG/` si existe su par RAW, o entra a `RAW/` si el dispositivo tiene activo *"Permitir filtrar JPG/HEIC cuando no dispare en RAW/DNG"*).

---

## 1. Formatos RAW Soportados (`25` extensiones)

> [!IMPORTANT]
> **Cero miniaturas JPG incrustadas:** En macOS todos los RAW se revelan directamente desde los datos del sensor mediante `CIRAWFilter` sobre GPU Metal (`isDraftModeEnabled = false`), y en Windows mediante el motor C++ `LibRaw` (`rawpy`).

| Fabricante / Dispositivo | Extensiones RAW | Notas de Compatibilidad |
| :--- | :--- | :--- |
| **Android (Pro / Expert RAW / OpenCamera) & iPhone ProRAW / Leica / Ricoh** | `.DNG` | Estándar abierto Adobe Digital Negative (Bayer CFA y LinearRaw 16-bit). |
| **Canon (DSLR y Mirrorless EOS R)** | `.CR2`, `.CR3`, `.CRW` | Incluye Canon EOS 70D, 5D/6D, R5, R6, R7, R8, etc. |
| **Nikon (DSLR y Z Series)** | `.NEF`, `.NRW` | Z6/Z7/Z8/Z9, D750/D850 y compactas Coolpix RAW. |
| **Sony Alpha / Cyber-shot** | `.ARW`, `.SRF`, `.SR2` | A7 III/IV/RV, A6xxx, FX3, ZV-E1, RX100. |
| **Fujifilm X & GFX** | `.RAF` | Sensores X-Trans y Bayer en X-T5, X-H2, X100VI, GFX. |
| **Olympus / OM System** | `.ORF`, `.ORI` | OM-1, E-M1, PEN. |
| **Panasonic Lumix** | `.RW2`, `.RAW` | GH5/GH6, S5 II, LX100. |
| **Samsung NX / Galaxy Pro** | `.SRW`, `.DNG` | Cámaras NX y Galaxy S/Z Fold en modo Pro/Expert RAW. |
| **Pentax** | `.PEF`, `.DNG` | K-1, K-3, KP. |
| **Formato Medio y Otros** | `.3FR`, `.FFF` *(Hasselblad)*, `.IIQ` *(Phase One)*, `.RWL` *(Leica)*, `.ERF` *(Epson)*, `.MOS` *(Leaf)*, `.MRW` *(Minolta)*, `.DCR`, `.KDC` *(Kodak)* | Soportados en el clasificador maestro y decodificación nativa. |

---

## 2. Formatos Comprimidos y Móviles (`11` extensiones)

| Formato | Extensión | Uso Común |
| :--- | :--- | :--- |
| **JPEG estándar** | `.JPG`, `.JPEG` | Copias paralelas RAW+JPG en DSLR o disparos estándar en Android. |
| **HEIF / HEIC (Apple y Canon 10-bit)** | `.HEIC`, `.HEIF`, `.HIF` | Cámaras iPhone/iPad (captura normal) y Canon R en HDR PQ. |
| **Formatos Web / Next-Gen** | `.AVIF`, `.JXL`, `.WEBP` | Exportaciones modernas y móviles Android recientes. |
| **Lossless / Escaneo** | `.PNG`, `.TIF`, `.TIFF` | Pruebas de estudio, escaneos y archivos de flujo intermedio. |

---

## 3. Regla de Separación Automática RAW + Comprimido

1. Si disparás en **RAW + JPG** (ej. `IMG_0042.CR2` + `IMG_0042.JPG` o `S24_0042.DNG` + `S24_0042.JPG`):
   - `IMG_0042.CR2` entra a `RAW/` (fuente única de la cola tipo Tinder).
   - `IMG_0042.JPG` se separa automáticamente a `JPG/`.
2. **Promoción tardía en celulares:** Si un teléfono Android transfiere el `.JPG` unos milisegundos antes que el `.DNG` y tiene el fallback activado, PhotoPic muestra temporalmente el `.JPG` y, en cuanto entra `S24_0042.DNG`, mueve el `.JPG` a `JPG/` y promueve el `.DNG` sin duplicar la foto en la cola.
