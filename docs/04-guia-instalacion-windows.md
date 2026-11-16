# Guía de Instalación y Uso — Windows 10 / 11 (x64)

La edición de **PhotoPic para Windows** comparte el mismo esquema de carpetas (`RAW/`, `JPG/`, `Para_Edicion/`, `Archivadas/`), los mismos 36 formatos, la misma protección anti-galería antigua y el mismo formato `.photopic_tags.json` + sidecars `.xmp` que la versión de macOS.

---

## 1. Requisitos del Sistema
- Windows 10 u 11 (64 bits).
- **Opción A (Ejecutable portable):** Descargá `PhotoPic-Windows-x64.zip` desde **GitHub Releases**, descomprimilo y ejecutá `PhotoPic.exe`.
- **Opción B (Desde código fuente):** Python 3.10 – 3.12.

---

## 2. Ejecutar o Compilar `PhotoPic.exe` desde Código Fuente

```powershell
cd windows
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Ejecutar la aplicación directamente
python -m photopic_win.main
```

Para generar el ejecutable independiente **`dist\PhotoPic-Windows\PhotoPic.exe`** con el ícono nativo `AppIcon.ico`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\scripts\build_windows_exe.ps1
```

---

## 3. Tethering en Windows (WPD USB + Watchfolder / Tarjeta SD)

1. **Teléfonos Android y iPhone / Cámaras PTP:** Windows soporta de fábrica tanto **MTP ("Transferir archivos")** como **PTP ("Transferir imágenes")** a través de **Windows Portable Devices (`Shell.Application`)** (`windows/scripts/wpd_bridge.ps1`).
2. **Watchfolder directo para cámaras con software del fabricante / lectores USB-C:** Desde el espacio de trabajo podés pulsar **"Vincular Carpeta/SD USB..."** para monitorear en vivo cualquier carpeta de captura (por ejemplo de EOS Utility, Nikon NX Tether o una tarjeta CFexpress/SD conectada por Thunderbolt 4).
3. El escudo `TetherBaselineGate` indexa las fotos previas al vincular para que **nunca se descarguen fotos viejas**.

---

## 4. Pruebas Automatizadas en Windows

```powershell
python -m unittest discover -s windows/tests -v
```
