# Mapa de Capas EGM y Referencia Técnica de Módulos
> **ID Documento**: `DOC-08` | **Módulo Sistema**: `egm-reference` | **Alcance**: `macOS (Swift 6)` + `Windows (Python / PySide6)`
> **Roles con Acceso**: `REFERENCIA-RBAC`, `SISTEMA-AUTO`
> **Propósito LLM**: Vincula cada documento funcional `DOC-XX` con las rutas exactas de código en `macos/` y `windows/`.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Mapa de Correspondencia Documentos vs Código Fuente | `REFERENCIA-RBAC` | `L016-L026` |
| 2 | 2. Invariantes de Arquitectura y Empaquetado | `SISTEMA-AUTO` | `L027-L031` |
<!-- TOC:END -->

## 1. Mapa de Correspondencia Documentos vs Código Fuente [ROL: REFERENCIA-RBAC]

| Documento | Capa macOS (`macos/PhotoPic/`) | Capa Windows (`windows/photopic_win/`) | Pruebas Asociadas |
| :--- | :--- | :--- | :--- |
| `DOC-01` Global, Grupos y Ayuda | `App/AppState.swift`, `App/PhotoPicApp.swift`, `Models/HelpGuideCatalog*.swift`, `Views/Help/HelpCenterView.swift`, `Views/Home/HomeDashboardView.swift`, `Views/Home/SessionCardView.swift`, `Views/Home/ImportSessionSheet.swift` | `main.py`, `ui_home.py`, `ui_home_dialogs.py`, `ui_help_dialog.py`, `session_metadata.py` | `HardwareAndArchiveDeleteVerification.swift`, `UISnapshotVerification.swift`, `test_import_rename_and_rotation.py` |
| `DOC-02` Auditoría Hardware | `Models/PerformancePreferences.swift`, `Services/HardwareCapabilityAuditor.swift`, `Views/Onboarding/GuidedSetupWizardView.swift`, `Views/Components/HardwareAuditSettingsBlock.swift`, `Views/Settings/GeneralSettingsView.swift` | `hardware_auditor.py`, `ui_setup_wizard.py` | `HardwareAndArchiveDeleteVerification.swift`, `test_windows_core.py` |
| `DOC-03` Captura USB/Wi-Fi | `Services/DeviceDiscoveryService.swift`, `Services/TetherCaptureService.swift`, `Services/TetherBaselineGate.swift`, `Services/FolderWatchTetherService.swift`, `Services/KnownDevicesStore.swift` | `wpd_tether_service.py`, `baseline_gate.py`, `scripts/wpd_bridge.ps1` | `CorePipelineVerification.swift`, `test_windows_core.py` |
| `DOC-04` Culling, Rotación, IA y Seleccionadas/Archivadas | `Services/RawImageRenderer.swift`, `Services/PhotoOrientationService.swift`, `Services/PhotoVisionAnalyzer.swift`, `Services/PhotoTagStore.swift`, `Services/SessionArchiveCleaner.swift`, `ViewModels/CullingSessionViewModel*.swift`, `Views/Workspace/SelectedPhotosView.swift`, `Views/Workspace/ArchivedPhotosView.swift`, `Views/Workspace/CullingControlsBar.swift` | `raw_renderer.py`, `photo_orientation.py`, `vision_autotagger.py`, `tag_store.py`, `archive_cleaner.py`, `ui_selected_tab.py`, `ui_archived_tab.py`, `ui_workspace.py`, `ui_workspace_bars.py` | `CorePipelineVerification.swift`, `HardwareAndArchiveDeleteVerification.swift`, `test_windows_core.py`, `test_import_rename_and_rotation.py` |
| `DOC-05` Carpetas, Importación y Pares RAW+JPG | `Models/PhotoSession.swift`, `Services/SessionFileManager*.swift`, `Services/SessionFolderImporter.swift`, `Services/SessionIngestRouter.swift` | `models.py`, `session_manager.py`, `session_metadata.py`, `folder_importer.py`, `ingest_router.py` | `CorePipelineVerification.swift`, `HardwareAndArchiveDeleteVerification.swift`, `test_windows_core.py`, `test_import_rename_and_rotation.py` |
| `DOC-07` Vista en Vivo y Flash (`DOC-06` mod.) | `Services/DirectCanonUSBPTPService.swift`, `Services/CanonPTPCapabilities.swift`, `Services/LiveViewCameraService.swift`, `Services/GPhoto2LiveBridge.swift`, `Views/Workspace/LiveViewWorkspacePane.swift` | `ui_live_view.py`, `ui_workspace_bars.py`, `ui_workspace.py` | `HardwareAndArchiveDeleteVerification.swift`, `UISnapshotVerification.swift` |

## 2. Invariantes de Arquitectura y Empaquetado [ROL: SISTEMA-AUTO]

1. Todo archivo `.swift` y `.py` del proyecto respeta un máximo estricto de `300` líneas por archivo.
2. En macOS `PhotoPic.entitlements` corre sin App Sandbox (`app-sandbox = false`) con permisos explícitos de cámara y USB para soportar `AVFoundation`, `ImageCaptureCore`, liberación de `PTPCamera` y bridge opcional `gphoto2`.
3. Toda actualización de esta carpeta finaliza ejecutando `build-llm-toc-index.mjs` para verificar `<= 500` líneas y exactitud de coordenadas `Lxxx-Lyyy`.
