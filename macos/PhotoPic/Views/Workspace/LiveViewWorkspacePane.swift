import AppKit
import SwiftUI

/// Live View studio workspace tab supporting direct Canon/Nikon USB PTP Live View,
/// UVC / HDMI-USB (`AVFoundation`), Android IP Wi-Fi MJPEG, and optional `gphoto2`.
package struct LiveViewWorkspacePane: View {
    private enum BridgeMode: String, CaseIterable, Identifiable {
        case usbPTPDirect = "USB PTP"
        case nativeUVC = "UVC / HDMI"
        case networkMJPEG = "Wi-Fi IP"
        case classicGPhoto2 = "gphoto2"
        var id: String { rawValue }
    }

    private var visibleModes: [BridgeMode] {
        var modes: [BridgeMode] = [.usbPTPDirect, .nativeUVC, .networkMJPEG]
        if gphoto.isAvailable {
            modes.append(.classicGPhoto2)
        }
        return modes
    }

    @Bindable var appState: AppState
    @Bindable var viewModel: CullingSessionViewModel
    @State private var bridgeMode: BridgeMode = .usbPTPDirect
    @State private var captureFeedback: String?
    @State private var didAutoSelectMode = false
    @State private var showControlDeck = true
    @State private var demoSnapshot: CameraControlSnapshot? = .canon70DDemo()

    private var activeControlSnapshot: CameraControlSnapshot? {
        if let dev = primaryUSBDevice {
            if let liveSnap = directCanon.controlSnapshots[dev.fingerprint] {
                return liveSnap
            }
            if let demo = demoSnapshot {
                return demo
            }
            return CameraControlSnapshot.adaptiveFallback(
                for: dev,
                keepOriginalsOnSD: appState.knownDevicesStore.device(for: dev.fingerprint)?.keepOriginalsOnDevice ?? false
            )
        }
        return demoSnapshot
    }

    package init(appState: AppState, viewModel: CullingSessionViewModel) {
        self.appState = appState
        self.viewModel = viewModel
    }

    private var live: LiveViewCameraService { appState.liveViewService }
    private var ptpLive: PTPLiveViewService { appState.ptpLiveViewService }
    private var directCanon: DirectCanonUSBPTPService { appState.discoveryService.directCanonService }
    private var gphoto: GPhoto2LiveBridge { appState.gphotoBridge }
    private var network: NetworkMJPEGStreamService { appState.networkStreamService }
    private var primaryUSBDevice: ConnectedDeviceState? { appState.discoveryService.primaryLiveDevice }

    private var isLiveActive: Bool {
        switch bridgeMode {
        case .usbPTPDirect: return ptpLive.isStreaming || directCanon.isDirectLiveViewStreaming
        case .nativeUVC: return live.isRunning
        case .networkMJPEG: return network.isStreaming
        case .classicGPhoto2: return gphoto.isStreaming
        }
    }

    package var body: some View {
        VStack(spacing: 0) {
            liveToolbar
            HStack(spacing: 0) {
                ZStack {
                    AppColors.stageBackground
                    if let frame = live.currentFrame, isLiveActive {
                        liveFrameStage(frame)
                    } else {
                        LiveViewCompatibilityCard(
                            connectedDevice: primaryUSBDevice,
                            modeTitle: emptyModeTitle,
                            explanation: emptyExplanation,
                            feedbackMessage: captureFeedback ?? directCanon.inlineFeedbackNote ?? directCanon.directLiveViewStatusNote ?? ptpLive.statusNote ?? live.statusMessage ?? network.statusNote ?? gphoto.statusNote,
                            isActive: isLiveActive,
                            isOpticalHotShoeFlashMode: activeControlSnapshot?.isMirrorDownOpticalFlashMode == true && !isLiveActive,
                            onToggle: { Task { await toggleStream() } },
                            onActivateDemo: {
                                demoSnapshot = .canon70DDemo()
                                showControlDeck = true
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showControlDeck, let snapshot = activeControlSnapshot {
                    LiveCameraControlDeckView(
                        snapshot: snapshot,
                        isLiveStreaming: isLiveActive,
                        inlineNote: directCanon.inlineFeedbackNote ?? captureFeedback,
                        onSelectProperty: { prop, rawValue in
                            if snapshot.isDemoMode {
                                demoSnapshot?.applyDemoChange(property: prop, rawValue: rawValue)
                            } else if let dev = primaryUSBDevice {
                                Task {
                                    _ = await directCanon.setCameraProperty(for: dev.fingerprint, property: prop, rawValue: rawValue)
                                }
                            }
                        },
                        onSelectFlashAccessory: { accessory in
                            if snapshot.isDemoMode {
                                demoSnapshot?.flashAccessory = accessory
                                switch accessory {
                                case .externalHotShoe:
                                    demoSnapshot?.applyDemoChange(property: .silentShutter, rawValue: 0)
                                    demoSnapshot?.applyDemoChange(property: .stroboFiring, rawValue: 0)
                                    captureFeedback = "Demo: Flash Externo (Zapata) seguro activado. El pop-up interno nunca se levantará."
                                case .disabled:
                                    demoSnapshot?.applyDemoChange(property: .stroboFiring, rawValue: 1)
                                    captureFeedback = "Demo: Disparo de flash desactivado (0xD1DC = 1)."
                                case .builtinPopup:
                                    demoSnapshot?.applyDemoChange(property: .stroboFiring, rawValue: 0)
                                    captureFeedback = "Demo: Modo Flash Interno seleccionado (solo si la zapata está libre)."
                                }
                            } else if let dev = primaryUSBDevice {
                                Task {
                                    await directCanon.setFlashAccessory(for: dev.fingerprint, accessory: accessory)
                                }
                            }
                        },
                        onEngageOpticalHotShoeFlash: {
                            if snapshot.isDemoMode {
                                demoSnapshot?.applyDemoChange(property: .silentShutter, rawValue: 0)
                                demoSnapshot?.applyDemoChange(property: .stroboFiring, rawValue: 0)
                                demoSnapshot?.flashAccessory = .externalHotShoe
                                demoSnapshot?.isMirrorDownOpticalFlashMode = true
                                captureFeedback = "Demo: Espejo abajo · Flash de zapata sincronizado con conexión USB activa."
                            } else if let dev = primaryUSBDevice {
                                Task {
                                    await directCanon.engageOpticalHotShoeFlashMode(for: dev.fingerprint)
                                }
                            }
                        },
                        onResumeLiveView: {
                            if snapshot.isDemoMode {
                                demoSnapshot?.isMirrorDownOpticalFlashMode = false
                                captureFeedback = "Demo: Vista en Vivo reanudada."
                            } else {
                                Task { await toggleStream() }
                            }
                        },
                        onPopupBuiltinFlash: {
                            if snapshot.isDemoMode {
                                captureFeedback = "Demo: Comando 0x9131 (Flash Interno) probado en simulación."
                            } else if let dev = primaryUSBDevice {
                                Task {
                                    _ = await directCanon.popupBuiltinFlash(for: dev.fingerprint)
                                }
                            }
                        },
                        onTriggerAutofocus: { cancel in
                            if snapshot.isDemoMode {
                                captureFeedback = cancel ? "Demo: Enfoque AF cancelado." : "Demo: Enfoque AF ejecutado."
                            } else if let dev = primaryUSBDevice {
                                Task {
                                    _ = await directCanon.triggerAutofocus(for: dev.fingerprint, cancel: cancel)
                                }
                            }
                        },
                        onDriveManualFocus: { near, step in
                            if snapshot.isDemoMode {
                                captureFeedback = near ? "Demo: Foco movido más cerca (paso \(step))." : "Demo: Foco movido más lejos (paso \(step))."
                            } else if let dev = primaryUSBDevice {
                                Task {
                                    _ = await directCanon.driveManualFocus(for: dev.fingerprint, near: near, stepSize: step)
                                }
                            }
                        },
                        onSetZoom: { zoom in
                            if snapshot.isDemoMode {
                                demoSnapshot?.liveViewZoom = zoom
                            } else if let dev = primaryUSBDevice {
                                Task {
                                    _ = await directCanon.setLiveViewZoom(for: dev.fingerprint, zoomFactor: zoom)
                                }
                            }
                        },
                        onToggleDOF: { enabled in
                            if snapshot.isDemoMode {
                                demoSnapshot?.isDOFPreviewActive = enabled
                            } else if let dev = primaryUSBDevice {
                                Task {
                                    _ = await directCanon.setDOFPreview(for: dev.fingerprint, enabled: enabled)
                                }
                            }
                        },
                        onToggleKeepOriginals: { enabled in
                            if snapshot.isDemoMode {
                                demoSnapshot?.keepOriginalsOnSD = enabled
                            } else if let dev = primaryUSBDevice {
                                appState.discoveryService.setKeepOriginals(fingerprint: dev.fingerprint, enabled: enabled)
                            }
                        },
                        onOpenDemo: {
                            demoSnapshot = .canon70DDemo()
                            showControlDeck = true
                        },
                        onCloseDemo: snapshot.isDemoMode ? {
                            demoSnapshot = nil
                            captureFeedback = nil
                        } : nil
                    )
                }
            }
            .onChange(of: primaryUSBDevice?.fingerprint) { _, newFingerprint in
                if newFingerprint != nil {
                    demoSnapshot = nil
                }
            }
            .onChange(of: directCanon.controlSnapshots.isEmpty) { _, isEmpty in
                if !isEmpty {
                    demoSnapshot = nil
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            liveBottomBar
        }
        .background(AppColors.stageBackground)
        .onAppear {
            if primaryUSBDevice != nil {
                demoSnapshot = nil
            }
            live.refreshDevices()
            autoPickBestBridgeModeIfNeeded()
        }
        .onDisappear { appState.stopAllLiveView() }
    }

    private func autoPickBestBridgeModeIfNeeded() {
        guard !didAutoSelectMode else { return }
        didAutoSelectMode = true
        if let usb = primaryUSBDevice, usb.category == .dslrMirrorless,
           ptpLive.supportsDirectPTPLiveView(vendorID: usb.usbVendorID) {
            bridgeMode = .usbPTPDirect
        } else if live.availableDevices.contains(where: \.isExternal) {
            bridgeMode = .nativeUVC
        } else if primaryUSBDevice?.category == .androidPTP {
            bridgeMode = .networkMJPEG
        } else if primaryUSBDevice?.category == .dslrMirrorless {
            bridgeMode = .usbPTPDirect
        } else {
            bridgeMode = .nativeUVC
        }
    }

    private var liveToolbar: some View {
        HStack(spacing: AppSpacing.md) {
            HStack(spacing: 4) {
                ForEach(visibleModes) { mode in
                    let isSelected = bridgeMode == mode
                    Button {
                        if bridgeMode != mode {
                            bridgeMode = mode
                            appState.stopAllLiveView()
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(isSelected ? AppColors.textOnAccent : AppColors.textSecondary)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, 5)
                            .background(isSelected ? AppColors.primaryActionFill : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            .padding(3)
            .background(AppColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
            .layoutPriority(1)

            if bridgeMode == .usbPTPDirect {
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(primaryUSBDevice?.status.isLiveSessionOpen == true ? AppColors.approveGreen : AppColors.warningAmber)
                        .frame(width: 7, height: 7)
                    Text(usbTargetSummary)
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, 6)
                .background(AppColors.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            } else if bridgeMode == .nativeUVC {
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
                .frame(maxWidth: 220)

                Button {
                    live.refreshDevices()
                    gphoto.refreshAvailability()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help("Actualizar cámaras UVC/Continuity/HDMI")
            } else if bridgeMode == .networkMJPEG {
                TextField("http://192.168.1.50:8080/video", text: Binding(
                    get: { network.streamURLString },
                    set: { network.streamURLString = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.monoCaption)
                .frame(width: 215)
            }

            Spacer(minLength: AppSpacing.sm)

            HStack(spacing: AppSpacing.sm) {
                Toggle("3×3", isOn: Binding(get: { live.showThirdsGrid }, set: { live.showThirdsGrid = $0 }))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .fixedSize()

                Toggle("Espejo", isOn: Binding(get: { live.mirrorHorizontally }, set: { live.mirrorHorizontally = $0 }))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .fixedSize()

                Picker("Guía", selection: Binding(get: { live.aspectGuide }, set: { live.aspectGuide = $0 })) {
                    ForEach(LiveAspectGuide.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .labelsHidden()
                .frame(width: 124)

                if activeControlSnapshot != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showControlDeck.toggle()
                        }
                    } label: {
                        Label("Controles", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(StudioButtonStyle(showControlDeck ? .primaryLight : .secondaryDark, compact: true))
                    .fixedSize()
                    .help("Mostrar u ocultar el panel completo de controles de cámara")
                } else if primaryUSBDevice == nil {
                    Button {
                        demoSnapshot = .canon70DDemo()
                        showControlDeck = true
                    } label: {
                        Label("Demo Controles", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                    .fixedSize()
                    .help("Abrir vista interactiva de controles Canon EOS 70D sin cámara conectada")
                }

                Button(isLiveActive ? "Detener Vivo" : "Iniciar Vista en Vivo") {
                    Task { await toggleStream() }
                }
                .buttonStyle(StudioButtonStyle(isLiveActive ? .archiveCoral : .primaryLight, compact: true))
                .fixedSize()
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle().frame(height: AppSpacing.hairline).foregroundStyle(AppColors.borderSubtle),
            alignment: .bottom
        )
    }

    private var usbTargetSummary: String {
        guard let dev = primaryUSBDevice else {
            return "Sin cámara USB detectada"
        }
        if case .indexingCatalog(let pct, _) = dev.status {
            return "\(dev.alias) (Indexando SD \(pct)%)"
        }
        return "\(dev.alias) (Visor PTP USB)"
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
        case .usbPTPDirect:
            if let dev = primaryUSBDevice {
                return "Vista en Vivo USB PTP Directo — \(dev.alias)"
            }
            return "Vista en Vivo Cámara DSLR / Mirrorless por USB PTP"
        case .nativeUVC: return "Vista en Vivo UVC / Continuidad iOS / HDMI-USB"
        case .networkMJPEG: return "Vista en Vivo Android / Cámara IP Wi-Fi (MJPEG)"
        case .classicGPhoto2: return "Vista en Vivo DSLR vía gphoto2 CLI"
        }
    }

    private var emptyExplanation: String {
        switch bridgeMode {
        case .usbPTPDirect:
            if let dev = primaryUSBDevice {
                if case .indexingCatalog(let pct, let count) = dev.status {
                    return "Tu \(dev.alias) está sincronizando el índice de su tarjeta SD (\(pct)% · \(count) archivos). En cuanto llegue al 100% podrás iniciar el visor en vivo y disparar directo a RAW/ sin programas externos."
                }
                if ptpLive.supportsDirectPTPLiveView(vendorID: dev.usbVendorID) {
                    return "\(dev.alias) lista por cable USB. Pulsá 'Iniciar Vista en Vivo' para levantar el espejo y ver el encuadre en tiempo real mientras seguís disparando en RAW + JPG."
                }
                return "\(dev.alias) está conectada por PTP, pero su fabricante requiere modo 'USB Streaming (UVC)' en la pestaña UVC/HDMI o capturadora HDMI→USB."
            }
            return "Conectá tu cámara Canon EOS o Nikon por cable USB para transmitir el visor óptico/electrónico directo sin instalar drivers ni utilidades externas."
        case .nativeUVC:
            return "Detecta automáticamente iPhone Continuidad, cámaras con USB Streaming UVC, Android Webcam USB y capturadoras HDMI→USB."
        case .networkMJPEG:
            return "Abrí IP Webcam (:8080/video) o DroidCam (:4747/video) en tu Android por Wi-Fi local mientras el cable USB transfiere fotos PTP a RAW/."
        case .classicGPhoto2:
            if gphoto.isAvailable {
                return "gphoto2 detectado (\(gphoto.executablePath ?? "")). Útil para cuerpos antiguos fuera de Canon/Nikon PTP nativo."
            }
            return "Modo alternativo opcional para otras marcas vía Homebrew (brew install gphoto2). Para Canon/Nikon usá la pestaña 'Cámara USB (PTP)'."
        }
    }

    private var liveBottomBar: some View {
        HStack(spacing: AppSpacing.md) {
            let statusLabel: String = if let feedback = directCanon.inlineFeedbackNote ?? captureFeedback {
                feedback
            } else {
                switch bridgeMode {
                case .usbPTPDirect:
                    if activeControlSnapshot?.isMirrorDownOpticalFlashMode == true {
                        "Espejo abajo · Flash de Zapata listo · USB conectado"
                    } else if directCanon.isDirectLiveViewStreaming {
                        "Visor USB · ~\(max(1, directCanon.directLiveViewFPS)) fps · Zapata Segura"
                    } else if ptpLive.isStreaming {
                        "Visor PTP USB activo · ~\(max(1, ptpLive.fpsEstimate)) fps"
                    } else if let dev = primaryUSBDevice {
                        "\(dev.alias) · \(dev.status.label)"
                    } else {
                        "Esperando cámara Canon / Nikon USB"
                    }
                case .nativeUVC: "\(live.availableDevices.count) fuente(s) UVC / Continuidad / HDMI"
                case .networkMJPEG: network.statusNote ?? "Stream IP Wi-Fi simultáneo al cable PTP"
                case .classicGPhoto2: gphoto.isAvailable ? "gphoto2 listo" : "gphoto2 no instalado (usá USB PTP)"
                }
            }
            Text(statusLabel)
                .font(AppTypography.monoCaption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: AppSpacing.sm)

            if directCanon.isDirectLiveViewStreaming || ptpLive.isStreaming || appState.discoveryService.canTriggerPrimaryShutter {
                Button {
                    Task { await firePTPRemoteShutter() }
                } label: {
                    Label("Disparar Cámara (PTP)", systemImage: "camera.shutter.button")
                }
                .buttonStyle(StudioButtonStyle(.approveEmerald, compact: true))
                .fixedSize()
            }

            if bridgeMode == .classicGPhoto2 && gphoto.isAvailable {
                Button {
                    Task { await fireGPhoto2Shutter() }
                } label: {
                    Label("Disparar y Descargar RAW", systemImage: "bolt.fill")
                }
                .buttonStyle(StudioButtonStyle(.approveEmerald, compact: true))
            }

            if live.currentFrame != nil && isLiveActive {
                Button("Guardar Cuadro de Referencia") {
                    if let ref = live.captureReferenceJPEG() {
                        let profile = KnownDevice(id: "liveview", displayName: "Live View", alias: "Vista en Vivo", category: .dslrMirrorless, allowJpgWhenNoRaw: true)
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
        case .usbPTPDirect:
            guard let dev = primaryUSBDevice else {
                captureFeedback = "No hay ninguna cámara USB conectada."
                return
            }
            if directCanon.hasSession(for: dev.fingerprint) {
                directCanon.startLiveView(
                    for: dev.fingerprint,
                    onFrame: { frame in live.injectExternalPreviewFrame(frame) },
                    onError: { err in captureFeedback = err }
                )
                return
            }
            if case .indexingCatalog(let pct, _) = dev.status {
                captureFeedback = "Esperá a que termine el índice SD (\(pct)%) para abrir el visor PTP en vivo."
                return
            }
            guard let icCam = appState.discoveryService.activePrimaryICCamera else {
                appState.discoveryService.connectDevice(fingerprint: dev.fingerprint)
                captureFeedback = "Abriendo sesión PTP con \(dev.alias)... volvé a pulsar en unos segundos."
                return
            }
            ptpLive.startStream(
                camera: icCam,
                deviceState: dev,
                onFrame: { frame in live.injectExternalPreviewFrame(frame) },
                onError: { err in captureFeedback = err }
            )

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

    private func firePTPRemoteShutter() async {
        if let dev = primaryUSBDevice, directCanon.hasSession(for: dev.fingerprint) {
            let ok = await directCanon.triggerRemoteShutter(for: dev.fingerprint)
            captureFeedback = ok ? "Disparo enviado por USB directo — recibiendo foto..." : "La cámara no pudo disparar (revisá enfoque AF/MF)."
        } else if ptpLive.isStreaming {
            let ok = await ptpLive.triggerRemoteShutter()
            captureFeedback = ok ? "Disparo enviado a la cámara — recibiendo RAW/JPG..." : "La cámara no pudo disparar (revisá foco AF/MF)."
        } else {
            let ok = appState.discoveryService.triggerPrimaryRemoteShutter()
            captureFeedback = ok ? "Disparo PTP enviado a la cámara" : "No se pudo disparar por PTP"
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
