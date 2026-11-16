# Arquitectura Modular de PhotoPic

Todo el código fuente de PhotoPic respeta un límite estricto de modularidad (**≤ 300 líneas por archivo**) tanto en Swift (macOS) como en Python (Windows), con una separación estricta entre **Design System**, **Modelos**, **Servicios**, **ViewModels** y **Vistas**.

---

## 1. Flujo en Tiempo Real: Disparo USB → IA → Disco

```mermaid
flowchart LR
    A["Cámara DSLR / Android PTP / iPhone"] -->|"USB / Thunderbolt 4"| B["TetherCaptureService / WPD"]
    B -->|"Escudo Anti-Galería Vieja"| C{"TetherBaselineGate"}
    C -->|"Foto previa"| D["Ignorada (Solo índice)"]
    C -->|"Disparo nuevo"| E["Descarga Atómica Staging"]
    E --> F["SessionIngestRouter"]
    F -->|"RAW (.CR2/.DNG/...)"| G["Sesión/RAW/"]
    F -->|"Par .JPG/.HEIC"| H["Sesión/JPG/"]
    G --> I["RawImageRenderer (Metal / LibRaw)"]
    I --> J["PhotoVisionAnalyzer (Caras · Ojos · Poses)"]
    J --> K["PhotoTagStore (.json + .xmp + Finder)"]
    G --> L["Cola Tinder (Sin interrumpir pantalla)"]
    L -->|"→ / Swipe Derecha"| M["Para_Edicion/{RAW,JPG} (+ .xmp)"]
    L -->|"← / Swipe Izquierda"| N["Archivadas/{RAW,JPG} (+ .xmp)"]
```

---

## 2. Secuencia de Protección Anti-Galería Vieja

```mermaid
sequenceDiagram
    participant USB as Cámara / Celular USB
    participant Disc as DeviceDiscoveryService
    participant Gate as TetherBaselineGate
    participant Ingest as SessionIngestRouter

    USB->>Disc: Conexión USB (Hot-Plug)
    Disc->>Gate: Registra connectedAtTimestamp
    loop Hasta deviceDidBecomeReady
        USB-->>Gate: Archivos existentes (carrete / SD)
        Gate->>Gate: Indexa claves en baselineKeys (0 descargas)
    end
    Gate->>Gate: markCatalogComplete() + Inicia Smart Delta Watcher (1.5s)
    USB->>Gate: Nuevo disparo (didAdd / Delta Poll)
    Gate-->>Ingest: Autoriza descarga atómica -> RAW/ + JPG/
```

---

## 3. Estructura de Módulos

```text
PhotoSelect/
├── assets/                          # logo.svg, iconos Pictogrammers SVG, capturas Retina
├── docs/                            # Guías técnicas y manuales de usuario
├── macos/
│   ├── PhotoPic/
│   │   ├── App/                     # PhotoPicApp, AppState
│   │   ├── DesignSystem/            # AppColors, AppTypography, AppSpacing, AppRadius, AppMotion, PictogrammersIcons
│   │   ├── Models/                  # PhotoItem, PhotoExifMetadata, PhotoVisionTags, PhotoSession,
│   │   │                            # KnownDevice, ConnectedDeviceState, PerformancePreferences, HelpGuideCatalog
│   │   ├── Services/                # BookmarkManager, KnownDevicesStore, DeviceDiscoveryService, TetherCaptureService,
│   │   │                            # TetherBaselineGate, FolderWatchTetherService, SessionFileManager (+BucketSync),
│   │   │                            # SessionIngestRouter, SessionArchiveCleaner, RawImageRenderer,
│   │   │                            # ExifMetadataReader, PhotoVisionAnalyzer, PhotoTagStore, HardwareCapabilityAuditor
│   │   ├── ViewModels/              # HomeViewModel, DeviceManagerViewModel, CullingSessionViewModel (+Actions/Rendering/Vision)
│   │   └── Views/                   # Onboarding (+GuidedSetupWizardView), Home, Workspace (+ArchivedDeletePopovers),
│   │                                # Settings, Help (+HelpCenterView), Components (+HardwareAuditSettingsBlock)
│   ├── Resources/                   # Info.plist, PhotoPic.entitlements, AppIcon.icns
│   ├── Scripts/                     # generate_icon.swift, generate_xcodeproj.py, package_macos_app.sh
│   └── Verification/                # SyntheticDNGGenerator, CorePipelineVerification, HardwareAndArchiveDeleteVerification,
│                                    # UISnapshotVerification
└── windows/
    ├── photopic_win/                # main, design_system, hardware_auditor, models, baseline_gate, tag_store,
    │                                # session_manager, ingest_router, archive_cleaner, raw_renderer, vision_autotagger,
    │                                # wpd_tether_service, ui_home, ui_setup_wizard, ui_archived_tab, ui_help_dialog, ui_workspace
    ├── scripts/                     # wpd_bridge.ps1, build_windows_exe.ps1
    └── tests/                       # test_windows_core.py
```
