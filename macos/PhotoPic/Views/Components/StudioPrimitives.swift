import SwiftUI

/// Consistent tactile button styles following Apple & Emil Kowalski press feedback rules.
package struct StudioButtonStyle: ButtonStyle {
    package enum Variant {
        case primaryLight
        case secondaryDark
        case approveEmerald
        case archiveCoral
        case ghost
    }

    let variant: Variant
    let compact: Bool

    package init(_ variant: Variant = .secondaryDark, compact: Bool = false) {
        self.variant = variant
        self.compact = compact
    }

    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? AppTypography.captionMedium : AppTypography.bodyMedium)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, compact ? AppSpacing.md : AppSpacing.lg)
            .padding(.vertical, compact ? AppSpacing.xs : AppSpacing.sm)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(borderColor, lineWidth: AppSpacing.hairline)
            )
            .scaleEffect(configuration.isPressed ? AppMotion.pressScale : 1.0)
            .animation(AppMotion.buttonPress, value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primaryLight: return AppColors.textOnAccent
        case .secondaryDark, .ghost: return AppColors.textPrimary
        case .approveEmerald: return AppColors.approveGreen
        case .archiveCoral: return AppColors.archiveRed
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primaryLight:
            return isPressed ? AppColors.primaryActionHover.opacity(0.88) : AppColors.primaryActionFill
        case .secondaryDark:
            return isPressed ? AppColors.controlHover : AppColors.secondaryButtonFill
        case .approveEmerald:
            return AppColors.approveGreenTint.opacity(isPressed ? 1.4 : 1.0)
        case .archiveCoral:
            return AppColors.archiveRedTint.opacity(isPressed ? 1.4 : 1.0)
        case .ghost:
            return isPressed ? AppColors.elevatedSurface : .clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primaryLight: return .clear
        case .secondaryDark: return AppColors.borderSubtle
        case .approveEmerald: return AppColors.approveGreen.opacity(0.35)
        case .archiveCoral: return AppColors.archiveRed.opacity(0.35)
        case .ghost: return AppColors.borderSubtle
        }
    }
}

/// Live indicator dot supporting gentle studio pulse without jarring animation.
package struct PulsingStatusDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let isActive: Bool
    @State private var pulseExpanded = false

    package init(color: Color, isActive: Bool) {
        self.color = color
        self.isActive = isActive
    }

    package var body: some View {
        ZStack {
            if isActive && !reduceMotion {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulseExpanded ? 1.15 : 0.72)
                    .opacity(pulseExpanded ? 0.1 : 0.65)
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            guard isActive && !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulseExpanded = true
            }
        }
    }
}

/// Crisp keyboard shortcut cap badge for studio action labels.
package struct KeycapBadge: View {
    let symbol: String

    package init(_ symbol: String) {
        self.symbol = symbol
    }

    package var body: some View {
        Text(symbol)
            .font(AppTypography.monoMicro)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 2)
            .background(AppColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .stroke(AppColors.borderStrong, lineWidth: AppSpacing.hairline)
            )
    }
}

/// Top non-blocking banner shown when a previously unseen USB camera or phone plugs in.
package struct UnknownDeviceTopBanner: View {
    let device: ConnectedDeviceState
    let onConnectAndSave: () -> Void
    let onDismiss: () -> Void

    package init(
        device: ConnectedDeviceState,
        onConnectAndSave: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.device = device
        self.onConnectAndSave = onConnectAndSave
        self.onDismiss = onDismiss
    }

    package var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: device.category.sfSymbolName)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(device.category == .androidPTP ? AppColors.warningAmber : AppColors.infoBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.category == .androidPTP
                    ? "Android detectado (\(device.deviceName)) — Requiere permiso USB"
                    : "Nuevo dispositivo detectado: \(device.deviceName)")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Text(device.category == .androidPTP
                    ? "En tu teléfono cambiá 'Solo carga' → 'Transferir imágenes (PTP)' y tocá 'Permitir acceso'."
                    : device.category.displayTitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button(device.category == .androidPTP ? "Verificar permiso y Conectar" : "Conectar y Guardar", action: onConnectAndSave)
                .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(AppSpacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Descartar aviso")
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle()
                .frame(height: AppSpacing.hairline)
                .foregroundStyle(AppColors.borderStrong),
            alignment: .bottom
        )
    }
}

/// Amber alert banner shown when `IOKit` detects a USB phone/camera hidden from `ImageCaptureCore`
/// (e.g. Android in Charging-only/MTP, locked iPhone, or Canon with Wi-Fi enabled).
package struct UnmountedUSBTopBanner: View {
    let device: PhysicalUSBDevice
    let onOpenValidator: () -> Void

    package init(device: PhysicalUSBDevice, onOpenValidator: @escaping () -> Void) {
        self.device = device
        self.onOpenValidator = onOpenValidator
    }

    package var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: device.category.sfSymbolName)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.warningAmber)

            VStack(alignment: .leading, spacing: 2) {
                Text("Detectado por USB: \(device.displayName) — Modo USB incompatible o bloqueado")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Cambiá de 'Solo carga' / 'Mass Storage' a PTP o desbloqueá tu teléfono para habilitar la captura.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button("Abrir Guía y Validar", action: onOpenValidator)
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.warningAmberTint)
        .overlay(
            Rectangle()
                .frame(height: AppSpacing.hairline)
                .foregroundStyle(AppColors.warningAmber.opacity(0.45)),
            alignment: .bottom
        )
    }
}

/// Non-intrusive top-center toast notification (e.g. auto-connected saved device).
package struct FloatingToastBanner: View {
    let message: String
    let iconName: String
    let tint: Color

    package init(message: String, iconName: String = "checkmark.circle.fill", tint: Color = AppColors.approveGreen) {
        self.message = message
        self.iconName = iconName
        self.tint = tint
    }

    package var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
            Text(message)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.elevatedSurface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AppColors.borderStrong, lineWidth: AppSpacing.hairline)
        )
    }
}
