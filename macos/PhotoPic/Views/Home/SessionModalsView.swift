import SwiftUI

/// Confirmation sheet warning before permanently deleting a session directory and all its photos.
package struct DeleteSessionConfirmationSheet: View {
    let session: PhotoSession
    let onCancel: () -> Void
    let onConfirmPermanentDelete: () -> Void

    package init(
        session: PhotoSession,
        onCancel: @escaping () -> Void,
        onConfirmPermanentDelete: @escaping () -> Void
    ) {
        self.session = session
        self.onCancel = onCancel
        self.onConfirmPermanentDelete = onConfirmPermanentDelete
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.sm) {
                PictogrammersIcon(.deleteAlertOutline, size: 24)
                    .foregroundStyle(AppColors.archiveRed)

                VStack(alignment: .leading, spacing: 2) {
                    Text("¿Eliminar proyecto permanentemente?")
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Esta acción borrará la carpeta completa y todas sus fotos del disco.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(session.name)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    if let group = session.groupName {
                        Text("📁 \(group)")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 2)
                            .background(AppColors.elevatedSurface)
                            .clipShape(Capsule())
                    }
                }

                Text(
                    "Total a eliminar: \(session.counts.totalAllImages) fotos "
                    + "(Pendientes: \(session.counts.pending) · Para Edición: \(session.counts.forEditing) · Archivadas: \(session.counts.archived))"
                )
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppColors.warningAmber)

                Text(session.directoryURL.path)
                    .font(AppTypography.monoPath)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(2)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.stageBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.archiveRed.opacity(0.35), lineWidth: AppSpacing.hairline)
            )

            Text("No va a la Papelera ni se puede deshacer con ⌘Z. Se borrarán permanentemente todas las subcarpetas RAW/, JPG/, Para_Edicion/ y Archivadas/.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .buttonStyle(StudioButtonStyle(.ghost))
                    .keyboardShortcut(.cancelAction)

                Button("Eliminar Permanentemente", action: onConfirmPermanentDelete)
                    .buttonStyle(StudioButtonStyle(.archiveCoral))
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 470)
        .background(AppColors.panelSurface)
    }
}

/// Popover for assigning project tags and moving a session into a Master Group folder.
package struct SessionOrganizationPopover: View {
    let session: PhotoSession
    let availableGroups: [String]
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onMoveToGroup: (String?) -> Void

    @State private var tagDraft = ""
    @State private var newGroupDraft = ""

    package init(
        session: PhotoSession,
        availableGroups: [String],
        onAddTag: @escaping (String) -> Void,
        onRemoveTag: @escaping (String) -> Void,
        onMoveToGroup: @escaping (String?) -> Void
    ) {
        self.session = session
        self.availableGroups = availableGroups
        self.onAddTag = onAddTag
        self.onRemoveTag = onRemoveTag
        self.onMoveToGroup = onMoveToGroup
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Organizar Proyecto")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Etiquetas del proyecto")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: AppSpacing.xs) {
                    TextField("Ej. Navidad, Exterior, VIP", text: $tagDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submitTag() }
                    Button("Agregar") { submitTag() }
                        .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                }

                if !session.metadata.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.xs) {
                            ForEach(session.metadata.tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text("#\(tag)")
                                        .font(AppTypography.monoMicro)
                                    Button {
                                        onRemoveTag(tag)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(AppColors.infoBlue)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 3)
                                .background(AppColors.infoBlueTint)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            Divider()
                .overlay(AppColors.borderSubtle)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Carpeta Máster / Categoría")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                Picker(
                    "Grupo",
                    selection: Binding(
                        get: { session.groupName ?? "" },
                        set: { selected in
                            onMoveToGroup(selected.isEmpty ? nil : selected)
                        }
                    )
                ) {
                    Text("Sin grupo (Carpeta Raíz)").tag("")
                    ForEach(availableGroups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
                .labelsHidden()

                HStack(spacing: AppSpacing.xs) {
                    TextField("O mover a nueva carpeta máster...", text: $newGroupDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submitNewGroupMove() }
                    Button("Mover") { submitNewGroupMove() }
                        .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                        .disabled(newGroupDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(width: 320)
        .background(AppColors.panelSurface)
    }

    private func submitTag() {
        let trimmed = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddTag(trimmed)
        tagDraft = ""
    }

    private func submitNewGroupMove() {
        let trimmed = newGroupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onMoveToGroup(trimmed)
        newGroupDraft = ""
    }
}
