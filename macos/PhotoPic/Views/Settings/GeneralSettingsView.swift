import AppKit
import SwiftUI

/// Settings Tab 2: Hardware audit & AI performance controls, Global Root Folder, and studio shortcuts.
package struct GeneralSettingsView: View {
    @Bindable var appState: AppState
    let onChangeRootFolder: () -> Void

    package init(appState: AppState, onChangeRootFolder: @escaping () -> Void) {
        self.appState = appState
        self.onChangeRootFolder = onChangeRootFolder
    }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                CloudUpdateSettingsCard(appState: appState)
                hardwareAndAISection
                sessionTimerSection
                rootFolderSection
                shortcutsSummarySection
            }
            .padding(AppSpacing.xl)
        }
    }

    private var sessionTimerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Temporizador de Sesiones Fotográficas")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Toggle(isOn: Binding(
                    get: { appState.performancePrefs.autoStartSessionTimerOnFirstShot },
                    set: { enabled in
                        var updated = appState.performancePrefs
                        updated.autoStartSessionTimerOnFirstShot = enabled
                        appState.updatePerformancePreferences(updated)
                    }
                )) {
                    Text("Auto-iniciar temporizador con la primera foto")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                }
                .toggleStyle(.switch)

                Text("Al recibir la primera foto en vivo dentro de la sesión, el reloj arranca automáticamente usando la hora de captura de esa primera foto. Siempre podés iniciar o finalizar el timer manualmente desde la barra superior.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
        }
    }

    private var hardwareAndAISection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Auditoría de Hardware y Motor IA")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(appState.performancePrefs.tier.shortBadge)
                    .font(AppTypography.monoMicro)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 3)
                    .background(AppColors.elevatedSurface)
                    .clipShape(Capsule())
            }

            HardwareAuditSettingsBlock(
                report: appState.hardwareAudit,
                preferences: appState.performancePrefs,
                compact: true,
                onSelectTier: { tier in appState.selectPerformanceTier(tier) },
                onToggleAutoTag: { enabled in
                    var updated = appState.performancePrefs
                    updated.enableVisionAutoTagging = enabled
                    if !enabled { updated.detectBodyPoses = false }
                    appState.updatePerformancePreferences(updated)
                },
                onTogglePoses: { enabled in
                    var updated = appState.performancePrefs
                    updated.detectBodyPoses = enabled
                    appState.updatePerformancePreferences(updated)
                },
                onReAudit: { appState.reAuditAndApplyRecommendedProfile() }
            )
            .padding(AppSpacing.md)
            .background(AppColors.panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
        }
    }

    private var rootFolderSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Carpeta Raíz Global")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(appState.rootFolderURL?.path ?? "Sin carpeta configurada")
                    .font(AppTypography.monoPath)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.stageBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

                HStack(spacing: AppSpacing.sm) {
                    Button("Cambiar carpeta...", action: onChangeRootFolder)
                        .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))

                    if let rootFolderURL = appState.rootFolderURL {
                        Button("Abrir en Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([rootFolderURL])
                        }
                        .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                    }
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

    private var shortcutsSummarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Atajos de Teclado y Gestos en Estudio")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            VStack(spacing: AppSpacing.xs) {
                shortcutRow(keys: ["↑", "↓"], title: "Navegar cola pendiente sin mover archivos")
                shortcutRow(keys: ["←"], title: "Archivar foto actual (mueve a Archivadas/)")
                shortcutRow(keys: ["→"], title: "Aprobar foto actual (mueve a Para_Edicion/)")
                shortcutRow(keys: ["Espacio"], title: "Activar / salir de Zoom 1:1 píxel real")
                shortcutRow(keys: ["Clic + Arrastrar"], title: "Lupa 1:1 instantánea al sostener sobre detalles")
                shortcutRow(keys: ["⌘Z"], title: "Deshacer última clasificación (restaura a RAW/)")
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

    private func shortcutRow(keys: [String], title: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            HStack(spacing: AppSpacing.xxs) {
                ForEach(keys, id: \.self) { key in
                    KeycapBadge(key)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
