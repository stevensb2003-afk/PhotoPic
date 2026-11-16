import AppKit
import SwiftUI

/// Live View studio workspace tab supporting UVC / HDMI-USB (`AVFoundation`)
/// and optional classic DSLR USB streaming (`gphoto2`) with framing guides & shutter.
package struct LiveViewWorkspacePane: View {
    private enum BridgeMode: String, CaseIterable, Identifiable {
        case nativeUVC = "UVC / HDMI-USB"
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
    private var isLiveActive: Bool {
        bridgeMode == .nativeUVC ? live.isRunning : gphoto.isStreaming
    }

    package var body: some View {
        VStack(spacing: 0) {
            liveToolbar
            ZStack {
                AppColors.stageBackground
                if let frame = live.currentFrame, isLiveActive {
                    liveFrameStage(frame)
                } else {
                    liveEmptyStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            liveBottomBar
        }
        .background(AppColors.stageBackground)
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
            .frame(maxWidth: 255)
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
                .frame(maxWidth: 260)

                Button {
                    live.refreshDevices()
                    gphoto.refreshAvailability()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help("Actualizar cámaras UVC/HDMI y gphoto2")
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
                    thirdsGridOverlay
                }
                if let targetRatio = live.aspectGuide.aspectRatio {
                    aspectMaskOverlay(containerSize: geo.size, targetRatio: targetRatio)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(AppSpacing.md)
    }

    private var thirdsGridOverlay: some View {
        GeometryReader { g in
            Path { path in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3.0
                    let y = g.size.height * CGFloat(i) / 3.0
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: g.size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }
            .stroke(AppColors.borderStrong, lineWidth: AppSpacing.hairline)
        }
        .allowsHitTesting(false)
    }

    private func aspectMaskOverlay(containerSize: CGSize, targetRatio: CGFloat) -> some View {
        let currentRatio = containerSize.width / max(1, containerSize.height)
        let boxW = currentRatio > targetRatio ? containerSize.height * targetRatio : containerSize.width * 0.92
        let boxH = boxW / targetRatio
        return RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
            .stroke(AppColors.warningAmber, lineWidth: 1.5)
            .frame(width: boxW, height: boxH)
            .allowsHitTesting(false)
    }

    private var liveEmptyStage: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "video.viewfinder")
                .font(AppTypography.displayTitle)
                .foregroundStyle(AppColors.textTertiary)

            Text(bridgeMode == .nativeUVC ? "Vista en Vivo UVC / Capturadora HDMI-USB" : "Vista en Vivo DSLR Clásica vía gphoto2 USB")
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text(emptyExplanation)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            if let msg = captureFeedback ?? live.statusMessage ?? gphoto.statusNote {
                Text(msg)
                    .font(AppTypography.monoCaption)
                    .foregroundStyle(AppColors.warningAmber)
            }

            Button(isLiveActive ? "Detener" : "Iniciar Vista en Vivo") {
                Task { await toggleStream() }
            }
            .buttonStyle(StudioButtonStyle(.primaryLight))
        }
        .padding(AppSpacing.xxl)
    }

    private var emptyExplanation: String {
        if bridgeMode == .nativeUVC {
            return "Ideal para cámaras modernas con USB Streaming (UVC) o DSLRs clásicas conectadas con capturadora HDMI→USB-C. No interfiere con el tethering de tus RAWs."
        }
        if gphoto.isAvailable {
            return "gphoto2 detectado (\(gphoto.executablePath ?? "")). Al iniciar, PhotoPic pausa ImageCaptureCore temporalmente para transmitir el visor por USB y disparar directo a RAW/."
        }
        return "gphoto2 no está instalado en este Mac. Para usarlo con DSLRs clásicas (ej. Canon EOS 70D) por un único cable USB ejecutá: brew install gphoto2"
    }

    private var liveBottomBar: some View {
        HStack(spacing: AppSpacing.md) {
            let statusLabel = bridgeMode == .nativeUVC
                ? "\(live.availableDevices.count) fuente(s) UVC/HDMI detectada(s)"
                : (gphoto.isAvailable ? "gphoto2 listo" : "Modo DSLR USB requiere brew install gphoto2")
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

            if live.currentFrame != nil && bridgeMode == .nativeUVC {
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
        if bridgeMode == .nativeUVC {
            await live.start()
        } else {
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
