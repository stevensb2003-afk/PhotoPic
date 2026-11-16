import SwiftUI

/// Shared hardware audit telemetry, Neural Engine explanation, tier selector,
/// and AI switches reused by both the Guided Setup Wizard and Settings -> General.
package struct HardwareAuditSettingsBlock: View {
    let report: HardwareAuditReport
    let preferences: PerformancePreferences
    let compact: Bool
    let onSelectTier: @MainActor (PerformanceTier) -> Void
    let onToggleAutoTag: @MainActor (Bool) -> Void
    let onTogglePoses: @MainActor (Bool) -> Void
    let onReAudit: (@MainActor () -> Void)?

    package init(
        report: HardwareAuditReport,
        preferences: PerformancePreferences,
        compact: Bool = false,
        onSelectTier: @escaping @MainActor (PerformanceTier) -> Void,
        onToggleAutoTag: @escaping @MainActor (Bool) -> Void,
        onTogglePoses: @escaping @MainActor (Bool) -> Void,
        onReAudit: (@MainActor () -> Void)? = nil
    ) {
        self.report = report
        self.preferences = preferences
        self.compact = compact
        self.onSelectTier = onSelectTier
        self.onToggleAutoTag = onToggleAutoTag
        self.onTogglePoses = onTogglePoses
        self.onReAudit = onReAudit
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: compact ? AppSpacing.md : AppSpacing.lg) {
            hardwareGrid
            recommendationNotice
            tierSelector
            aiFeatureSwitches
        }
    }

    private var hardwareGrid: some View {
        let columns = [GridItem(.flexible(), spacing: AppSpacing.sm), GridItem(.flexible(), spacing: AppSpacing.sm)]
        return LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
            metricTile(
                asset: .chip,
                label: "Procesador y Arquitectura",
                value: report.cpuBrand,
                detail: report.architectureLabel,
                tint: AppColors.textPrimary
            )
            metricTile(
                asset: .creationSparkles,
                label: "Motor Neural Engine",
                value: report.hasAppleNeuralEngine ? "Apple Neural Engine activo" : "Sin Neural Engine físico",
                detail: report.hasAppleNeuralEngine
                    ? "Chip físico integrado en Apple Silicon"
                    : "La IA corre sobre CPU / GPU",
                tint: report.hasAppleNeuralEngine ? AppColors.approveGreen : AppColors.warningAmber
            )
            metricTile(
                asset: .memory,
                label: "Memoria y Núcleos",
                value: "\(report.physicalMemoryGB) GB RAM · \(report.activeCores) núcleos",
                detail: report.physicalMemoryGB >= 12 ? "Apto para cola RAW + IA completa" : "Conviene perfil ligero o equilibrado",
                tint: AppColors.infoBlue
            )
            metricTile(
                asset: .speedometer,
                label: "Aceleración Gráfica Metal",
                value: report.gpuName,
                detail: report.hasMetalGPU ? "Revelado CIRAWFilter en GPU activo" : "Respaldo por CPU",
                tint: report.hasMetalGPU ? AppColors.approveGreen : AppColors.warningAmber
            )
        }
    }

    private func metricTile(
        asset: PictogrammersAsset,
        label: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xs) {
                PictogrammersIcon(asset, size: 13)
                    .foregroundStyle(tint)
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }
            Text(value)
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
            Text(detail)
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }

    private var recommendationNotice: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            PictogrammersIcon(.checkDecagram, size: 15)
                .foregroundStyle(AppColors.approveGreen)
                .padding(.top, 2)

            Text(report.recommendationReason)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AppSpacing.sm)

            if let onReAudit {
                Button("Re-auditar") {
                    onReAudit()
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.approveGreenTint)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.approveGreen.opacity(0.35), lineWidth: AppSpacing.hairline)
        )
    }

    private var tierSelector: some View {
        VStack(spacing: AppSpacing.xs) {
            ForEach(PerformanceTier.allCases, id: \.self) { tier in
                let isSelected = preferences.tier == tier
                let isRecommended = report.recommendedTier == tier
                Button {
                    onSelectTier(tier)
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? AppColors.approveGreen : AppColors.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: AppSpacing.sm) {
                                Text(tier.title)
                                    .font(AppTypography.bodyMedium)
                                    .foregroundStyle(AppColors.textPrimary)
                                if isRecommended {
                                    Text("Recomendado")
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColors.approveGreen)
                                        .padding(.horizontal, AppSpacing.xs)
                                        .padding(.vertical, 2)
                                        .background(AppColors.approveGreenTint)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(tier.subtitle)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(AppSpacing.md)
                    .background(isSelected ? AppColors.elevatedSurface : AppColors.stageBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(isSelected ? AppColors.approveGreen.opacity(0.6) : AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aiFeatureSwitches: some View {
        VStack(spacing: AppSpacing.xs) {
            Toggle(
                "Activar auto-etiquetado IA de caras y personas al capturar",
                isOn: Binding(get: { preferences.enableVisionAutoTagging }, set: { onToggleAutoTag($0) })
            )
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)

            Toggle(
                "Incluir detección corporal de poses (19 articulaciones)",
                isOn: Binding(get: { preferences.detectBodyPoses }, set: { onTogglePoses($0) })
            )
            .font(AppTypography.body)
            .foregroundStyle(preferences.enableVisionAutoTagging ? AppColors.textPrimary : AppColors.textTertiary)
            .disabled(!preferences.enableVisionAutoTagging)
        }
        .padding(AppSpacing.md)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }
}
