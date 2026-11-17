import SwiftUI

/// Compact live shooting session timer control inside the workspace sub-header.
package struct SessionTimerPillView: View {
    @Bindable var viewModel: CullingSessionViewModel

    package init(viewModel: CullingSessionViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        let meta = viewModel.session.metadata
        HStack(spacing: AppSpacing.xs) {
            PulsingStatusDot(
                color: statusColor(for: meta),
                isActive: meta.isTimerRunning
            )

            Text(viewModel.formattedSessionDuration)
                .font(AppTypography.monoCounter)
                .foregroundStyle(meta.isTimerRunning ? AppColors.textPrimary : AppColors.textSecondary)

            if meta.isTimerRunning {
                Button {
                    viewModel.stopAndFinishSessionTimer()
                } label: {
                    Label("Finalizar", systemImage: "stop.fill")
                        .font(AppTypography.micro)
                }
                .buttonStyle(StudioButtonStyle(.archiveCoral, compact: true))
                .help("Detener y registrar duración de la sesión")
            } else if meta.isTimerFinished {
                Button {
                    viewModel.startSessionTimerManual()
                } label: {
                    Label("Reanudar", systemImage: "play.fill")
                        .font(AppTypography.micro)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))

                Button {
                    viewModel.resetSessionTimer()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(AppTypography.micro)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textTertiary)
                .help("Reiniciar temporizador")
            } else {
                Button {
                    viewModel.startSessionTimerManual()
                } label: {
                    Label("Iniciar Timer", systemImage: "play.fill")
                        .font(AppTypography.micro)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help(
                    viewModel.autoStartTimerOnFirstShot
                        ? "Se inicia automático con la 1ª foto en vivo o manualmente aquí"
                        : "Iniciar temporizador manualmente"
                )

                if viewModel.autoStartTimerOnFirstShot {
                    Text("Auto 1ª foto")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background(meta.isTimerRunning ? AppColors.elevatedSurface : AppColors.panelSurface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    meta.isTimerRunning ? AppColors.approveGreen.opacity(0.45) : AppColors.borderSubtle,
                    lineWidth: AppSpacing.hairline
                )
        )
    }

    private func statusColor(for meta: SessionMetadata) -> Color {
        if meta.isTimerRunning { return AppColors.approveGreen }
        if meta.isTimerFinished { return AppColors.warningAmber }
        return AppColors.textTertiary
    }
}
