# Mapa de Capas EGM y Referencia Técnica de Módulos
> **ID Documento**: `DOC-06` | **Módulo Sistema**: `egm-reference` | **Alcance**: `macOS (Swift 6)` + `Windows (Python / PySide6)`
> **Roles con Acceso**: `REFERENCIA-RBAC`, `SISTEMA-AUTO`
> **Propósito LLM**: Vincula cada documento funcional `DOC-XX` con las rutas exactas de modelos, servicios, ViewModels y vistas en disco.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Mapa de Correspondencia `DOC-XX` vs Código Fuente | `REFERENCIA-RBAC` | `L016-L025` |
| 2 | 2. Invariantes de Arquitectura y Verificación | `SISTEMA-AUTO` | `L026-L030` |
<!-- TOC:END -->

## 1. Mapa de Correspondencia `DOC-XX` vs Código Fuente [ROL: REFERENCIA-RBAC]

| Documento | Capa macOS (`macos/PhotoPic/`) | Capa Windows (`windows/photopic_win/`) | Pruebas Asociadas |
| :--- | :--- | :--- | :--- |
| `DOC-01` Global y Ayuda | `App/AppState.swift`, `App/PhotoPicApp.swift`, `Models/HelpGuideCatalog.swift`, `Views/Help/HelpCenterView.swift`, `Views/Home/TopDeviceStatusBar.swift` | `main.py`, `ui_home.py`, `ui_help_dialog.py` | `UISnapshotVerification.swift` |
| `DOC-02` Auditoría Hardware | `Models/PerformancePreferences.swift`, `Services/HardwareCapabilityAuditor.swift`, `Views/Onboarding/GuidedSetupWizardView.swift`, `Views/Components/HardwareAuditSettingsBlock.swift`, `Views/Settings/GeneralSettingsView.swift` | `hardware_auditor.py`, `ui_setup_wizard.py` | `HardwareAndArchiveDeleteVerification.swift`, `test_windows_core.py` |
| `DOC-03` Captura USB/Wi-Fi | `Services/DeviceDiscoveryService.swift`, `Services/TetherCaptureService.swift`, `Services/TetherBaselineGate.swift`, `Services/FolderWatchTetherService.swift`, `Services/KnownDevicesStore.swift` | `wpd_tether_service.py`, `baseline_gate.py`, `scripts/wpd_bridge.ps1` | `CorePipelineVerification.swift`, `test_windows_core.py` |
| `DOC-04` Culling, IA y Archivadas | `Services/RawImageRenderer.swift`, `Services/PhotoVisionAnalyzer.swift`, `Services/PhotoTagStore.swift`, `Services/SessionArchiveCleaner.swift`, `ViewModels/CullingSessionViewModel*.swift`, `Views/Workspace/ArchivedPhotosView.swift`, `Views/Workspace/ArchivedDeletePopovers.swift` | `raw_renderer.py`, `vision_autotagger.py`, `tag_store.py`, `archive_cleaner.py`, `ui_archived_tab.py`, `ui_workspace.py` | `CorePipelineVerification.swift`, `HardwareAndArchiveDeleteVerification.swift`, `test_windows_core.py` |
| `DOC-05` Carpetas y Pares RAW+JPG | `Models/PhotoSession.swift`, `Services/SessionFileManager.swift`, `Services/SessionFileManager+BucketSync.swift`, `Services/SessionIngestRouter.swift` | `models.py`, `session_manager.py`, `ingest_router.py` | `CorePipelineVerification.swift`, `HardwareAndArchiveDeleteVerification.swift`, `test_windows_core.py` |

## 2. Invariantes de Arquitectura y Verificación [ROL: SISTEMA-AUTO]

1. Todo archivo fuente `.swift` y `.py` del repositorio respeta un máximo estricto de `300` líneas por archivo.
2. Toda modificación funcional en `macos/` o `windows/` se valida mediante `swift run PhotoPicVerify`, `python3 -m unittest discover -s windows/tests -v` y `bash macos/Scripts/package_macos_app.sh`.
3. Toda actualización de esta carpeta documental finaliza ejecutando `build-llm-toc-index.mjs` para mantener exactitud matemática en `Lxxx-Lyyy`.
