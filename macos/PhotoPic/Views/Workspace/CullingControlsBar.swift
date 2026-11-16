import SwiftUI

/// Bottom culling control deck with free queue navigation, physical Swipe actions,
/// Undo (`⌘Z`), 1:1 Zoom toggle, and "Seguir última captura".
package struct CullingControlsBar: View {
    @Bindable var viewModel: CullingSessionViewModel

    package init(viewModel: CullingSessionViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Free navigation without moving files
            HStack(spacing: AppSpacing.xs) {
                Button {
                    viewModel.navigatePrevious()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        KeycapBadge("↑")
                        Text("Anterior")
                    }
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .disabled(viewModel.currentIndex <= 0 || viewModel.pendingItems.isEmpty)

                Button {
                    viewModel.navigateNext()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        KeycapBadge("↓")
                        Text("Siguiente")
                    }
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .disabled(viewModel.currentIndex + 1 >= viewModel.visiblePendingItems.count)
            }

            Divider()
                .frame(height: 22)
                .overlay(AppColors.borderSubtle)

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

            Spacer()

            // Physical disk culling decisions
            HStack(spacing: AppSpacing.sm) {
                Button {
                    viewModel.undoLastMove()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Deshacer")
                        KeycapBadge("⌘Z")
                    }
                }
                .buttonStyle(StudioButtonStyle(.ghost, compact: true))
                .disabled(!viewModel.canUndo)

                Button {
                    viewModel.archiveCurrent()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        KeycapBadge("←")
                        Text("Archivar")
                    }
                }
                .buttonStyle(StudioButtonStyle(.archiveCoral))
                .disabled(viewModel.currentPendingItem == nil)

                Button {
                    viewModel.approveCurrentToEditing()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text("Para Edición")
                        KeycapBadge("→")
                    }
                }
                .buttonStyle(StudioButtonStyle(.approveEmerald))
                .disabled(viewModel.currentPendingItem == nil)
            }

            Spacer()

            Toggle(isOn: $viewModel.followLatestCapture) {
                Label("Seguir última captura", systemImage: "bolt.horizontal.circle")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
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
