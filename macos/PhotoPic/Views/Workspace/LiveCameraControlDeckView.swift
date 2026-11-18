import SwiftUI

package struct LiveCameraControlDeckView: View {
    package let snapshot: CameraControlSnapshot
    package let isLiveStreaming: Bool
    package let inlineNote: String?
    package let onSelectProperty: (CameraPropertyID, UInt32) -> Void
    package let onSelectFlashAccessory: (FlashAccessorySelection) -> Void
    package let onEngageOpticalHotShoeFlash: () -> Void
    package let onResumeLiveView: () -> Void
    package let onPopupBuiltinFlash: () -> Void
    package let onTriggerAutofocus: (Bool) -> Void
    package let onDriveManualFocus: (Bool, UInt32) -> Void
    package let onSetZoom: (UInt32) -> Void
    package let onToggleDOF: (Bool) -> Void
    package let onToggleKeepOriginals: (Bool) -> Void
    package let onOpenDemo: (() -> Void)?
    package let onCloseDemo: (() -> Void)?

    @State private var focusStepSize: UInt32 = 2

    package init(
        snapshot: CameraControlSnapshot,
        isLiveStreaming: Bool,
        inlineNote: String? = nil,
        onSelectProperty: @escaping (CameraPropertyID, UInt32) -> Void,
        onSelectFlashAccessory: @escaping (FlashAccessorySelection) -> Void,
        onEngageOpticalHotShoeFlash: @escaping () -> Void,
        onResumeLiveView: @escaping () -> Void,
        onPopupBuiltinFlash: @escaping () -> Void,
        onTriggerAutofocus: @escaping (Bool) -> Void,
        onDriveManualFocus: @escaping (Bool, UInt32) -> Void,
        onSetZoom: @escaping (UInt32) -> Void,
        onToggleDOF: @escaping (Bool) -> Void,
        onToggleKeepOriginals: @escaping (Bool) -> Void,
        onOpenDemo: (() -> Void)? = nil,
        onCloseDemo: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.isLiveStreaming = isLiveStreaming
        self.inlineNote = inlineNote
        self.onSelectProperty = onSelectProperty
        self.onSelectFlashAccessory = onSelectFlashAccessory
        self.onEngageOpticalHotShoeFlash = onEngageOpticalHotShoeFlash
        self.onResumeLiveView = onResumeLiveView
        self.onPopupBuiltinFlash = onPopupBuiltinFlash
        self.onTriggerAutofocus = onTriggerAutofocus
        self.onDriveManualFocus = onDriveManualFocus
        self.onSetZoom = onSetZoom
        self.onToggleDOF = onToggleDOF
        self.onToggleKeepOriginals = onToggleKeepOriginals
        self.onOpenDemo = onOpenDemo
        self.onCloseDemo = onCloseDemo
    }

    package var body: some View {
        VStack(spacing: 0) {
            telemetryHeader
            Divider().overlay(AppColors.borderSubtle)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if let inlineNote, !inlineNote.isEmpty {
                        calmInlineNotice(inlineNote)
                    }

                    if let capabilityNotice = snapshot.deviceCapabilityNotice, snapshot.controls.isEmpty {
                        deviceCapabilityCard(capabilityNotice)
                        storageSection
                    } else {
                        exposureSection
                        flashSection
                        if isLiveStreaming || snapshot.isDemoMode {
                            focusAndLiveViewSection
                        }
                        creativeControlsSection
                        storageSection
                    }
                }
                .padding(AppSpacing.md)
            }
        }
        .frame(width: 318)
        .background(AppColors.panelSurface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(width: 1)
        }
    }

    private func deviceCapabilityCard(_ notice: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.infoBlue)
                Text("Capacidades del Dispositivo")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPrimary)
            }

            Text(notice)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let onOpenDemo {
                Button {
                    onOpenDemo()
                } label: {
                    Label("Probar Demo Canon EOS 70D", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .padding(.top, 2)
            }
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.elevatedSurface)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.sm).stroke(AppColors.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    // MARK: - Telemetry Header

    private var telemetryHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(snapshot.isDemoMode ? AppColors.infoBlue : AppColors.approveGreen)
                Text(snapshot.deviceName)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if snapshot.isDemoMode {
                    Text("DEMO")
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(AppColors.infoBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.infoBlueTint)
                        .clipShape(Capsule())
                    if let onCloseDemo {
                        Button(action: onCloseDemo) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 20, height: 20)
                                .background(AppColors.elevatedSurface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Cerrar vista Demo de controles")
                    }
                }
            }

            HStack(spacing: 6) {
                if let aeLabel = snapshot.aeModeLabel {
                    telemetryPill(
                        icon: "dial.low",
                        text: aeLabel,
                        tint: AppColors.textPrimary,
                        helpText: "Modo del dial físico de la cámara (solo lectura)"
                    )
                }
                if let battery = snapshot.batteryPercentLabel {
                    telemetryPill(
                        icon: "battery.75percent",
                        text: battery,
                        tint: AppColors.textSecondary,
                        helpText: "Nivel de batería de la cámara"
                    )
                }
                if let shots = snapshot.availableShots {
                    telemetryPill(
                        icon: "photo.stack",
                        text: "\(shots)",
                        tint: AppColors.textSecondary,
                        helpText: "Disparos disponibles reportados por la cámara"
                    )
                }
            }

            if let lens = snapshot.lensName, !lens.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(lens)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    private func telemetryPill(icon: String, text: String, tint: Color, helpText: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(AppTypography.micro)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(AppColors.elevatedSurface)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.xs).stroke(AppColors.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
        .help(helpText)
    }

    private func calmInlineNotice(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.infoBlue)
                .padding(.top, 1)
            Text(note)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.infoBlueTint)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.sm).stroke(AppColors.infoBlue.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    // MARK: - Section 1: Exposición Principal (2x2)

    private var exposureSection: some View {
        let exposureControls = snapshot.orderedPrimaryExposureControls
        let lockedNotes = exposureControls.compactMap { ctrl -> String? in
            guard !ctrl.isWritable, let reason = ctrl.lockExplanation else { return nil }
            return "• \(ctrl.property.shortLabel): \(reason)"
        }

        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionHeading("Exposición Principal", badge: exposureControls.isEmpty ? "Leyendo..." : nil)

            if exposureControls.isEmpty {
                emptySectionCard("Esperando tabla de exposición de la cámara vía PTP...")
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppSpacing.xs),
                        GridItem(.flexible(), spacing: AppSpacing.xs)
                    ],
                    spacing: AppSpacing.xs
                ) {
                    ForEach(exposureControls) { control in
                        exposureTile(control)
                    }
                }

                if !lockedNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(lockedNotes, id: \.self) { note in
                            Text(note)
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(AppSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.elevatedSurface.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                }
            }
        }
    }

    private func exposureTile(_ control: CameraPropertyControl) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(control.property.shortLabel)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if !control.isWritable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if control.isWritable && !control.availableOptions.isEmpty {
                Menu {
                    ForEach(control.availableOptions) { option in
                        Button {
                            onSelectProperty(control.property, option.rawValue)
                        } label: {
                            if option.rawValue == control.currentValue {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(control.currentLabel)
                            .font(AppTypography.monoCounter)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(AppColors.panelSurface)
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.xs).stroke(AppColors.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                }
                .menuStyle(.borderlessButton)

                HStack(spacing: 4) {
                    stepperButton(symbol: "minus", enabled: control.canStepBackward) {
                        if let prev = control.adjacentOption(step: -1) {
                            onSelectProperty(control.property, prev.rawValue)
                        }
                    }
                    stepperButton(symbol: "plus", enabled: control.canStepForward) {
                        if let next = control.adjacentOption(step: 1) {
                            onSelectProperty(control.property, next.rawValue)
                        }
                    }
                }
            } else {
                Text(control.currentLabel)
                    .font(AppTypography.monoCounter)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(AppColors.panelSurface.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))

                Text("Controlado por dial")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppSpacing.xs)
        .background(AppColors.elevatedSurface)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.sm).stroke(AppColors.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    private func stepperButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? AppColors.textPrimary : AppColors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(AppColors.panelSurface)
                .overlay(RoundedRectangle(cornerRadius: AppRadius.xs).stroke(AppColors.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Section 2: Flash y Zapata Superior

    private var flashSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                sectionHeading("Flash y Zapata Superior", badge: nil)
                Spacer()
                flashStatusBadge
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: 4) {
                    ForEach(FlashAccessorySelection.allCases) { mode in
                        let selected = snapshot.flashAccessory == mode
                        Button {
                            onSelectFlashAccessory(mode)
                        } label: {
                            Text(shortFlashTabTitle(mode))
                                .font(AppTypography.micro)
                                .foregroundStyle(selected ? AppColors.textOnAccent : AppColors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(selected ? AppColors.primaryActionFill : AppColors.panelSurface)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                        }
                        .buttonStyle(.plain)
                    }
                }

                flashAccessoryGuidanceBox

                if let silentControl = snapshot.controls[.silentShutter], !silentControl.availableOptions.isEmpty {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "speaker.slash")
                                .font(.system(size: 10))
                                .foregroundStyle(snapshot.isSilentLVBlockingFlash ? AppColors.warningAmber : AppColors.textSecondary)
                            Text("Silencioso LV")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Menu {
                            ForEach(silentControl.availableOptions) { opt in
                                Button {
                                    onSelectProperty(.silentShutter, opt.rawValue)
                                } label: {
                                    if opt.rawValue == silentControl.currentValue {
                                        Label(opt.label, systemImage: "checkmark")
                                    } else {
                                        Text(opt.label)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(silentControl.currentValue == 0 ? "Desactivado (Sync OK)" : "Modo \(silentControl.currentValue) (Bloquea)")
                                    .font(AppTypography.micro)
                                    .foregroundStyle(snapshot.isSilentLVBlockingFlash ? AppColors.warningAmber : AppColors.approveGreen)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(AppColors.panelSurface)
                            .overlay(RoundedRectangle(cornerRadius: AppRadius.xs).stroke(AppColors.borderSubtle, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }
            .padding(AppSpacing.xs)
            .background(AppColors.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.sm).stroke(AppColors.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    @ViewBuilder
    private var flashStatusBadge: some View {
        if snapshot.flashAccessory == .disabled || snapshot.isFlashFiringDisabled {
            pillBadge("Apagado", color: AppColors.textTertiary, bg: AppColors.elevatedSurface)
        } else if snapshot.isAEModeBlockingFlash {
            pillBadge("Dial sin flash", color: AppColors.warningAmber, bg: AppColors.warningAmberTint)
        } else if snapshot.isSilentLVBlockingFlash {
            pillBadge("Bloqueado LV", color: AppColors.warningAmber, bg: AppColors.warningAmberTint)
        } else if snapshot.isMirrorDownOpticalFlashMode {
            pillBadge("Zapata Activa", color: AppColors.approveGreen, bg: AppColors.approveGreenTint)
        } else if snapshot.flashAccessory == .externalHotShoe {
            pillBadge("Zapata Segura", color: AppColors.approveGreen, bg: AppColors.approveGreenTint)
        } else {
            pillBadge("Interno", color: AppColors.infoBlue, bg: AppColors.infoBlueTint)
        }
    }

    @ViewBuilder
    private var flashAccessoryGuidanceBox: some View {
        switch snapshot.flashAccessory {
        case .externalHotShoe:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.approveGreen)
                    Text("Flash interno protegido (nunca se abrirá)")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPrimary)
                }

                Text("Si usás un flash externo manual (1 pin) en Canon 70D, bajá el espejo para que dispare directo por zapata sin desconectar el Mac.")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if snapshot.isSilentLVBlockingFlash {
                    Button("Desactivar Disparo Silencioso LV") {
                        onSelectProperty(.silentShutter, 0)
                    }
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                }

                if snapshot.isMirrorDownOpticalFlashMode {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.approveGreen)
                        Text("Espejo abajo · Listo para Flash Zapata")
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.approveGreen)
                        Spacer()
                    }
                    .padding(6)
                    .background(AppColors.approveGreenTint)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))

                    Button("Volver a Vista en Vivo") {
                        onResumeLiveView()
                    }
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                } else {
                    Button {
                        onEngageOpticalHotShoeFlash()
                    } label: {
                        Label("Modo Flash Zapata (Bajar Espejo)", systemImage: "bolt.horizontal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioButtonStyle(.approveEmerald, compact: true))
                }
            }
            .padding(AppSpacing.xs)
            .background(AppColors.panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))

        case .disabled:
            Text(snapshot.flashAccessory.statusSummary)
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(AppSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.panelSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))

        case .builtinPopup:
            VStack(alignment: .leading, spacing: 6) {
                Text("⚠️ Solo activalo si no hay absolutamente nada montado en la zapata superior.")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.warningAmber)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onPopupBuiltinFlash()
                } label: {
                    Label("Levantar Flash Interno", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            }
            .padding(AppSpacing.xs)
            .background(AppColors.warningAmberTint.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
        }
    }

    private func shortFlashTabTitle(_ mode: FlashAccessorySelection) -> String {
        switch mode {
        case .externalHotShoe: return "Zapata Externa"
        case .disabled: return "Sin Flash"
        case .builtinPopup: return "Interno"
        }
    }

    // MARK: - Section 3: Enfoque y Visor

    private var focusAndLiveViewSection: some View {
        let isLensInMF = snapshot.controls[.focusMode]?.currentValue == 3

        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionHeading("Enfoque y Visor", badge: "\(snapshot.liveViewZoom)x")

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: 6) {
                    Text("Zoom")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    ForEach([UInt32(1), 5, 10], id: \.self) { zoom in
                        let active = snapshot.liveViewZoom == zoom
                        Button("\(zoom)x") {
                            onSetZoom(zoom)
                        }
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(active ? AppColors.textOnAccent : AppColors.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(active ? AppColors.infoBlue : AppColors.panelSurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 6) {
                    Button {
                        onTriggerAutofocus(false)
                    } label: {
                        Label("Enfocar AF", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                    .disabled(isLensInMF)

                    Button {
                        onToggleDOF(!snapshot.isDOFPreviewActive)
                    } label: {
                        Text(snapshot.isDOFPreviewActive ? "DOF: Activo" : "DOF")
                    }
                    .buttonStyle(StudioButtonStyle(snapshot.isDOFPreviewActive ? .primaryLight : .secondaryDark, compact: true))
                }

                HStack(spacing: 6) {
                    Button {
                        onDriveManualFocus(true, focusStepSize)
                    } label: {
                        Label("Cerca", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                    .disabled(isLensInMF)

                    Menu {
                        Button("Paso 1 (Fino)") { focusStepSize = 1 }
                        Button("Paso 2 (Medio)") { focusStepSize = 2 }
                        Button("Paso 3 (Rápido)") { focusStepSize = 3 }
                    } label: {
                        Text("Paso \(focusStepSize)")
                            .font(AppTypography.monoMicro)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppColors.panelSurface)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                    }
                    .menuStyle(.borderlessButton)

                    Button {
                        onDriveManualFocus(false, focusStepSize)
                    } label: {
                        Label("Lejos", systemImage: "chevron.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                    .disabled(isLensInMF)
                }

                if isLensInMF {
                    Text("El interruptor del lente está en MF (manual). Cambialo a AF en el lente para mover el foco desde aquí.")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AppSpacing.xs)
            .background(AppColors.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.sm).stroke(AppColors.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Section 4: Ajustes Adaptativos

    private var creativeControlsSection: some View {
        let creative = snapshot.orderedCreativeControls
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionHeading("Ajustes de Cámara", badge: creative.isEmpty ? nil : "\(creative.count)")

            if creative.isEmpty {
                emptySectionCard("Sin ajustes adicionales reportados todavía.")
            } else {
                VStack(spacing: 6) {
                    ForEach(creative) { control in
                        creativeRow(control)
                    }
                }
            }
        }
    }

    private func creativeRow(_ control: CameraPropertyControl) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: control.property.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(control.isWritable ? AppColors.textSecondary : AppColors.textTertiary)
                    .frame(width: 14)

                Text(control.property.shortLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer(minLength: 4)

                if control.isWritable && !control.availableOptions.isEmpty {
                    Menu {
                        ForEach(control.availableOptions) { option in
                            Button {
                                onSelectProperty(control.property, option.rawValue)
                            } label: {
                                if option.rawValue == control.currentValue {
                                    Label(option.label, systemImage: "checkmark")
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(control.currentLabel)
                                .font(AppTypography.captionMedium)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.panelSurface)
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.xs).stroke(AppColors.borderStrong, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AppColors.textTertiary)
                        Text(control.currentLabel)
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.panelSurface.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                }
            }

            if !control.isWritable, let explanation = control.lockExplanation {
                Text(explanation)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 7)
        .background(AppColors.elevatedSurface)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.sm).stroke(AppColors.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    // MARK: - Section 5: Almacenamiento

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            sectionHeading("Almacenamiento en Captura", badge: nil)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { snapshot.keepOriginalsOnSD },
                    set: { onToggleKeepOriginals($0) }
                )) {
                    Text("Guardar copia en tarjeta SD de cámara")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPrimary)
                }
                .toggleStyle(.switch)

                Text(snapshot.keepOriginalsOnSD
                    ? "Destino activo: Mac + Tarjeta SD de la cámara."
                    : "Destino activo: Directo al Mac (máxima velocidad en ráfaga).")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.xs)
            .background(AppColors.elevatedSurface)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.sm).stroke(AppColors.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Helpers

    private func sectionHeading(_ title: String, badge: String?) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(AppTypography.monoMicro)
                .foregroundStyle(AppColors.textTertiary)
            if let badge {
                Text(badge)
                    .font(AppTypography.monoMicro)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
        }
    }

    private func pillBadge(_ text: String, color: Color, bg: Color) -> some View {
        Text(text)
            .font(AppTypography.monoMicro)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    private func emptySectionCard(_ message: String) -> some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xs)
            .background(AppColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }
}
