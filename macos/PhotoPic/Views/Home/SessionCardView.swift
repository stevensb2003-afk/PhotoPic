import SwiftUI

/// Card representing an existing shooting session directory on disk with live counts,
/// Master Group badge, session timer duration, project tags, and permanent delete action.
package struct SessionCardView: View {
    let session: PhotoSession
    let availableGroups: [String]
    let onOpen: () -> Void
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onMoveToGroup: (String?) -> Void
    let onRequestDelete: () -> Void

    @State private var isHovering = false
    @State private var isPresentingOrgPopover = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    package init(
        session: PhotoSession,
        availableGroups: [String] = [],
        onOpen: @escaping () -> Void,
        onAddTag: @escaping (String) -> Void = { _ in },
        onRemoveTag: @escaping (String) -> Void = { _ in },
        onMoveToGroup: @escaping (String?) -> Void = { _ in },
        onRequestDelete: @escaping () -> Void = {}
    ) {
        self.session = session
        self.availableGroups = availableGroups
        self.onOpen = onOpen
        self.onAddTag = onAddTag
        self.onRemoveTag = onRemoveTag
        self.onMoveToGroup = onMoveToGroup
        self.onRequestDelete = onRequestDelete
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        Image(systemName: session.groupName == nil ? "folder.fill" : "folder.fill.badge.gearshape")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColors.textSecondary)

                        VStack(alignment: .leading, spacing: 3) {
                            if let group = session.groupName {
                                Text("📁 \(group)")
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColors.infoBlue)
                                    .lineLimit(1)
                            }
                            Text(session.name)
                                .font(AppTypography.cardTitle)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: AppSpacing.xs) {
                                Text(Self.dateFormatter.string(from: session.createdAt))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textTertiary)

                                if session.metadata.hasRecordedTime {
                                    Text("· ⏱ \(session.metadata.formattedDuration())")
                                        .font(AppTypography.monoMicro)
                                        .foregroundStyle(
                                            session.metadata.isTimerRunning
                                                ? AppColors.approveGreen
                                                : AppColors.textSecondary
                                        )
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: AppSpacing.xs) {
                    Button {
                        isPresentingOrgPopover.toggle()
                    } label: {
                        PictogrammersIcon(.tagMultipleOutline, size: 13)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(5)
                            .background(AppColors.stageBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Etiquetas y Carpeta Máster")
                    .popover(isPresented: $isPresentingOrgPopover, arrowEdge: .bottom) {
                        SessionOrganizationPopover(
                            session: session,
                            availableGroups: availableGroups,
                            onAddTag: onAddTag,
                            onRemoveTag: onRemoveTag,
                            onMoveToGroup: onMoveToGroup
                        )
                    }

                    Button(action: onRequestDelete) {
                        PictogrammersIcon(.trashCanOutline, size: 13)
                            .foregroundStyle(AppColors.archiveRed.opacity(0.85))
                            .padding(5)
                            .background(AppColors.stageBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Eliminar proyecto permanentemente")
                }
            }

            if !session.metadata.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xxs) {
                        ForEach(session.metadata.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(AppTypography.monoMicro)
                                .foregroundStyle(AppColors.infoBlue)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 2)
                                .background(AppColors.infoBlueTint)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Divider()
                .overlay(AppColors.borderSubtle)

            Button(action: onOpen) {
                HStack(spacing: AppSpacing.sm) {
                    countBadge(value: session.counts.pending, label: "Pendientes", tint: AppColors.warningAmber)
                    countBadge(value: session.counts.forEditing, label: "Para Edición", tint: AppColors.approveGreen)
                    countBadge(value: session.counts.archived, label: "Archivadas", tint: AppColors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? AppColors.elevatedSurface : AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(isHovering ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
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
