import SwiftUI

/// Pestaña `Archivadas`: split grid & RAW GPU inspector with recovery to `Para_Edicion/`
/// and permanent disk deletion guarded by confirmation popovers.
package struct ArchivedPhotosView: View {
    @Bindable var viewModel: CullingSessionViewModel
    @State private var isConfirmingSingleDelete = false
    @State private var isConfirmingEmptyFolder = false

    package init(viewModel: CullingSessionViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        Group {
            if viewModel.archivedItems.isEmpty {
                emptyArchivedState
            } else {
                HSplitView {
                    archivedGridPane
                        .frame(minWidth: 340, maxWidth: 520)

                    archivedInspectorPane
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
            }
        }
        .background(AppColors.stageBackground)
        .onAppear {
            if let selected = viewModel.selectedArchivedItem {
                viewModel.loadArchivedPreview(for: selected)
            }
        }
    }

    private var archivedGridPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.archivedItems.count) descartadas")
                    .font(AppTypography.monoCaption)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                Button {
                    isConfirmingEmptyFolder = true
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        PictogrammersIcon(.trashCanOutline, size: 13)
                        Text("Vaciar carpeta...")
                    }
                }
                .buttonStyle(StudioButtonStyle(.archiveCoral, compact: true))
                .help("Eliminar permanentemente todas las fotos archivadas")
                .popover(isPresented: $isConfirmingEmptyFolder, arrowEdge: .bottom) {
                    EmptyArchivedFolderConfirmPopover(
                        itemCount: viewModel.archivedItems.count,
                        onCancel: { isConfirmingEmptyFolder = false },
                        onConfirmEmpty: { deleteJpgs in
                            isConfirmingEmptyFolder = false
                            viewModel.emptyAllArchivedPermanently(alsoDeleteCompanionJpgs: deleteJpgs)
                        }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.panelSurface)
            .overlay(
                Rectangle()
                    .frame(height: AppSpacing.hairline)
                    .foregroundStyle(AppColors.borderSubtle),
                alignment: .bottom
            )

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: AppSpacing.archivedGridMinWidth), spacing: AppSpacing.md)],
                    spacing: AppSpacing.md
                ) {
                    ForEach(viewModel.archivedItems) { item in
                        ArchivedTileView(
                            item: item,
                            isSelected: viewModel.selectedArchivedItem?.id == item.id,
                            cachedThumbnail: viewModel.archivedThumbnails[item.id],
                            loadThumbnail: { await viewModel.renderThumbnail(for: item) },
                            onSelect: {
                                isConfirmingSingleDelete = false
                                viewModel.selectArchivedItem(item)
                            }
                        )
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .background(AppColors.windowCanvas)
    }

    @ViewBuilder
    private var archivedInspectorPane: some View {
        if let selected = viewModel.selectedArchivedItem {
            VStack(spacing: 0) {
                ZStack {
                    AppColors.stageBackground
                    if let cgImage = viewModel.archivedPreviewImage {
                        Image(decorative: cgImage, scale: 1.0, orientation: .up)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(AppSpacing.lg)
                    } else if viewModel.isRenderingArchivedPreview {
                        ProgressView("Revelando RAW en GPU...")
                    } else {
                        Text("Seleccioná una foto archivada")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        HStack(spacing: AppSpacing.sm) {
                            Text(selected.filename)
                                .font(AppTypography.monoCounter)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(selected.formatExtension)
                                .font(AppTypography.monoMicro)
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 2)
                                .background(AppColors.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                        }

                        Text("\(selected.exif.compactHudSummary) · \(selected.formattedFileSize)")
                            .font(AppTypography.monoCaption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    Button {
                        isConfirmingSingleDelete = true
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            PictogrammersIcon(.trashCanOutline, size: 14)
                            Text("Eliminar archivo...")
                        }
                    }
                    .buttonStyle(StudioButtonStyle(.archiveCoral))
                    .help("Eliminar esta foto permanentemente del disco")
                    .popover(isPresented: $isConfirmingSingleDelete, arrowEdge: .top) {
                        ArchivedDeleteConfirmPopover(
                            item: selected,
                            onCancel: { isConfirmingSingleDelete = false },
                            onConfirmDelete: { deleteJpg in
                                isConfirmingSingleDelete = false
                                viewModel.deleteArchivedItemPermanently(
                                    selected,
                                    alsoDeleteCompanionJpg: deleteJpg
                                )
                            }
                        )
                    }

                    Button {
                        viewModel.recoverArchivedItemToEditing(selected)
                    } label: {
                        Label("Recuperar a Seleccionadas", systemImage: "arrow.uturn.right.circle.fill")
                    }
                    .buttonStyle(StudioButtonStyle(.approveEmerald))
                    .help("Recuperar esta foto hacia Seleccionadas para Edición")
                }
                .padding(AppSpacing.lg)
                .background(AppColors.panelSurface)
                .overlay(
                    Rectangle()
                        .frame(height: AppSpacing.hairline)
                        .foregroundStyle(AppColors.borderSubtle),
                    alignment: .top
                )
            }
        } else {
            emptyArchivedState
        }
    }

    private var emptyArchivedState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "archivebox")
                .font(AppTypography.displayTitle)
                .foregroundStyle(AppColors.textTertiary)
            Text("No hay fotos en Archivadas")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text("Las fotos descartadas con Swipe Izquierda o ← aparecerán aquí por si necesitás recuperarlas hacia Para_Edicion.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArchivedTileView: View {
    let item: PhotoItem
    let isSelected: Bool
    let cachedThumbnail: CGImage?
    let loadThumbnail: () async -> CGImage?
    let onSelect: () -> Void

    @State private var thumbnail: CGImage?
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ZStack {
                    AppColors.stageBackground
                    if let activeThumb = thumbnail ?? cachedThumbnail {
                        Image(decorative: activeThumb, scale: 1.0, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(height: 112)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

                HStack {
                    Text(item.filename)
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(item.formatExtension)
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(AppSpacing.sm)
            .background(isSelected ? AppColors.elevatedSurface : (isHovered ? AppColors.controlHover : AppColors.panelSurface))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(isSelected ? AppColors.borderFocus : (isHovered ? AppColors.borderStrong : AppColors.borderSubtle), lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Ver \(item.filename)")
        .task(id: item.id) {
            thumbnail = await loadThumbnail()
        }
    }
}
