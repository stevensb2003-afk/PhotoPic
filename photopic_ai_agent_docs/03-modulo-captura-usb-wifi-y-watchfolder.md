# Módulo: Captura Tethered USB, Wi-Fi PTP/IP, Android PTP y Watchfolder
> **ID Documento**: `DOC-03` | **Módulo Sistema**: `tether-discovery` | **Pantallas**: `Barra Superior`, `Configuración → Dispositivos`, `Watchfolder`
> **Roles con Acceso**: `FOTOGRAFO`, `ASISTENTE`, `ADMIN-EQUIPO`
> **Propósito LLM**: Guía paso a paso para conectar cámaras DSLR/Mirrorless, smartphones Android/iPhone, transmisores Wi-Fi y Watchfolders.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Propósito de Negocio y Modos de Captura | `TODOS` | `L020-L023` |
| 2 | 2. Procesos Operativos Paso a Paso | `FOTOGRAFO` | `L024-L040` |
| 3 | ↳ 2.1 Conectar cámara DSLR/Mirrorless o teléfono por USB | `FOTOGRAFO` | `L026-L031` |
| 4 | ↳ 2.2 Liberar cámara ocupada por macOS Fotos / PTPCamera | `FOTOGRAFO` | `L032-L035` |
| 5 | ↳ 2.3 Conectar transmisor Wi-Fi, FTP o lector SD vía Watchfolder | `FOTOGRAFO` | `L036-L040` |
| 6 | 3. Reglas de Perfil de Dispositivo y Escudo Anti-Galería Vieja | `ADMIN-EQUIPO` | `L041-L046` |
<!-- TOC:END -->

## 1. Propósito de Negocio y Modos de Captura [ROL: TODOS]

Este módulo recibe cada fotografía segundos después de disparar, protegiendo las tarjetas SD o carretes de teléfono con miles de fotos antiguas mediante el **Escudo Anti-Galería Vieja**. Soporta 3 vías de entrada: cable directo (**USB-C / Thunderbolt 4 / Lightning**), red local inalámbrica (**Wi-Fi PTP/IP Bonjour** en macOS) y monitoreo de carpeta (**Watchfolder** en macOS y Windows).

## 2. Procesos Operativos Paso a Paso [ROL: FOTOGRAFO]

### 2.1 Conectar cámara DSLR/Mirrorless o teléfono por USB [ROL: FOTOGRAFO]
1. Conecta el cable USB o Thunderbolt 4 directo a la computadora.
2. En **Android**, desbloquea la pantalla y elige **"Transferir imágenes (PTP)"** en la notificación USB (en Windows también funciona MTP).
3. En **iPhone/iPad**, desbloquea y toca **Confiar en esta computadora**.
4. Si el dispositivo es nuevo, aparece un banner superior: pulsa **`Conectar y Guardar`**. Si ya estaba guardado con **Auto-conectar**, se vincula en menos de 1 segundo con notificación flotante.

### 2.2 Liberar cámara ocupada por macOS Fotos / PTPCamera [ROL: FOTOGRAFO]
1. Si la píldora superior muestra **`Ocupado por macOS`**, abre el Administrador de Dispositivos haciendo clic sobre la píldora.
2. Pulsa **`Liberar macOS`** para cerrar `PTPCamera` y reclamar la sesión PTP al instante sin desconectar el cable.

### 2.3 Conectar transmisor Wi-Fi, FTP o lector SD vía Watchfolder [ROL: FOTOGRAFO]
1. Dentro de una sesión abierta, pulsa **`Vincular Carpeta / Wi-Fi...`** en macOS (o **`Vincular Carpeta/SD USB...`** en Windows).
2. Selecciona la carpeta donde tu transmisor Wi-Fi (ej. Air Direct, CamRanger, FTP local, EOS Utility Wi-Fi o Nikon NX Tether) deposita las fotos nuevas.
3. PhotoPic indexa silenciosamente los archivos ya existentes en esa carpeta y comienza a ingerir solo las fotos nuevas una vez que su tamaño en disco se estabiliza.

## 3. Reglas de Perfil de Dispositivo y Escudo Anti-Galería Vieja [ROL: ADMIN-EQUIPO]

1. **Huella Única:** Identifica cada cámara/teléfono por número de serie, UUID o `usbVendorID + usbProductID + nombre`.
2. **Switch `Mantener originales en el dispositivo`:** Activado por defecto para no borrar nunca la tarjeta SD del cliente.
3. **Switch `Permitir filtrar JPG/HEIC cuando no dispare en RAW/DNG`:** Activado por defecto en celulares para usarlos como cámara de apoyo si no disparan en modo Pro/DNG.
4. **Cero descargas antiguas:** `TetherBaselineGate` ignora todo archivo previo al timestamp de conexión (`connectedAtTimestamp`) y todo archivo ya indexado durante la enumeración inicial.
