import SwiftUI

/// Bottom culling control deck organized into 3 balanced zones:
/// Left: Zoom 1:1 + Undo (`⌘Z`)
/// Center: 4 uniformly sized primary actions (`← Archivar`, `↑ Anterior`, `↓ Siguiente`, `Edición →`)
/// Right: "Seguir última captura" toggle
package struct CullingControlsBar: View {
    @Bindable var viewModel: CullingSessionViewModel

    package init(viewModel: CullingSessionViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Left utilities: Zoom 1:1, Rotate (Shift), Undo (⌘Z)
            HStack(spacing: AppSpacing.xs) {
                Button {
                    viewModel.toggleLockedOneToOneZoom()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: viewModel.isAnyZoomActive ? "minus.magnifyingglass" : "plus.magnifyingglass")
                        Text("Zoom 1:1")
                        KeycapBadge("Espacio")
                    }
                }
                .buttonStyle(StudioButtonStyle(viewModel.isAnyZoomActive ? .primaryLight : .secondaryDark, compact: true))
                .disabled(viewModel.currentPendingItem == nil)
                .help("Alternar Zoom 1:1 real sobre el sensor (Espacio)")

                Button {
                    viewModel.rotateActivePhotoClockwise()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "rotate.right")
                        KeycapBadge("Shift")
                    }
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .disabled(viewModel.currentPendingItem == nil)
                .help("Rotar 90° a la derecha y guardar en el archivo (Shift)")

                Button {
                    viewModel.undoLastMove()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.uturn.backward")
                        KeycapBadge("⌘Z")
                    }
                }
                .buttonStyle(StudioButtonStyle(.ghost, compact: true))
                .disabled(!viewModel.canUndo)
                .help("Deshacer última clasificación (⌘Z)")
            }

            Spacer(minLength: AppSpacing.sm)

            // Centered 4 Uniform Action Controls
            HStack(spacing: AppSpacing.xs) {
                Button {
                    viewModel.requestAnimatedArchive()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        KeycapBadge("←")
                        Text("Archivar")
                    }
                    .frame(width: 92)
                }
                .buttonStyle(StudioButtonStyle(.archiveCoral, compact: true))
                .disabled(viewModel.currentPendingItem == nil)
                .help("Descartar hacia Archivadas (Flecha Izquierda ←)")

                Button {
                    viewModel.navigatePrevious()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        KeycapBadge("↑")
                        Text("Anterior")
                    }
                    .frame(width: 92)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .disabled(viewModel.currentIndex <= 0 || viewModel.pendingItems.isEmpty)
                .help("Ver foto pendiente anterior (Flecha Arriba ↑)")

                Button {
                    viewModel.navigateNext()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        KeycapBadge("↓")
                        Text("Siguiente")
                    }
                    .frame(width: 92)
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .disabled(viewModel.currentIndex + 1 >= viewModel.visiblePendingItems.count)
                .help("Ver siguiente foto pendiente (Flecha Abajo ↓)")

                Button {
                    viewModel.requestAnimatedApprove()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text("Edición")
                        KeycapBadge("→")
                    }
                    .frame(width: 92)
                }
                .buttonStyle(StudioButtonStyle(.approveEmerald, compact: true))
                .disabled(viewModel.currentPendingItem == nil)
                .help("Aprobar hacia Seleccionadas para Edición (Flecha Derecha →)")
            }

            Spacer(minLength: AppSpacing.sm)

            Toggle(isOn: $viewModel.followLatestCapture) {
                Label("Seguir última captura", systemImage: "bolt.horizontal.circle")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Saltar automáticamente a cada nueva foto recibida")
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: AppSpacing.bottomControlBarHeight)
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle()
                .frame(height: AppSpacing.hairline)
                .foregroundStyle(AppColors.borderSubtle),
            alignment: .top
        )
    }
}
