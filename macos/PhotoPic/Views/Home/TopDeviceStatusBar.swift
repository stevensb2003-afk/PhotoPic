import SwiftUI

/// Persistent top studio bar displaying the live USB device pill and quick Settings trigger.
package struct TopDeviceStatusBar: View {
    let primaryDevice: ConnectedDeviceState?
    let leadingTitle: String
    let leadingSubtitle: String?
    let onBackAction: (() -> Void)?
    let onTapDevicePill: () -> Void
    let onTapSettings: () -> Void

    package init(
        primaryDevice: ConnectedDeviceState?,
        leadingTitle: String,
        leadingSubtitle: String? = nil,
        onBackAction: (() -> Void)? = nil,
        onTapDevicePill: @escaping () -> Void,
        onTapSettings: @escaping () -> Void
    ) {
        self.primaryDevice = primaryDevice
        self.leadingTitle = leadingTitle
        self.leadingSubtitle = leadingSubtitle
        self.onBackAction = onBackAction
        self.onTapDevicePill = onTapDevicePill
        self.onTapSettings = onTapSettings
    }

    package var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let onBackAction {
                Button(action: onBackAction) {
                    Label("Sesiones", systemImage: "chevron.left")
                }
                .buttonStyle(StudioButtonStyle(.ghost, compact: true))
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

            liveDevicePill

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
            .background(AppColors.elevatedSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(pillBorderColor, lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .help("Abrir Administrador de Dispositivos")
    }

    private var isDeviceLive: Bool {
        primaryDevice?.status.isLiveSessionOpen == true
    }

    private var pillStatusColor: Color {
        guard let status = primaryDevice?.status else { return AppColors.textTertiary }
        switch status {
        case .connectedReady: return AppColors.approveGreen
        case .capturing, .connecting: return AppColors.warningAmber
        case .busyByMacOS, .accessRestrictedLocked, .error: return AppColors.archiveRed
        case .waiting, .detectedNotConnected, .disconnected: return AppColors.textTertiary
        }
    }

    private var pillBorderColor: Color {
        guard let status = primaryDevice?.status else { return AppColors.borderSubtle }
        switch status {
        case .connectedReady: return AppColors.approveGreen.opacity(0.35)
        case .capturing: return AppColors.warningAmber.opacity(0.4)
        case .busyByMacOS, .accessRestrictedLocked, .error: return AppColors.archiveRed.opacity(0.4)
        default: return AppColors.borderSubtle
        }
    }

    private var pillText: String {
        guard let device = primaryDevice else {
            return "Esperando cámara o celular USB..."
        }
        switch device.status {
        case .connectedReady:
            return device.alias
        case .capturing(let count):
            return count > 1 ? "\(device.alias) · \(count) capturas" : "\(device.alias) · Capturando"
        case .connecting:
            return "\(device.alias) · Conectando..."
        case .busyByMacOS:
            return "\(device.alias) · Ocupado por macOS"
        case .accessRestrictedLocked:
            return "\(device.alias) · Desbloquear"
        case .detectedNotConnected:
            return "\(device.alias) · Sin vincular"
        case .disconnected:
            return "\(device.alias) · Desconectado"
        case .waiting:
            return "Esperando cámara o celular USB..."
        case .error:
            return "\(device.alias) · Error USB"
        }
    }
}
