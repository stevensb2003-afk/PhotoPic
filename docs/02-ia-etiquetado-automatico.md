# IA Offline: Detección de Caras, Ojos, Poses y Conteo de Personas

PhotoPic ejecuta análisis de visión por computadora **100% en local y sin internet** conforme ingresan las fotos (tanto por cable USB/Thunderbolt como al abrir sesiones existentes).

---

## 1. Motor por Plataforma

| Plataforma | Motor Nativo Offline | Aceleración |
| :--- | :--- | :--- |
| **macOS 14+** | Apple **Vision.framework** (`VNDetectFaceLandmarksRequest`, `VNDetectFaceCaptureQualityRequest`, `VNDetectHumanBodyPoseRequest`, `VNDetectHumanRectanglesRequest`) | Apple Neural Engine + GPU Metal |
| **Windows 10/11** | Google **MediaPipe** (`FaceDetection`, `FaceMesh` 468 puntos, `Pose` 33 puntos) con fallback automático a OpenCV Haar | CPU multi-hilo x64 |

---

## 2. Etiquetas Generadas Automáticamente

| Categoría | Etiquetas Emitidas | Criterio Técnico |
| :--- | :--- | :--- |
| **Conteo de personas** | `Sin personas`, `1 persona` + `Individual`, `2 personas` + `Pareja`, `N personas` + `Grupo` (3–5) o `Grupo grande` (6+) | Fusión deduplicada entre rostros, esqueletos corporales y siluetas humanas (`anchorsX`). |
| **Encuadre** | `Primer plano`, `Plano medio`, `Cuerpo entero`, `Retrato` | Altura relativa de caja facial (`>= 25%`, `>= 10%`) o detección de tobillos/cuerpo completo. |
| **Ojos y nitidez facial** | `Ojos abiertos`, `Ojos cerrados` (badge ámbar de alerta), `Rostro nítido` | Cálculo de **Eye Aspect Ratio (EAR)** en landmarks oculares + `faceCaptureQuality >= 0.60`. |
| **Pose corporal** | `Brazos arriba`, `Manos en cintura`, `De pie`, `Sentado`, `Pose dinámica` | Relaciones geométricas entre hombros, muñecas, caderas y rodillas. |

---

## 3. Cómo Filtra y Persiste PhotoPic tus Etiquetas

1. **Barra superior de filtros (`IA:`):** En el espacio de trabajo podés hacer clic en cualquier chip (`Pareja`, `Brazos arriba`, `Ojos cerrados`, etc.) para filtrar al instante la cola pendiente sin mover archivos del disco.
2. **Etiquetas manuales (`+ Etiqueta`):** Podés agregar etiquetas propias desde el HUD de la foto (ej. `Novia`, `Favorita`, `Repetir`).
3. **Triple persistencia compatible con flujo profesional:**
   - `.photopic_tags.json` en la raíz de la sesión (mantiene todas las etiquetas aunque muevas una foto entre `RAW/`, `Para_Edicion/` y `Archivadas/`).
   - **Sidecar estándar Adobe `.xmp` (`<dc:subject>` + `<photopic:PersonCount>`):** Se guarda junto al RAW y **viaja físicamente** con él cuando aprobás, archivás o deshacés con `⌘Z`, listo para **Lightroom Classic**, **Camera Raw**, **Capture One** o **Bridge**.
   - **macOS Finder Tags:** Se aplican directamente sobre el archivo físico para buscarlo desde Spotlight o Finder.
