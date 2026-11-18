import SwiftUI

/// Reusable popover to rename a session or master group folder directly on disk.
package struct RenameFolderPopover: View {
    let title: String
    let subtitle: String
    let placeholder: String
    @State private var draftName: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    package init(
        title: String,
        subtitle: String,
        currentName: String,
        placeholder: String = "Nuevo nombre",
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self._draftName = State(initialValue: currentName)
        self.placeholder = placeholder
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)

            Text(subtitle)
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textTertiary)

            TextField(placeholder, text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)
                .onSubmit { submit() }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .buttonStyle(StudioButtonStyle(.ghost, compact: true))
                Button("Renombrar") { submit() }
                    .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                    .disabled(trimmedDraft.isEmpty)
            }
        }
        .padding(AppSpacing.md)
        .frame(width: 280)
        .background(AppColors.panelSurface)
    }

    private var trimmedDraft: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedDraft.isEmpty else { return }
        onConfirm(trimmedDraft)
    }
}

/// Card representing an existing shooting session directory on disk with live counts,
/// optional Master Group badge, rename, project tags, and permanent delete action.
package struct SessionCardView: View {
    let session: PhotoSession
    let availableGroups: [String]
    let showGroupBadge: Bool
    let onOpen: () -> Void
    let onRename: ((String) -> Void)?
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onMoveToGroup: (String?) -> Void
    let onRequestDelete: () -> Void

    @State private var isHovering = false
    @State private var isRenameHovered = false
    @State private var isTagHovered = false
    @State private var isDeleteHovered = false
    @State private var isPresentingRenamePopover = false
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
        showGroupBadge: Bool = true,
        onOpen: @escaping () -> Void,
        onRename: ((String) -> Void)? = nil,
        onAddTag: @escaping (String) -> Void = { _ in },
        onRemoveTag: @escaping (String) -> Void = { _ in },
        onMoveToGroup: @escaping (String?) -> Void = { _ in },
        onRequestDelete: @escaping () -> Void = {}
    ) {
        self.session = session
        self.availableGroups = availableGroups
        self.showGroupBadge = showGroupBadge
        self.onOpen = onOpen
        self.onRename = onRename
        self.onAddTag = onAddTag
        self.onRemoveTag = onRemoveTag
        self.onMoveToGroup = onMoveToGroup
        self.onRequestDelete = onRequestDelete
    }

    package var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        if showGroupBadge, let group = session.groupName {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.stack.fill")
                                    .font(.system(size: 9))
                                Text(group)
                            }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, onRename != nil ? 86 : 56)

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

                    HStack(spacing: AppSpacing.sm) {
                        countBadge(value: session.counts.pending, label: "Pendientes", tint: AppColors.warningAmber)
                        countBadge(value: session.counts.forEditing, label: "Seleccionadas", tint: AppColors.approveGreen)
                        countBadge(value: session.counts.archived, label: "Archivadas", tint: AppColors.textSecondary)
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
            .help("Abrir sesión \(session.name)")

            HStack(spacing: AppSpacing.xs) {
                if let onRename {
                    Button {
                        isPresentingRenamePopover.toggle()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isRenameHovered ? AppColors.textPrimary : AppColors.textSecondary)
                            .frame(width: 23, height: 23)
                            .background(isRenameHovered ? AppColors.controlHover : AppColors.stageBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover { isRenameHovered = $0 }
                    .help("Renombrar sesión y su carpeta en Finder")
                    .popover(isPresented: $isPresentingRenamePopover, arrowEdge: .bottom) {
                        RenameFolderPopover(
                            title: "Renombrar sesión",
                            subtitle: "También renombra la carpeta real en Finder.",
                            currentName: session.name,
                            placeholder: "Ej. Familia_Navidad",
                            onCancel: { isPresentingRenamePopover = false },
                            onConfirm: { newName in
                                isPresentingRenamePopover = false
                                onRename(newName)
                            }
                        )
                    }
                }

                Button {
                    isPresentingOrgPopover.toggle()
                } label: {
                    PictogrammersIcon(.tagMultipleOutline, size: 13)
                        .foregroundStyle(isTagHovered ? AppColors.textPrimary : AppColors.textSecondary)
                        .padding(5)
                        .background(isTagHovered ? AppColors.controlHover : AppColors.stageBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isTagHovered = $0 }
                .help("Etiquetas y grupo")
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
                        .foregroundStyle(isDeleteHovered ? AppColors.archiveRed : AppColors.archiveRed.opacity(0.85))
                        .padding(5)
                        .background(isDeleteHovered ? AppColors.archiveRedTint : AppColors.stageBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isDeleteHovered = $0 }
                .help("Eliminar sesión permanentemente")
            }
            .padding(AppSpacing.lg)
        }
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
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
    }
}
