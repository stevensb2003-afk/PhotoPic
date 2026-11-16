# Módulo: Asistente Guiado Inicial y Auditor de Capacidad de Hardware
> **ID Documento**: `DOC-02` | **Módulo Sistema**: `hardware-auditor` | **Pantallas**: `Asistente Inicial (Paso 1 y Paso 2)`, `Configuración → General y Rendimiento`
> **Roles con Acceso**: `ADMIN-EQUIPO` (configuración), `TODOS` (consulta de perfil)
> **Propósito LLM**: Detalla cómo PhotoPic audita CPU, RAM, GPU Metal y Apple Neural Engine, y cómo desactivar o regular la IA.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Propósito y Origen del Motor Neural Engine | `TODOS` | `L020-L023` |
| 2 | 2. Qué Inspecciona el Auditor al Arrancar | `SISTEMA-AUTO` | `L024-L030` |
| 3 | 3. Reglas de Recomendación Automática de Perfiles | `SISTEMA-AUTO` | `L031-L036` |
| 4 | 4. Procesos Paso a Paso | `ADMIN-EQUIPO` | `L037-L049` |
| 5 | ↳ 4.1 Cómo completar el Asistente Guiado Inicial | `ADMIN-EQUIPO` | `L039-L044` |
| 6 | ↳ 4.2 Cómo prender, apagar la IA o re-auditar en vivo | `ADMIN-EQUIPO` | `L045-L049` |
<!-- TOC:END -->

## 1. Propósito y Origen del Motor Neural Engine [ROL: TODOS]

El **Apple Neural Engine (ANE)** no es una librería externa ni una descarga de terceros: es un acelerador físico integrado dentro de los procesadores Apple Silicon (M1, M2, M3, M4, M5). En macOS, `Vision.framework` despacha la detección de rostros y poses sobre ese bloque físico cuando existe; en Macs Intel (sin ANE) o PCs Windows (`MediaPipe`/OpenCV), la inferencia corre en CPU/GPU. Para evitar lentitud en equipos modestos, PhotoPic audita el hardware antes de empezar y permite apagar la IA por completo.

## 2. Qué Inspecciona el Auditor al Arrancar [ROL: SISTEMA-AUTO]

1. **Arquitectura y Procesador:** Distingue `Apple Silicon (arm64)` vs `Intel (x86_64)` en macOS, o procesador/arquitectura x64 en Windows.
2. **Apple Neural Engine / Motores Windows:** Reporta si el equipo cuenta con ANE físico integrado (macOS) o si `MediaPipe` y `OpenCV` están disponibles (Windows).
3. **Memoria RAM y Núcleos Activos:** Lee memoria física total en GB y núcleos lógicos disponibles.
4. **GPU Metal (macOS):** Verifica disponibilidad de dispositivo gráfico Metal para revelado `CIRAWFilter`.

## 3. Reglas de Recomendación Automática de Perfiles [ROL: SISTEMA-AUTO]

1. **Modo Ligero (Sin IA · Solo Tethering y RAW):** Se recomienda cuando RAM `< 8 GB`, núcleos `< 4` o no hay GPU Metal (o en Windows faltan `MediaPipe` y `OpenCV`). Desactiva toda la IA en segundo plano y reduce el viewport a `1600 px` (`1280 px` en Windows).
2. **Equilibrado (GPU + Rostros Rápidos):** Se recomienda en Macs Intel sin Neural Engine o equipos con `8–11 GB` de RAM. Analiza conteo de rostros y ojos abiertos/cerrados, omitiendo el modelo corporal pesado de 19 articulaciones.
3. **Estudio Completo (GPU + IA Completa):** Se recomienda en Apple Silicon con Neural Engine y `>= 12 GB` de RAM (o Windows con `MediaPipe`, `>= 12 GB` de RAM y `>= 6` núcleos). Activa rostros, parpadeo y poses de cuerpo completo.

## 4. Procesos Paso a Paso [ROL: ADMIN-EQUIPO]

### 4.1 Cómo completar el Asistente Guiado Inicial [ROL: ADMIN-EQUIPO]
1. Al abrir PhotoPic por primera vez, observa las 4 tarjetas de diagnóstico de hardware en el **Paso 1: Auditoría de Capacidad**.
2. Acepta el perfil marcado como **Recomendado** o selecciona manualmente **Modo Ligero (Sin IA)** si querés priorizar batería o velocidad pura.
3. Ajusta los switches individuales si deseás conservar solo detección de caras sin poses corporales.
4. Pulsa **`Continuar al Paso 2 →`**, revisa el esquema de subcarpetas (`Para_Edicion/{RAW,JPG}` y `Archivadas/{RAW,JPG}`) y pulsa **`Elegir Carpeta Raíz...`** para finalizar.

### 4.2 Cómo prender, apagar la IA o re-auditar en vivo [ROL: ADMIN-EQUIPO]
1. Abre **Configuración (`⌘,`) → pestaña `General y Rendimiento`** (en Windows, botón **`Rendimiento e IA...`**).
2. Cambia de perfil o apaga **`Activar auto-etiquetado IA de caras y personas al capturar`** (o solo **`Incluir detección corporal de poses`**).
3. El cambio surte efecto inmediato sobre la sesión abierta sin reiniciarla: si apagas la IA, la cola de análisis en curso se cancela al instante.
4. Pulsa **`Re-auditar`** para volver a evaluar tu máquina y aplicar el perfil recomendado.
