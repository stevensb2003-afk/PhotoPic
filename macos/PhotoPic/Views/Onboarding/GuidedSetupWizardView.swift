import SwiftUI

/// Guided 2-step first-run installation wizard:
/// Step 1 audits host hardware (CPU, Neural Engine, RAM, Metal GPU) & lets user adjust AI;
/// Step 2 picks the Global Root Folder via NSOpenPanel.
package struct GuidedSetupWizardView: View {
    package enum WizardStep: Int, Sendable {
        case hardwareAudit = 1
        case rootFolder = 2
    }

    @Bindable var appState: AppState
    @State private var step: WizardStep

    package init(appState: AppState, initialStep: WizardStep = .hardwareAudit) {
        self.appState = appState
        self._step = State(initialValue: initialStep)
    }

    package var body: some View {
        ZStack {
            AppColors.windowCanvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                wizardHeader

                switch step {
                case .hardwareAudit:
                    hardwareStepCard
                case .rootFolder:
                    RootFolderOnboardingView(
                        embeddedInWizard: true,
                        onChooseFolder: { appState.pickAndSetRootFolder() },
                        onBack: { step = .hardwareAudit }
                    )
                }
            }
            .frame(maxWidth: AppSpacing.wizardMaxWidth)
            .padding(AppSpacing.xl)
        }
    }

    private var wizardHeader: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.elevatedSurface)
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.borderStrong, lineWidth: AppSpacing.hairline)
                    )
                PictogrammersIcon(.cameraIris, size: 26)
                    .foregroundStyle(AppColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("PhotoPic · Asistente Inicial")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Ajustamos el motor RAW e IA a tu Mac antes de empezar a capturar")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            HStack(spacing: AppSpacing.xs) {
                stepBadge(number: 1, title: "Hardware e IA", isActive: step == .hardwareAudit)
                stepBadge(number: 2, title: "Carpeta Raíz", isActive: step == .rootFolder)
            }
        }
    }

    private func stepBadge(number: Int, title: String, isActive: Bool) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text("\(number)")
                .font(AppTypography.monoMicro)
                .foregroundStyle(isActive ? AppColors.textOnAccent : AppColors.textTertiary)
                .frame(width: 18, height: 18)
                .background(isActive ? AppColors.primaryActionFill : AppColors.elevatedSurface)
                .clipShape(Circle())
            Text(title)
                .font(AppTypography.captionMedium)
                .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textTertiary)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.panelSurface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isActive ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }

    private var hardwareStepCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Paso 1: Auditoría de Capacidad de tu Mac")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Podés elegir el perfil recomendado o desactivar la detección IA por completo si preferís priorizar batería o fluidez en equipos antiguos.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
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
                }
            )

            HStack {
                Text("Perfil activo: \(appState.performancePrefs.tier.shortBadge)")
                    .font(AppTypography.monoCaption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button("Continuar al Paso 2 →") {
                    step = .rootFolder
                }
                .buttonStyle(StudioButtonStyle(.primaryLight))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.xl)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }
}
