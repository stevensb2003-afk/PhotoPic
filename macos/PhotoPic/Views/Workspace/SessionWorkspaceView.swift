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
                onDetachWatchFolder: { appState.detachWatchFolder() },
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
            } else if let unmounted = appState.discoveryService.unmountedPhysicalDevices.first {
                UnmountedUSBTopBanner(device: unmounted) {
                    appState.openSettings(tab: .devices)
                }
            }

            if let primary = appState.discoveryService.primaryLiveDevice {
                DynamicDeviceStatusBanner(
                    device: primary,
                    onRetry: { appState.discoveryService.connectDevice(fingerprint: primary.fingerprint) },
                    onReleaseMacOSLock: { appState.discoveryService.releaseMacOSPTPCameraLock(for: primary.fingerprint) }
                )
            }

            workspaceSubHeader

            if viewModel.activeTab == .cullPending && (!viewModel.pendingItems.isEmpty || !viewModel.availablePendingTags.isEmpty) {
                VisionTagFilterStrip(
                    availableTags: viewModel.availablePendingTags,
                    selectedTag: $viewModel.selectedTagFilter,
                    totalPendingCount: viewModel.pendingItems.count,
                    isAnalyzing: viewModel.isAnalyzingVision,
                    analyzedCount: viewModel.visionCompletedCount,
                    totalAnalyzeCount: viewModel.visionTotalCount,
                    hasUnanalyzedItems: viewModel.pendingItems.contains { $0.visionTags == nil },
                    onTriggerManualAnalysis: { viewModel.runManualVisionAnalysisBatch() }
                )
            }

            Group {
                switch viewModel.activeTab {
                case .cullPending:
                    VStack(spacing: 0) {
                        TinderCardStackView(viewModel: viewModel)
                        CullingControlsBar(viewModel: viewModel)
                    }
                case .liveView:
                    LiveViewWorkspacePane(appState: appState, viewModel: viewModel)
                case .forEditing:
                    SelectedPhotosView(viewModel: viewModel)
                case .archived:
                    ArchivedPhotosView(viewModel: viewModel)
                }
            }
        }
        .background(AppColors.stageBackground)
        .onAppear {
            installKeyMonitor()
            viewModel.syncTimerTicker()
        }
        .onDisappear {
            removeKeyMonitor()
            viewModel.cancelTimerTicker()
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
            let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
            guard event.modifierFlags.intersection(blockedModifiers).isEmpty else {
                return event
            }
            let keyCode = event.keyCode
            let handled = MainActor.assumeIsolated {
                guard !appState.isPresentingSettings,
                      !appState.isPresentingHelp,
                      NSApp.keyWindow?.sheets.isEmpty != false,
                      !(NSApp.keyWindow?.firstResponder is NSTextView) else {
                    return false
                }

                switch viewModel.activeTab {
                case .cullPending:
                    switch keyCode {
                    case 123: // Left Arrow -> Archivar (animado)
                        viewModel.requestAnimatedArchive()
                        return true
                    case 124: // Right Arrow -> Para Edición (animado)
                        viewModel.requestAnimatedApprove()
                        return true
                    case 126: // Up Arrow -> Anterior
                        viewModel.navigatePrevious()
                        return true
                    case 125: // Down Arrow -> Siguiente
                        viewModel.navigateNext()
                        return true
                    case 49:  // Space -> Zoom 1:1
                        viewModel.toggleLockedOneToOneZoom()
                        return true
                    case 53:  // Escape -> Salir de Zoom 1:1
                        if viewModel.isAnyZoomActive {
                            viewModel.resetZoomState()
                            return true
                        }
                        return false
                    default:
                        return false
                    }
                case .forEditing:
                    switch keyCode {
                    case 126: // Up Arrow -> Anterior
                        viewModel.stepEditingSelection(delta: -1)
                        return true
                    case 125: // Down Arrow -> Siguiente
                        viewModel.stepEditingSelection(delta: 1)
                        return true
                    case 123: // Left Arrow -> Mover a Archivadas
                        if let selected = viewModel.selectedEditingItem {
                            viewModel.moveEditingItemToArchived(selected)
                            return true
                        }
                        return false
                    default:
                        return false
                    }
                case .archived:
                    switch keyCode {
                    case 126: // Up Arrow -> Anterior
                        viewModel.stepArchivedSelection(delta: -1)
                        return true
                    case 125: // Down Arrow -> Siguiente
                        viewModel.stepArchivedSelection(delta: 1)
                        return true
                    default:
                        return false
                    }
                case .liveView:
                    return false
                }
            }
            return handled ? nil : event
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
                    badgeColor: AppColors.warningAmber,
                    helpText: "Revisar y filtrar fotos pendientes"
                )
                tabButton(
                    tab: .liveView,
                    count: nil,
                    badgeColor: AppColors.approveGreen,
                    liveActive: appState.liveViewService.isRunning
                        || appState.ptpLiveViewService.isStreaming
                        || appState.discoveryService.directCanonService.isDirectLiveViewStreaming
                        || appState.networkStreamService.isStreaming
                        || appState.gphotoBridge.isStreaming,
                    helpText: "Transmisión en vivo y controles de cámara"
                )
                tabButton(
                    tab: .forEditing,
                    count: viewModel.session.counts.forEditing,
                    badgeColor: AppColors.approveGreen,
                    helpText: "Ver fotos seleccionadas para edición"
                )
                tabButton(
                    tab: .archived,
                    count: viewModel.session.counts.archived,
                    badgeColor: AppColors.archiveRed,
                    helpText: "Revisar fotos descartadas o recuperarlas"
                )
            }

            Spacer()

            HStack(spacing: AppSpacing.sm) {
                SessionTimerPillView(viewModel: viewModel)

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

                Button {
                    viewModel.activeTab = .forEditing
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Circle()
                            .fill(AppColors.approveGreen)
                            .frame(width: 7, height: 7)
                        Text("Seleccionadas:")
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
                .buttonStyle(.plain)
                .help("Abrir módulo de fotos seleccionadas")
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

    private func tabButton(
        tab: WorkspaceTab,
        count: Int?,
        badgeColor: Color,
        liveActive: Bool = false,
        helpText: String
    ) -> some View {
        WorkspaceTabPillButton(
            tab: tab,
            count: count,
            badgeColor: badgeColor,
            liveActive: liveActive,
            isActive: viewModel.activeTab == tab,
            helpText: helpText
        ) {
            viewModel.activeTab = tab
        }
    }
}

private struct WorkspaceTabPillButton: View {
    let tab: WorkspaceTab
    let count: Int?
    let badgeColor: Color
    let liveActive: Bool
    let isActive: Bool
    let helpText: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                if tab == .liveView {
                    PulsingStatusDot(color: liveActive ? AppColors.approveGreen : AppColors.textTertiary, isActive: liveActive)
                }
                Text(tab.title)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(isActive || isHovered ? AppColors.textPrimary : AppColors.textSecondary)

                if let count {
                    Text("\(count)")
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(isActive ? badgeColor : AppColors.textTertiary)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(AppColors.stageBackground)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(isActive ? AppColors.elevatedSurface : (isHovered ? AppColors.panelSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(isActive ? AppColors.borderStrong : (isHovered ? AppColors.borderSubtle : Color.clear), lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }
}
