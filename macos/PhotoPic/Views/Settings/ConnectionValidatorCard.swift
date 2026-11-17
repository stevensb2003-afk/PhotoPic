import SwiftUI

/// Interactive 3-stage USB connection validator, native permission prompt waker,
/// conflict checker, and brand-by-brand setup guide inside Settings -> Devices.
package struct ConnectionValidatorCard: View {
    @Bindable var viewModel: DeviceManagerViewModel
    @State private var selectedGuide: DeviceBrandGuide = .samsungAndroid
    @State private var hasInitializedGuide = false

    package init(viewModel: DeviceManagerViewModel) {
        self.viewModel = viewModel
    }

    private var report: ConnectionValidationReport {
        viewModel.validationReport
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            headerSection
            stagesRow
            alertsSection
            brandGuideSection
        }
        .padding(AppSpacing.lg)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
        .onAppear {
            if !hasInitializedGuide {
                selectedGuide = report.recommendedGuide
                hasInitializedGuide = true
            }
        }
        .onChange(of: report.recommendedGuide) { _, newGuide in
            selectedGuide = newGuide
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Validador y Asistente de Conexión USB")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(report.headline) — \(report.subheadline)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Probar / Despertar Permiso en Móvil") {
                Task { await viewModel.runDiagnosticProbe() }
            }
            .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
        }
    }

    private var stagesRow: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(report.stages, id: \.title) { stage in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: iconName(for: stage))
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(iconColor(for: stage))
                        Text(stage.title)
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    Text(stage.detail)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(AppColors.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(borderColor(for: stage), lineWidth: AppSpacing.hairline)
                )
            }
        }
    }

    @ViewBuilder
    private var alertsSection: some View {
        if report.hasUnmountedHardware {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.warningAmber)
                Text("Tu Mac detectó hardware fotográfico conectado al cable USB, pero el dispositivo está en 'Solo carga' / Mass Storage o sin permiso PTP. Seguí la guía de abajo y tocá Reintentar.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.warningAmberTint)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        }

        if !report.conflictingApps.isEmpty {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "app.badge.checkmark")
                    .foregroundStyle(AppColors.warningAmber)
                Text("Apps abiertas compitiendo por el puerto USB: \(report.conflictingApps.joined(separator: ", ")). Ciérralas si tu cámara no responde.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.warningAmberTint)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        }
    }

    private var brandGuideSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(DeviceBrandGuide.allCases) { guide in
                        let selected = selectedGuide == guide
                        Button {
                            selectedGuide = guide
                        } label: {
                            Text(guide.title)
                                .font(AppTypography.captionMedium)
                                .foregroundStyle(selected ? AppColors.textOnAccent : AppColors.textSecondary)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, 5)
                                .background(selected ? AppColors.primaryActionFill : AppColors.elevatedSurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(selectedGuide.menuPathSummary)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)

                Text(selectedGuide.modesToAvoid)
                    .font(AppTypography.monoMicro)
                    .foregroundStyle(AppColors.warningAmber)

                ForEach(selectedGuide.checklistSteps, id: \.self) { step in
                    Text(step)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.infoBlue)
                    Text(selectedGuide.rawTip)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.infoBlue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.stageBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private func iconName(for stage: ValidationStageResult) -> String {
        if stage.passed { return "checkmark.circle.fill" }
        return stage.warning ? "exclamationmark.triangle.fill" : "circle.dashed"
    }

    private func iconColor(for stage: ValidationStageResult) -> Color {
        if stage.passed { return AppColors.approveGreen }
        return stage.warning ? AppColors.warningAmber : AppColors.textTertiary
    }

    private func borderColor(for stage: ValidationStageResult) -> Color {
        if stage.passed { return AppColors.approveGreen.opacity(0.3) }
        return stage.warning ? AppColors.warningAmber.opacity(0.45) : AppColors.borderSubtle
    }
}
