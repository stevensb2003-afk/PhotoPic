import SwiftUI

/// Profile configuration card for a remembered camera or smartphone.
package struct SavedDeviceRowView: View {
    let device: KnownDevice
    let liveState: ConnectedDeviceState?
    @Binding var aliasDraft: String
    let onCommitAlias: () -> Void
    let onToggleAutoConnect: @MainActor (Bool) -> Void
    let onToggleKeepOriginals: @MainActor (Bool) -> Void
    let onToggleAllowJpg: @MainActor (Bool) -> Void
    let onReleaseMacOSLock: () -> Void
    let onRetryConnection: () -> Void
    let onForget: () -> Void

    package init(
        device: KnownDevice,
        liveState: ConnectedDeviceState?,
        aliasDraft: Binding<String>,
        onCommitAlias: @escaping () -> Void,
        onToggleAutoConnect: @escaping @MainActor (Bool) -> Void,
        onToggleKeepOriginals: @escaping @MainActor (Bool) -> Void,
        onToggleAllowJpg: @escaping @MainActor (Bool) -> Void,
        onReleaseMacOSLock: @escaping () -> Void,
        onRetryConnection: @escaping () -> Void = {},
        onForget: @escaping () -> Void
    ) {
        self.device = device
        self.liveState = liveState
        self._aliasDraft = aliasDraft
        self.onCommitAlias = onCommitAlias
        self.onToggleAutoConnect = onToggleAutoConnect
        self.onToggleKeepOriginals = onToggleKeepOriginals
        self.onToggleAllowJpg = onToggleAllowJpg
        self.onReleaseMacOSLock = onReleaseMacOSLock
        self.onRetryConnection = onRetryConnection
        self.onForget = onForget
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            headerRow

            Divider()
                .overlay(AppColors.borderSubtle)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Toggle(
                    "Auto-conectar al detectar por USB",
                    isOn: Binding(get: { device.autoConnectOnPlug }, set: { onToggleAutoConnect($0) })
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Abrir conexión automáticamente al conectar el cable USB")

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(
                        "Mantener originales en la memoria/SD del dispositivo",
                        isOn: Binding(get: { device.keepOriginalsOnDevice }, set: { onToggleKeepOriginals($0) })
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("En cámaras compatibles (Canon 0xD11C / PTP), conserva o borra el original en la tarjeta tras descargar al Mac")

                    Text(device.keepOriginalsOnDevice
                        ? "Activo: cada foto queda respaldada en la memoria/SD de tu dispositivo y además se descarga al Mac."
                        : "Desactivado: descarga directo al Mac sin conservar copia en la cámara (en equipos compatibles).")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 28)
                }

                Toggle(
                    "Permitir filtrar JPG/HEIC cuando no dispare en RAW/DNG",
                    isOn: Binding(get: { device.allowJpgWhenNoRaw }, set: { onToggleAllowJpg($0) })
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Permite que fotos comprimidas de teléfonos o cámaras en solo JPG aparezcan en la cola de Filtrar")
            }
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)

            if liveState?.status == .busyByMacOS {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warningAmber)
                    Text("macOS (Fotos / PTPCamera) tiene bloqueada la cámara.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Button("Liberar macOS", action: onReleaseMacOSLock)
                        .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                }
                .padding(AppSpacing.sm)
                .background(AppColors.warningAmberTint)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            } else if liveState?.status == .androidPermissionRequired {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "iphone.and.arrow.right.inward")
                        .foregroundStyle(AppColors.warningAmber)
                    Text("En tu Android cambiá 'Solo carga' a 'Transferir imágenes (PTP)' y tocá 'Permitir'.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Button("Reintentar", action: onRetryConnection)
                        .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                }
                .padding(AppSpacing.sm)
                .background(AppColors.warningAmberTint)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            } else if case .error = liveState?.status {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.archiveRed)
                    Text("No se pudo completar el enlace PTP.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Button("Liberar macOS", action: onReleaseMacOSLock)
                        .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                    Button("Reintentar", action: onRetryConnection)
                        .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                }
                .padding(AppSpacing.sm)
                .background(AppColors.archiveRed.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            }

            HStack {
                Text(device.category.displayTitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Button("Olvidar dispositivo", role: .destructive, action: onForget)
                    .buttonStyle(StudioButtonStyle(.ghost, compact: true))
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }

    private var headerRow: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: device.category.sfSymbolName)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .background(AppColors.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                TextField("Alias del dispositivo", text: $aliasDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.bodyMedium)
                    .onSubmit(onCommitAlias)

                HStack(spacing: AppSpacing.xs) {
                    PulsingStatusDot(
                        color: statusColor,
                        isActive: liveState?.status.isLiveSessionOpen == true || liveState?.status.isIndexingCatalog == true
                    )
                    Text(effectiveStatus.label)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            if aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines) != device.alias {
                Button("Guardar", action: onCommitAlias)
                    .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
            }
        }
    }

    private var effectiveStatus: DeviceConnectionStatus {
        liveState?.status ?? .disconnected(lastSeen: device.lastConnectedAt)
    }

    private var statusColor: Color {
        switch effectiveStatus {
        case .connectedReady: return AppColors.approveGreen
        case .indexingCatalog: return AppColors.infoBlue
        case .capturing, .connecting, .androidPermissionRequired: return AppColors.warningAmber
        case .busyByMacOS, .accessRestrictedLocked, .error: return AppColors.archiveRed
        default: return AppColors.textTertiary
        }
    }
}
