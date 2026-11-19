import AppKit
import SwiftUI

/// Pestaña `Seleccionadas`: split grid & GPU RAW inspector allowing review, Finder reveal,
/// returning a photo to `Filtrar`, or moving a selected photo to `Archivadas`.
package struct SelectedPhotosView: View {
    @Bindable var viewModel: CullingSessionViewModel

    package init(viewModel: CullingSessionViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        Group {
            if viewModel.forEditingItems.isEmpty {
                emptySelectedState
            } else {
                HSplitView {
                    selectedGridPane
                        .frame(minWidth: 340, maxWidth: 520)

                    selectedInspectorPane
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
            }
        }
        .background(AppColors.stageBackground)
        .onAppear {
            if let selected = viewModel.selectedEditingItem {
                viewModel.loadEditingPreview(for: selected)
            }
        }
        .onChange(of: viewModel.selectedEditingItem?.id) { _, _ in
            if let selected = viewModel.selectedEditingItem {
                viewModel.loadEditingPreview(for: selected)
            }
        }
    }

    private var selectedGridPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.forEditingItems.count) seleccionadas")
                    .font(AppTypography.monoCaption)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([viewModel.session.forEditingFolderURL])
                } label: {
                    Label("Mostrar en Finder", systemImage: "folder")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help("Abrir carpeta Para_Edicion en Finder")
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
                    ForEach(viewModel.forEditingItems) { item in
                        SelectedTileView(
                            item: item,
                            isSelected: viewModel.selectedEditingItem?.id == item.id,
                            cachedThumbnail: viewModel.archivedThumbnails[item.id],
                            loadThumbnail: { await viewModel.renderThumbnail(for: item) },
                            onSelect: {
                                viewModel.selectEditingItem(item)
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
    private var selectedInspectorPane: some View {
        if let selected = viewModel.selectedEditingItem {
            VStack(spacing: 0) {
                InteractiveZoomPhotoCanvas(
                    image: viewModel.editingPreviewImage,
                    itemID: selected.id,
                    isLoading: viewModel.isRenderingEditingPreview,
                    emptyLabel: "Seleccioná una foto para inspeccionar"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: AppSpacing.md) {
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
                            if selected.pairedCompressedURL != nil {
                                Text("+JPG")
                                    .font(AppTypography.monoMicro)
                                    .foregroundStyle(AppColors.infoBlue)
                                    .padding(.horizontal, AppSpacing.xs)
                                    .padding(.vertical, 2)
                                    .background(AppColors.elevatedSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                            }
                        }

                        Text("\(selected.exif.compactHudSummary) · \(selected.formattedFileSize)")
                            .font(AppTypography.monoCaption)
                            .foregroundStyle(AppColors.textSecondary)

                        if let tags = selected.visionTags, !tags.allTags.isEmpty {
                            HStack(spacing: AppSpacing.xs) {
                                ForEach(tags.allTags.prefix(4), id: \.self) { tag in
                                    let isClosedEyes = tag == "Ojos cerrados"
                                    Text(tag)
                                        .font(AppTypography.monoMicro)
                                        .foregroundStyle(isClosedEyes ? AppColors.warningAmber : AppColors.textSecondary)
                                        .padding(.horizontal, AppSpacing.xs)
                                        .padding(.vertical, 2)
                                        .background(isClosedEyes ? AppColors.warningAmberTint : AppColors.elevatedSurface)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.rotatePhotoClockwise(selected)
                    } label: {
                        Label("Rotar", systemImage: "rotate.right")
                    }
                    .buttonStyle(StudioButtonStyle(.secondaryDark))
                    .help("Rotar 90° a la derecha y guardar en el archivo (Shift)")

                    Button {
                        viewModel.returnEditingItemToPending(selected)
                    } label: {
                        Label("Devolver a Filtrar", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(StudioButtonStyle(.secondaryDark))
                    .help("Devolver esta foto a la cola de Filtrar para volver a revisarla")

                    Button {
                        viewModel.moveEditingItemToArchived(selected)
                    } label: {
                        Label("Mover a Archivadas", systemImage: "archivebox")
                    }
                    .buttonStyle(StudioButtonStyle(.archiveCoral))
                    .help("Descartar esta selección y mover sus archivos a Archivadas")
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
            emptySelectedState
        }
    }

    private var emptySelectedState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.seal")
                .font(AppTypography.displayTitle)
                .foregroundStyle(AppColors.textTertiary)
            Text("Todavía no hay fotos seleccionadas")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text("Aprobá fotos desde Filtrar (→) para revisarlas aquí o volver a archivarlas cuando quieras.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SelectedTileView: View {
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
                    .stroke(isSelected ? AppColors.approveGreen.opacity(0.65) : (isHovered ? AppColors.borderStrong : AppColors.borderSubtle), lineWidth: AppSpacing.hairline)
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
