import SwiftUI

/// Confirmation `.popover` content to permanently delete a single archived RAW/JPG + sidecar.
package struct ArchivedDeleteConfirmPopover: View {
    let item: PhotoItem
    let onCancel: @MainActor () -> Void
    let onConfirmDelete: @MainActor (_ alsoDeleteCompanionJpg: Bool) -> Void

    @State private var alsoDeleteCompanionJpg = false

    package init(
        item: PhotoItem,
        onCancel: @escaping @MainActor () -> Void,
        onConfirmDelete: @escaping @MainActor (_ alsoDeleteCompanionJpg: Bool) -> Void
    ) {
        self.item = item
        self.onCancel = onCancel
        self.onConfirmDelete = onConfirmDelete
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(AppColors.archiveRedTint)
                        .frame(width: 32, height: 32)
                    PictogrammersIcon(.deleteAlertOutline, size: 18)
                        .foregroundStyle(AppColors.archiveRed)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("¿Eliminar foto definitivamente?")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("\(item.filename) · \(item.formattedFileSize)")
                        .font(AppTypography.monoCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Text("Se borrará del disco de Archivadas/ junto con su archivo .XMP de etiquetas. Esta acción no se puede deshacer con ⌘Z.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let companion = item.pairedCompressedURL {
                Toggle(
                    "Eliminar también copia \(companion.lastPathComponent) en JPG/",
                    isOn: $alsoDeleteCompanionJpg
                )
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPrimary)
            }

            HStack(spacing: AppSpacing.sm) {
                Button("Cancelar", action: onCancel)
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))

                Spacer()

                Button {
                    onConfirmDelete(alsoDeleteCompanionJpg)
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        PictogrammersIcon(.trashCanOutline, size: 13)
                        Text("Eliminar para siempre")
                    }
                }
                .buttonStyle(StudioButtonStyle(.archiveCoral, compact: true))
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 340)
        .background(AppColors.panelSurface)
    }
}

/// Confirmation `.popover` content to empty every file inside `Archivadas/` permanently.
package struct EmptyArchivedFolderConfirmPopover: View {
    let itemCount: Int
    let onCancel: @MainActor () -> Void
    let onConfirmEmpty: @MainActor (_ alsoDeleteCompanionJpgs: Bool) -> Void

    @State private var alsoDeleteCompanionJpgs = false

    package init(
        itemCount: Int,
        onCancel: @escaping @MainActor () -> Void,
        onConfirmEmpty: @escaping @MainActor (_ alsoDeleteCompanionJpgs: Bool) -> Void
    ) {
        self.itemCount = itemCount
        self.onCancel = onCancel
        self.onConfirmEmpty = onConfirmEmpty
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(AppColors.archiveRedTint)
                        .frame(width: 32, height: 32)
                    PictogrammersIcon(.deleteAlertOutline, size: 18)
                        .foregroundStyle(AppColors.archiveRed)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("¿Vaciar toda la carpeta Archivadas?")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("\(itemCount) archivos serán eliminados del disco")
                        .font(AppTypography.monoCaption)
                        .foregroundStyle(AppColors.archiveRed)
                }
            }

            Text("Liberará espacio borrando permanentemente todos los descartes en Archivadas/ y sus .XMP. Las fotos en RAW/ y Para_Edicion/ quedan intactas.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(
                "Eliminar también copias JPG asociadas de estas fotos",
                isOn: $alsoDeleteCompanionJpgs
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: AppSpacing.sm) {
                Button("Cancelar", action: onCancel)
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))

                Spacer()

                Button {
                    onConfirmEmpty(alsoDeleteCompanionJpgs)
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        PictogrammersIcon(.trashCanOutline, size: 13)
                        Text("Vaciar (\(itemCount))")
                    }
                }
                .buttonStyle(StudioButtonStyle(.archiveCoral, compact: true))
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 350)
        .background(AppColors.panelSurface)
    }
}
