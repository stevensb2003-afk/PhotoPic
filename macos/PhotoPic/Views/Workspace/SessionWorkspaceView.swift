import AppKit
import SwiftUI

/// Screen 3: Real-time Tinder culling workspace with top tabs (`Filtrar (Pendientes)` | `Archivadas`),
/// live `Para Edición` counter, and bulletproof AppKit keyboard shortcut monitoring.
package struct SessionWorkspaceView: View {
    @Bindable var appState: AppState
    @Bindable var viewModel: CullingSessionViewModel
    @State private var keyMonitor: Any?

    package init(appState: AppState, viewModel: CullingSessionViewModel) {
        self.appState = appState
        self.viewModel = viewModel
    }

    package var body: some View {
        VStack(spacing: 0) {
            TopDeviceStatusBar(
                primaryDevice: appState.discoveryService.primaryLiveDevice,
                leadingTitle: viewModel.session.name,
                leadingSubtitle: viewModel.session.directoryURL.path,
                watchedFolderName: appState.folderWatchService.watchedFolderURL?.lastPathComponent,
                onBackAction: { appState.closeActiveSession() },
                onTapWatchFolder: { appState.attachWatchFolderFromPicker() },
                onTapDevicePill: { appState.openSettings(tab: .devices) },
                onTapSettings: { appState.openSettings(tab: .general) },
                onTapHelp: { appState.isPresentingHelp = true }
            )

            if let unknown = appState.discoveryService.unknownDeviceBanner {
                UnknownDeviceTopBanner(
                    device: unknown,
                    onConnectAndSave: { appState.discoveryService.connectAndSaveDevice(fingerprint: unknown.fingerprint) },
                    onDismiss: { appState.discoveryService.dismissUnknownBanner() }
                )
            }

            workspaceSubHeader

            if viewModel.activeTab == .cullPending && (viewModel.autoTagOnIngest || !viewModel.availablePendingTags.isEmpty) {
                VisionTagFilterStrip(
                    availableTags: viewModel.availablePendingTags,
                    selectedTag: $viewModel.selectedTagFilter,
                    totalPendingCount: viewModel.pendingItems.count,
                    isAnalyzing: viewModel.isAnalyzingVision
                )
            }

            Group {
                switch viewModel.activeTab {
                case .cullPending:
                    VStack(spacing: 0) {
                        TinderCardStackView(viewModel: viewModel)
                        CullingControlsBar(viewModel: viewModel)
                    }
                case .archived:
                    ArchivedPhotosView(viewModel: viewModel)
                }
            }
        }
        .background(AppColors.stageBackground)
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .background(
            Button("") {
                viewModel.undoLastMove()
            }
            .keyboardShortcut("z", modifiers: .command)
            .hidden()
        )
        .alert("Error de archivo", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Entendido", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !appState.isPresentingSettings,
                  viewModel.activeTab == .cullPending,
                  NSApp.keyWindow?.sheets.isEmpty != false,
                  !(NSApp.keyWindow?.firstResponder is NSTextView) else {
                return event
            }

            let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
            if !event.modifierFlags.intersection(blockedModifiers).isEmpty {
                return event
            }

            switch event.keyCode {
            case 123: // Left Arrow -> Archivar
                viewModel.archiveCurrent()
                return nil
            case 124: // Right Arrow -> Para Edición
                viewModel.approveCurrentToEditing()
                return nil
            case 126: // Up Arrow -> Anterior
                viewModel.navigatePrevious()
                return nil
            case 125: // Down Arrow -> Siguiente
                viewModel.navigateNext()
                return nil
            case 49:  // Space -> Zoom 1:1
                viewModel.toggleLockedOneToOneZoom()
                return nil
            case 53:  // Escape -> Salir de Zoom 1:1
                if viewModel.isAnyZoomActive {
                    viewModel.resetZoomState()
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private var workspaceSubHeader: some View {
        HStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.xs) {
                tabButton(
                    tab: .cullPending,
                    count: viewModel.session.counts.pending,
                    badgeColor: AppColors.warningAmber
                )
                tabButton(
                    tab: .archived,
                    count: viewModel.session.counts.archived,
                    badgeColor: AppColors.archiveRed
                )
            }

            Spacer()

            HStack(spacing: AppSpacing.sm) {
                if viewModel.session.counts.companionJpgs > 0 {
                    HStack(spacing: AppSpacing.xs) {
                        Text("JPG Separados:")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                        Text("\(viewModel.session.counts.companionJpgs)")
                            .font(AppTypography.monoCaption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppColors.elevatedSurface)
                    .clipShape(Capsule())
                }

                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(AppColors.approveGreen)
                        .frame(width: 7, height: 7)
                    Text("Para Edición:")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textSecondary)
                    Text("\(viewModel.session.counts.forEditing)")
                        .font(AppTypography.monoCounter)
                        .foregroundStyle(AppColors.approveGreen)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.approveGreenTint)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.approveGreen.opacity(0.35), lineWidth: AppSpacing.hairline)
                )
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.windowCanvas)
        .overlay(
            Rectangle()
                .frame(height: AppSpacing.hairline)
                .foregroundStyle(AppColors.borderSubtle),
            alignment: .bottom
        )
    }

    private func tabButton(tab: WorkspaceTab, count: Int, badgeColor: Color) -> some View {
        let isActive = viewModel.activeTab == tab
        return Button {
            viewModel.activeTab = tab
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(tab.title)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary)

                Text("\(count)")
                    .font(AppTypography.monoMicro)
                    .foregroundStyle(isActive ? badgeColor : AppColors.textTertiary)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 2)
                    .background(AppColors.stageBackground)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(isActive ? AppColors.elevatedSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(isActive ? AppColors.borderStrong : Color.clear, lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}
