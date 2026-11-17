import AppKit
import SwiftUI

/// Live View studio workspace tab supporting UVC / HDMI-USB (`AVFoundation`)
/// and optional classic DSLR USB streaming (`gphoto2`) with framing guides & shutter.
package struct LiveViewWorkspacePane: View {
    private enum BridgeMode: String, CaseIterable, Identifiable {
        case nativeUVC = "UVC / HDMI-USB"
        case networkMJPEG = "Android / IP Wi-Fi"
        case classicGPhoto2 = "DSLR USB (gphoto2)"
        var id: String { rawValue }
    }

    @Bindable var appState: AppState
    @Bindable var viewModel: CullingSessionViewModel
    @State private var bridgeMode: BridgeMode = .nativeUVC
    @State private var captureFeedback: String?

    package init(appState: AppState, viewModel: CullingSessionViewModel) {
        self.appState = appState
        self.viewModel = viewModel
    }

    private var live: LiveViewCameraService { appState.liveViewService }
    private var gphoto: GPhoto2LiveBridge { appState.gphotoBridge }
    private var network: NetworkMJPEGStreamService { appState.networkStreamService }
    private var isLiveActive: Bool {
        switch bridgeMode {
        case .nativeUVC: return live.isRunning
        case .networkMJPEG: return network.isStreaming
        case .classicGPhoto2: return gphoto.isStreaming
        }
    }

    package var body: some View {
        VStack(spacing: 0) {
            liveToolbar
            ZStack {
                AppColors.stageBackground
                if let frame = live.currentFrame, isLiveActive {
                    liveFrameStage(frame)
                } else {
                    LiveViewCompatibilityCard(
                        connectedDevice: appState.discoveryService.primaryLiveDevice,
                        modeTitle: emptyModeTitle,
                        explanation: emptyExplanation,
                        feedbackMessage: captureFeedback ?? live.statusMessage ?? network.statusNote ?? gphoto.statusNote,
                        isActive: isLiveActive,
                        onToggle: { Task { await toggleStream() } }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            liveBottomBar
        }
        .background(AppColors.stageBackground)
        .onAppear { live.refreshDevices() }
        .onDisappear { appState.stopAllLiveView() }
    }

    private var liveToolbar: some View {
        HStack(spacing: AppSpacing.sm) {
            Picker("Modo", selection: $bridgeMode) {
                ForEach(BridgeMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 375)
            .onChange(of: bridgeMode) { _, _ in
                appState.stopAllLiveView()
            }

            if bridgeMode == .nativeUVC {
                Picker("Cámara", selection: Binding(
                    get: { live.selectedDeviceID ?? "" },
                    set: { live.selectedDeviceID = $0 }
                )) {
                    if live.availableDevices.isEmpty {
                        Text("Sin cámara UVC / HDMI").tag("")
                    } else {
                        ForEach(live.availableDevices) { dev in
                            Text("\(dev.localizedName) (\(dev.transportNote))").tag(dev.id)
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 250)

                Button {
                    live.refreshDevices()
                    gphoto.refreshAvailability()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help("Actualizar cámaras UVC/Continuity/HDMI y gphoto2")
            } else if bridgeMode == .networkMJPEG {
                TextField("http://192.168.1.50:8080/video", text: Binding(
                    get: { network.streamURLString },
                    set: { network.streamURLString = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.monoCaption)
                .frame(width: 245)
            }

            Spacer()

            Toggle("3×3", isOn: Binding(get: { live.showThirdsGrid }, set: { live.showThirdsGrid = $0 }))
                .toggleStyle(.button)
                .controlSize(.small)

            Toggle("Espejo", isOn: Binding(get: { live.mirrorHorizontally }, set: { live.mirrorHorizontally = $0 }))
                .toggleStyle(.button)
                .controlSize(.small)

            Picker("Guía", selection: Binding(get: { live.aspectGuide }, set: { live.aspectGuide = $0 })) {
                ForEach(LiveAspectGuide.allCases) { g in Text(g.rawValue).tag(g) }
            }
            .labelsHidden()
            .frame(width: 132)

            Button(isLiveActive ? "Detener Vivo" : "Iniciar Vista en Vivo") {
                Task { await toggleStream() }
            }
            .buttonStyle(StudioButtonStyle(isLiveActive ? .archiveCoral : .primaryLight, compact: true))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle().frame(height: AppSpacing.hairline).foregroundStyle(AppColors.borderSubtle),
            alignment: .bottom
        )
    }

    private func liveFrameStage(_ cgImage: CGImage) -> some View {
        GeometryReader { geo in
            ZStack {
                Image(decorative: cgImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(x: live.mirrorHorizontally ? -1 : 1, y: 1)
                    .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)

                if live.showThirdsGrid {
                    LiveThirdsGridOverlay()
                }
                if let targetRatio = live.aspectGuide.aspectRatio {
                    LiveAspectMaskOverlay(containerSize: geo.size, targetRatio: targetRatio)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(AppSpacing.md)
    }

    private var emptyModeTitle: String {
        switch bridgeMode {
        case .nativeUVC: return "Vista en Vivo UVC / Continuidad iOS / HDMI-USB"
        case .networkMJPEG: return "Vista en Vivo Android / Cámara IP Wi-Fi (MJPEG)"
        case .classicGPhoto2: return "Vista en Vivo DSLR Clásica vía gphoto2 USB"
        }
    }

    private var emptyExplanation: String {
        switch bridgeMode {
        case .nativeUVC:
            return "Detecta automáticamente iPhone Continuidad, cámaras UVC, Android con Webcam USB (Pixel/Moto) o DroidCam/Camo y capturadoras HDMI→USB sin cortar el tethering."
        case .networkMJPEG:
            return "Abrí IP Webcam (puerto :8080/video) o DroidCam (:4747/video) en tu Android y conectá por Wi-Fi local mientras el cable USB sigue pasando fotos PTP a RAW/."
        case .classicGPhoto2:
            if gphoto.isAvailable {
                return "gphoto2 detectado (\(gphoto.executablePath ?? "")). Al iniciar, PhotoPic pausa ImageCaptureCore temporalmente para transmitir el visor por USB y disparar directo a RAW/."
            }
            return "gphoto2 no está instalado en este Mac. Para usarlo con DSLRs clásicas (ej. Canon EOS 70D) por un único cable USB ejecutá: brew install gphoto2"
        }
    }

    private var liveBottomBar: some View {
        HStack(spacing: AppSpacing.md) {
            let statusLabel: String = switch bridgeMode {
            case .nativeUVC: "\(live.availableDevices.count) fuente(s) UVC / Continuidad / HDMI"
            case .networkMJPEG: network.statusNote ?? "Stream IP Wi-Fi simultáneo al cable PTP"
            case .classicGPhoto2: gphoto.isAvailable ? "gphoto2 listo" : "Modo DSLR USB requiere brew install gphoto2"
            }
            Text(statusLabel)
                .font(AppTypography.monoCaption)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            if appState.discoveryService.canTriggerPrimaryShutter {
                Button {
                    let ok = appState.discoveryService.triggerPrimaryRemoteShutter()
                    captureFeedback = ok ? "Disparo PTP enviado a la cámara" : "No se pudo disparar por PTP"
                } label: {
                    Label("Disparar Cámara (PTP)", systemImage: "camera.shutter.button")
                }
                .buttonStyle(StudioButtonStyle(.approveEmerald, compact: true))
            }

            if bridgeMode == .classicGPhoto2 && gphoto.isAvailable {
                Button {
                    Task { await fireGPhoto2Shutter() }
                } label: {
                    Label("Disparar y Descargar RAW", systemImage: "bolt.fill")
                }
                .buttonStyle(StudioButtonStyle(.approveEmerald, compact: true))
            }

            if live.currentFrame != nil && (bridgeMode == .nativeUVC || bridgeMode == .networkMJPEG) {
                Button("Guardar Cuadro de Referencia") {
                    if let ref = live.captureReferenceJPEG() {
                        let profile = KnownDevice(id: "liveview", displayName: "Live View UVC", alias: "Vista en Vivo", category: .dslrMirrorless, allowJpgWhenNoRaw: true)
                        _ = viewModel.handleCapturedFileStaged(stagedURL: ref.url, originalFilename: ref.filename, deviceProfile: profile)
                        appState.homeViewModel.updateSessionCounts(viewModel.session)
                        captureFeedback = "Referencia guardada: \(ref.filename)"
                    }
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: AppSpacing.bottomControlBarHeight)
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle().frame(height: AppSpacing.hairline).foregroundStyle(AppColors.borderSubtle),
            alignment: .top
        )
    }

    private func toggleStream() async {
        captureFeedback = nil
        if isLiveActive {
            appState.stopAllLiveView()
            return
        }
        switch bridgeMode {
        case .nativeUVC:
            await live.start()
        case .networkMJPEG:
            network.startStream(
                url: network.streamURLString,
                onFrame: { frame in live.injectExternalPreviewFrame(frame) },
                onError: { err in captureFeedback = err }
            )
        case .classicGPhoto2:
            appState.discoveryService.pauseSessionsForExternalBridge()
            gphoto.startPreviewStream(
                onFrame: { frame in live.injectExternalPreviewFrame(frame) },
                onError: { err in
                    captureFeedback = err
                    appState.discoveryService.resumeSessionsAfterExternalBridge()
                }
            )
        }
    }

    private func fireGPhoto2Shutter() async {
        let wasStreaming = gphoto.isStreaming
        let urls = await gphoto.triggerCaptureAndDownload()
        let profile = KnownDevice(id: "gphoto2", displayName: "DSLR gphoto2", alias: "DSLR USB (gphoto2)", category: .dslrMirrorless, allowJpgWhenNoRaw: true)
        for u in urls {
            _ = viewModel.handleCapturedFileStaged(stagedURL: u, originalFilename: u.lastPathComponent, deviceProfile: profile)
        }
        appState.homeViewModel.updateSessionCounts(viewModel.session)
        captureFeedback = urls.isEmpty ? "No se descargaron archivos nuevos" : "Capturado(s) \(urls.count) archivo(s) → RAW/"
        if wasStreaming {
            gphoto.startPreviewStream(onFrame: { frame in live.injectExternalPreviewFrame(frame) }, onError: { captureFeedback = $0 })
        }
    }
}
