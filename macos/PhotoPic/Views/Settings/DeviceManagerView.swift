import SwiftUI

/// Settings Tab 1: Plug & Play USB device manager (live USB list + saved profiles + Android/iOS note).
package struct DeviceManagerView: View {
    @Bindable var viewModel: DeviceManagerViewModel

    package init(viewModel: DeviceManagerViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                liveUsbSection
                savedDevicesSection
                mobileHelpNotice
            }
            .padding(AppSpacing.xl)
        }
    }

    private var liveUsbSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Conectados ahora mismo por USB")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text("\(viewModel.connectedDevices.count) activos")
                    .font(AppTypography.monoCaption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            if viewModel.connectedDevices.isEmpty {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "cable.connector.slash")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ningún dispositivo conectado en este momento")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Conectá una cámara DSLR/Mirrorless, un iPhone o un Android en modo PTP por USB.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.panelSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
                )
            } else {
                ForEach(viewModel.connectedDevices) { device in
                    liveUsbRow(device)
                }
            }
        }
    }

    private func liveUsbRow(_ device: ConnectedDeviceState) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: device.category.sfSymbolName)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(device.status.isLiveSessionOpen ? AppColors.approveGreen : AppColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(AppColors.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(device.alias)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    if let battery = device.batteryLevel {
                        Text("· \(battery)%")
                            .font(AppTypography.monoMicro)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                Text("\(device.category.displayTitle) — \(device.status.label)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            if device.status == .busyByMacOS {
                Button("Liberar macOS") {
                    viewModel.releaseMacOSLock(for: device.fingerprint)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            } else if device.status == .androidPermissionRequired {
                Button(device.isKnownDevice ? "Reintentar PTP" : "Verificar y Guardar") {
                    if device.isKnownDevice {
                        viewModel.connect(fingerprint: device.fingerprint)
                    } else {
                        viewModel.connectAndSave(fingerprint: device.fingerprint)
                    }
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            } else if device.status.isLiveSessionOpen {
                Button("Desconectar") {
                    viewModel.disconnect(fingerprint: device.fingerprint)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            } else if !device.isKnownDevice {
                Button("Conectar y Guardar") {
                    viewModel.connectAndSave(fingerprint: device.fingerprint)
                }
                .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
            } else {
                Button("Conectar") {
                    viewModel.connect(fingerprint: device.fingerprint)
                }
                .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }

    private var savedDevicesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Mis Dispositivos Guardados")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text("\(viewModel.savedDevices.count) guardados")
                    .font(AppTypography.monoCaption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            if viewModel.savedDevices.isEmpty {
                Text("Cuando conectes y guardes una cámara o teléfono por primera vez, aparecerá aquí con su alias y preferencias automáticas.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.panelSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            } else {
                ForEach(viewModel.savedDevices) { saved in
                    SavedDeviceRowView(
                        device: saved,
                        liveState: viewModel.liveState(for: saved),
                        aliasDraft: Binding(
                            get: { viewModel.aliasBinding(for: saved) },
                            set: { viewModel.setAliasDraft($0, for: saved.fingerprint) }
                        ),
                        onCommitAlias: { viewModel.commitAlias(for: saved.fingerprint) },
                        onToggleAutoConnect: { viewModel.setAutoConnect(fingerprint: saved.fingerprint, enabled: $0) },
                        onToggleKeepOriginals: { viewModel.setKeepOriginals(fingerprint: saved.fingerprint, enabled: $0) },
                        onToggleAllowJpg: { viewModel.setAllowJpgWhenNoRaw(fingerprint: saved.fingerprint, enabled: $0) },
                        onReleaseMacOSLock: { viewModel.releaseMacOSLock(for: saved.fingerprint) },
                        onRetryConnection: { viewModel.connect(fingerprint: saved.fingerprint) },
                        onForget: { viewModel.forget(fingerprint: saved.fingerprint) }
                    )
                }
            }
        }
    }

    private var mobileHelpNotice: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: "info.circle.fill")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.infoBlue)

            Text("Para usar un teléfono Android por cable, seleccioná 'Transferir imágenes (PTP)' en la notificación USB del celular. Para capturar RAW desde el móvil, usá el modo Pro / Expert RAW (.DNG).")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.infoBlueTint)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.infoBlue.opacity(0.35), lineWidth: AppSpacing.hairline)
        )
    }
}
