import SwiftUI

/// Persistent top studio bar displaying the live USB device pill and quick Settings trigger.
package struct TopDeviceStatusBar: View {
    let primaryDevice: ConnectedDeviceState?
    let leadingTitle: String
    let leadingSubtitle: String?
    let watchedFolderName: String?
    let onBackAction: (() -> Void)?
    let onTapWatchFolder: (() -> Void)?
    let onDetachWatchFolder: (() -> Void)?
    let onTapDevicePill: () -> Void
    let onTapSettings: () -> Void
    let onTapHelp: (() -> Void)?

    @State private var isShowingWatchPopover = false
    @State private var isDevicePillHovered = false

    package init(
        primaryDevice: ConnectedDeviceState?,
        leadingTitle: String,
        leadingSubtitle: String? = nil,
        watchedFolderName: String? = nil,
        onBackAction: (() -> Void)? = nil,
        onTapWatchFolder: (() -> Void)? = nil,
        onDetachWatchFolder: (() -> Void)? = nil,
        onTapDevicePill: @escaping () -> Void,
        onTapSettings: @escaping () -> Void,
        onTapHelp: (() -> Void)? = nil
    ) {
        self.primaryDevice = primaryDevice
        self.leadingTitle = leadingTitle
        self.leadingSubtitle = leadingSubtitle
        self.watchedFolderName = watchedFolderName
        self.onBackAction = onBackAction
        self.onTapWatchFolder = onTapWatchFolder
        self.onDetachWatchFolder = onDetachWatchFolder
        self.onTapDevicePill = onTapDevicePill
        self.onTapSettings = onTapSettings
        self.onTapHelp = onTapHelp
    }

    package var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let onBackAction {
                Button(action: onBackAction) {
                    Label("Sesiones", systemImage: "chevron.left")
                }
                .buttonStyle(StudioButtonStyle(.ghost, compact: true))
                .help("Volver a Sesiones de Fotografía")
            } else {
                PhotoPicBrandLogo(size: 24)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(leadingTitle)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if let leadingSubtitle {
                    Text(leadingSubtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let onTapWatchFolder {
                Button {
                    isShowingWatchPopover.toggle()
                } label: {
                    Label(
                        watchedFolderName.map { "Puente: \($0)" } ?? "Carpeta puente",
                        systemImage: watchedFolderName == nil ? "folder.badge.plus" : "folder.badge.gearshape"
                    )
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help("Importar fotos automáticamente desde una carpeta puente en tu Mac")
                .popover(isPresented: $isShowingWatchPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Carpeta puente automática")
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Importa al instante las fotos nuevas que caigan en cualquier carpeta de tu Mac (ideal si disparás con EOS Utility, Capture One, Lightroom o app Wi-Fi).")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let watchedFolderName {
                            Text("Carpeta actual: \(watchedFolderName)")
                                .font(AppTypography.monoMicro)
                                .foregroundStyle(AppColors.approveGreen)
                        }

                        HStack(spacing: AppSpacing.xs) {
                            Button("Seleccionar carpeta...") {
                                isShowingWatchPopover = false
                                onTapWatchFolder()
                            }
                            .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))

                            if watchedFolderName != nil, let onDetachWatchFolder {
                                Button("Desvincular") {
                                    isShowingWatchPopover = false
                                    onDetachWatchFolder()
                                }
                                .buttonStyle(StudioButtonStyle(.ghost, compact: true))
                            }
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(width: 310)
                    .background(AppColors.panelSurface)
                }
            }

            liveDevicePill

            if let onTapHelp {
                Button(action: onTapHelp) {
                    Image(systemName: "questionmark.circle")
                        .font(AppTypography.bodyMedium)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help("Centro de Ayuda de PhotoPic (⌘?)")
                .accessibilityLabel("Centro de Ayuda")
            }

            Button(action: onTapSettings) {
                Image(systemName: "gearshape")
                    .font(AppTypography.bodyMedium)
            }
            .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            .help("Configuración y Administrador de Dispositivos")
            .accessibilityLabel("Configuración y Dispositivos")
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: AppSpacing.topBarHeight)
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle()
                .frame(height: AppSpacing.hairline)
                .foregroundStyle(AppColors.borderSubtle),
            alignment: .bottom
        )
    }

    private var liveDevicePill: some View {
        Button(action: onTapDevicePill) {
            HStack(spacing: AppSpacing.sm) {
                PulsingStatusDot(color: pillStatusColor, isActive: isDeviceLive)

                Image(systemName: primaryDevice?.category.sfSymbolName ?? "cable.connector")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                Text(pillText)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if let battery = primaryDevice?.batteryLevel {
                    Text("\(battery)%")
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.leading, AppSpacing.xxs)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(isDevicePillHovered ? AppColors.controlHover : AppColors.elevatedSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isDevicePillHovered ? AppColors.borderStrong : pillBorderColor, lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { isDevicePillHovered = $0 }
        .help("Ver estado USB y configurar dispositivos conectados")
    }

    private var isDeviceLive: Bool {
        primaryDevice?.status.isLiveSessionOpen == true || primaryDevice?.status.isIndexingCatalog == true
    }

    private var pillStatusColor: Color {
        guard let status = primaryDevice?.status else { return AppColors.textTertiary }
        switch status {
        case .connectedReady: return AppColors.approveGreen
        case .indexingCatalog: return AppColors.infoBlue
        case .capturing, .connecting, .androidPermissionRequired: return AppColors.warningAmber
        case .busyByMacOS, .accessRestrictedLocked, .error: return AppColors.archiveRed
        case .waiting, .detectedNotConnected, .disconnected: return AppColors.textTertiary
        }
    }

    private var pillBorderColor: Color {
        guard let status = primaryDevice?.status else { return AppColors.borderSubtle }
        switch status {
        case .connectedReady: return AppColors.approveGreen.opacity(0.35)
        case .indexingCatalog: return AppColors.infoBlue.opacity(0.45)
        case .capturing, .androidPermissionRequired: return AppColors.warningAmber.opacity(0.4)
        case .busyByMacOS, .accessRestrictedLocked, .error: return AppColors.archiveRed.opacity(0.4)
        default: return AppColors.borderSubtle
        }
    }

    private var pillText: String {
        guard let device = primaryDevice else {
            return "Esperando dispositivo"
        }
        switch device.status {
        case .connectedReady:
            return device.alias
        case .indexingCatalog(let pct, let count):
            return count > 0 ? "\(device.alias) · Indexando SD \(pct)% (\(count))" : "\(device.alias) · Indexando SD \(pct)%"
        case .capturing(let count):
            return count > 1 ? "\(device.alias) · \(count) capturas" : "\(device.alias) · Capturando"
        case .connecting:
            return "\(device.alias) · Conectando..."
        case .busyByMacOS:
            return "\(device.alias) · Ocupado por macOS"
        case .accessRestrictedLocked:
            return "\(device.alias) · Desbloquear"
        case .androidPermissionRequired:
            return "\(device.alias) · Permitir en Android"
        case .detectedNotConnected:
            return "\(device.alias) · Sin vincular"
        case .disconnected:
            return "\(device.alias) · Desconectado"
        case .waiting:
            return "Esperando dispositivo"
        case .error:
            return "\(device.alias) · Error USB"
        }
    }
}
