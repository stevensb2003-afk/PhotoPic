import SwiftUI

/// Persistent cloud OTA top banner shown when a new build from GitHub Releases
/// is downloading, ready to install, or available for download.
package struct CloudUpdateTopBanner: View {
    @Bindable var appState: AppState
    @State private var confirmSessionInterrupt = false

    package init(appState: AppState) {
        self.appState = appState
    }

    package var body: some View {
        let updater = appState.cloudUpdater
        switch updater.state {
        case .downloading(let manifest, _):
            bannerChrome(accent: AppColors.infoBlue) {
                ProgressView().controlSize(.small)
                Text("Descargando actualización automática v\(manifest.version) en segundo plano...")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }

        case .readyToInstall(let manifest, _) where updater.bannerDismissedForBuild != manifest.buildNumber:
            bannerChrome(accent: AppColors.approveGreen) {
                Circle()
                    .fill(AppColors.approveGreen)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nueva actualización v\(manifest.version) lista desde GitHub Cloud")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    if !manifest.releaseNotes.isEmpty {
                        Text(manifest.releaseNotes)
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("Actualizar y Reiniciar") {
                    if appState.activeSessionViewModel != nil {
                        confirmSessionInterrupt = true
                    } else {
                        updater.installReadyUpdateAndRelaunch()
                    }
                }
                .buttonStyle(StudioButtonStyle(.approveEmerald, compact: true))

                Button {
                    updater.bannerDismissedForBuild = manifest.buildNumber
                } label: {
                    Image(systemName: "xmark")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .alert("¿Cerrar sesión activa y actualizar?", isPresented: $confirmSessionInterrupt) {
                Button("Más tarde", role: .cancel) {}
                Button("Instalar y Reiniciar") {
                    appState.closeActiveSession()
                    updater.installReadyUpdateAndRelaunch()
                }
            } message: {
                Text("Tenés una sesión abierta en estudio. PhotoPic cerrará la vista actual para instalar v\(manifest.version) y volverá a abrir automáticamente en 2 segundos.")
            }

        case .updateAvailable(let manifest) where updater.bannerDismissedForBuild != manifest.buildNumber:
            bannerChrome(accent: AppColors.infoBlue) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(AppColors.infoBlue)
                Text("Nueva versión v\(manifest.version) disponible en la nube")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button("Descargar ahora") {
                    Task { await updater.downloadAndStageUpdate(manifest) }
                }
                .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                Button {
                    updater.bannerDismissedForBuild = manifest.buildNumber
                } label: {
                    Image(systemName: "xmark")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }

        case .installing(let version):
            bannerChrome(accent: AppColors.approveGreen) {
                ProgressView().controlSize(.small)
                Text("Aplicando actualización v\(version) y reiniciando...")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }

        default:
            EmptyView()
        }
    }

    private func bannerChrome<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: AppSpacing.md) {
            content()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle()
                .frame(height: AppSpacing.hairline)
                .foregroundStyle(accent.opacity(0.45)),
            alignment: .bottom
        )
    }
}

/// Settings card inside `GeneralSettingsView` displaying current cloud build & OTA controls.
package struct CloudUpdateSettingsCard: View {
    @Bindable var appState: AppState

    package init(appState: AppState) {
        self.appState = appState
    }

    package var body: some View {
        let updater = appState.cloudUpdater
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Actualizaciones Automáticas (Nube GitHub)")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text("v\(updater.identity.shortVersion) · build \(updater.identity.buildNumber)")
                    .font(AppTypography.monoMicro)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 3)
                    .background(AppColors.elevatedSurface)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Toggle(isOn: Binding(
                    get: { appState.performancePrefs.autoCheckForUpdates },
                    set: { enabled in
                        var updated = appState.performancePrefs
                        updated.autoCheckForUpdates = enabled
                        appState.updatePerformancePreferences(updated)
                    }
                )) {
                    Text("Buscar nuevas versiones automáticamente en la nube")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                }
                .toggleStyle(.switch)

                Toggle(isOn: Binding(
                    get: { appState.performancePrefs.autoDownloadUpdates },
                    set: { enabled in
                        var updated = appState.performancePrefs
                        updated.autoDownloadUpdates = enabled
                        appState.updatePerformancePreferences(updated)
                    }
                )) {
                    Text("Descargar y verificar (SHA-256) automáticamente en segundo plano")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .toggleStyle(.switch)
                .disabled(!appState.performancePrefs.autoCheckForUpdates)

                HStack(spacing: AppSpacing.sm) {
                    Text(updater.state.statusSummary)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)

                    Spacer()

                    actionButton(updater: updater)
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
    }

    @ViewBuilder
    private func actionButton(updater: CloudUpdateService) -> some View {
        switch updater.state {
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .readyToInstall:
            Button("Instalar y Reiniciar") {
                updater.installReadyUpdateAndRelaunch()
            }
            .buttonStyle(StudioButtonStyle(.approveEmerald, compact: true))
        case .updateAvailable(let manifest):
            Button("Descargar v\(manifest.version)") {
                Task { await updater.downloadAndStageUpdate(manifest) }
            }
            .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
        default:
            Button("Buscar actualizaciones") {
                Task { await updater.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
        }
    }
}
