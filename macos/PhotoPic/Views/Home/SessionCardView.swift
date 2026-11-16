import SwiftUI

/// Card representing an existing shooting session directory on disk with live counts.
package struct SessionCardView: View {
    let session: PhotoSession
    let onOpen: () -> Void
    @State private var isHovering = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    package init(session: PhotoSession, onOpen: @escaping () -> Void) {
        self.session = session
        self.onOpen = onOpen
    }

    package var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: "folder.fill")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Text(Self.dateFormatter.string(from: session.createdAt))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(AppTypography.caption)
                        .foregroundStyle(isHovering ? AppColors.textPrimary : AppColors.textTertiary)
                }

                Divider()
                    .overlay(AppColors.borderSubtle)

                HStack(spacing: AppSpacing.sm) {
                    countBadge(
                        value: session.counts.pending,
                        label: "Pendientes",
                        tint: AppColors.warningAmber
                    )
                    countBadge(
                        value: session.counts.forEditing,
                        label: "Para Edición",
                        tint: AppColors.approveGreen
                    )
                    countBadge(
                        value: session.counts.archived,
                        label: "Archivadas",
                        tint: AppColors.textSecondary
                    )
                }
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? AppColors.elevatedSurface : AppColors.panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(isHovering ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppMotion.quickEaseOut) {
                isHovering = hovering
            }
        }
    }

    private func countBadge(value: Int, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(AppTypography.monoCounter)
                .foregroundStyle(tint)
            Text(label)
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
    }
}
