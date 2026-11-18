import SwiftUI

/// Screen 2: Home & Session Manager with persistent USB bar, Master Groups, search/tag filters,
/// New Session sheet, and permanent project deletion confirmation.
package struct HomeDashboardView: View {
    @Bindable var appState: AppState

    package init(appState: AppState) {
        self.appState = appState
    }

    package var body: some View {
        VStack(spacing: 0) {
            TopDeviceStatusBar(
                primaryDevice: appState.discoveryService.primaryLiveDevice,
                leadingTitle: "PhotoPic",
                leadingSubtitle: appState.rootFolderURL?.path,
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

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    headerActionsSection
                    sessionsHistorySection
                }
                .padding(AppSpacing.xl)
            }
        }
        .background(AppColors.windowCanvas)
        .sheet(isPresented: Binding(
            get: { appState.homeViewModel.isPresentingNewSessionSheet },
            set: { appState.homeViewModel.isPresentingNewSessionSheet = $0 }
        )) {
            NewSessionSheet(
                sessionName: Binding(
                    get: { appState.homeViewModel.newSessionNameDraft },
                    set: { appState.homeViewModel.newSessionNameDraft = $0 }
                ),
                selectedGroup: Binding(
                    get: { appState.homeViewModel.newSessionGroupDraft },
                    set: { appState.homeViewModel.newSessionGroupDraft = $0 }
                ),
                tagsDraft: Binding(
                    get: { appState.homeViewModel.newSessionTagsDraft },
                    set: { appState.homeViewModel.newSessionTagsDraft = $0 }
                ),
                availableGroups: appState.homeViewModel.masterGroups,
                rootFolderURL: appState.rootFolderURL,
                errorMessage: appState.homeViewModel.errorMessage,
                onCancel: { appState.homeViewModel.isPresentingNewSessionSheet = false },
                onCreate: { name, groupName, rawTags in
                    appState.createAndOpenSession(named: name, groupName: groupName, rawTags: rawTags)
                }
            )
        }
        .sheet(item: Binding(
            get: { appState.homeViewModel.sessionPendingDeletion },
            set: { appState.homeViewModel.sessionPendingDeletion = $0 }
        )) { pendingSession in
            DeleteSessionConfirmationSheet(
                session: pendingSession,
                onCancel: { appState.homeViewModel.sessionPendingDeletion = nil },
                onConfirmPermanentDelete: {
                    appState.deleteSessionPermanently(pendingSession)
                }
            )
        }
    }

    private var headerActionsSection: some View {
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Sesiones de Estudio")
                    .font(AppTypography.displayTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Creá una sesión o carpeta máster para organizar clientes, etiquetas y disparos en vivo.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button {
                appState.homeViewModel.reloadSessions(in: appState.rootFolderURL)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(StudioButtonStyle(.secondaryDark))
            .help("Actualizar contadores desde disco")

            Button {
                appState.homeViewModel.prepareNewSessionSheet()
            } label: {
                Label("Nueva Sesión de Filtrado", systemImage: "plus")
            }
            .buttonStyle(StudioButtonStyle(.primaryLight))
        }
    }

    @ViewBuilder
    private var sessionsHistorySection: some View {
        let vm = appState.homeViewModel
        let visibleSessions = vm.filteredSessions

        if vm.sessions.isEmpty && vm.masterGroups.isEmpty {
            emptySessionsState
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HomeFilterAndGroupBar(
                    searchQuery: Binding(get: { vm.searchQuery }, set: { vm.searchQuery = $0 }),
                    groupFilter: Binding(get: { vm.groupFilter }, set: { vm.groupFilter = $0 }),
                    selectedTagFilter: Binding(get: { vm.selectedTagFilter }, set: { vm.selectedTagFilter = $0 }),
                    masterGroups: vm.masterGroups,
                    availableTags: vm.availableProjectTags,
                    totalSessionCount: vm.sessions.count,
                    hasUngroupedSessions: vm.hasUngroupedSessions,
                    groupSessionCount: { group in
                        vm.sessions.filter { $0.groupName?.caseInsensitiveCompare(group) == .orderedSame }.count
                    },
                    onCreateMasterGroup: { groupName in
                        guard let root = appState.rootFolderURL else { return }
                        if let created = vm.createMasterGroup(named: groupName, in: root) {
                            vm.groupFilter = .group(created)
                        }
                    }
                )

                HStack {
                    Text("Historial en Carpeta Raíz")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(visibleSessions.count) de \(vm.sessions.count) sesiones")
                        .font(AppTypography.monoCaption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                if visibleSessions.isEmpty {
                    filteredEmptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: AppSpacing.cardGridMinWidth), spacing: AppSpacing.md)],
                        spacing: AppSpacing.md
                    ) {
                        ForEach(visibleSessions) { session in
                            SessionCardView(
                                session: session,
                                availableGroups: vm.masterGroups,
                                onOpen: { appState.openSession(session) },
                                onAddTag: { tag in vm.addTag(tag, to: session) },
                                onRemoveTag: { tag in vm.removeTag(tag, from: session) },
                                onMoveToGroup: { targetGroup in
                                    guard let root = appState.rootFolderURL else { return }
                                    vm.moveSession(session, toGroup: targetGroup, in: root)
                                },
                                onRequestDelete: { vm.sessionPendingDeletion = session }
                            )
                        }
                    }
                }
            }
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("Ninguna sesión coincide con los filtros actuales")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
            Button("Limpiar búsqueda y filtros") {
                appState.homeViewModel.searchQuery = ""
                appState.homeViewModel.groupFilter = .all
                appState.homeViewModel.selectedTagFilter = nil
            }
            .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
        }
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }

    private var emptySessionsState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "photo.stack")
                .font(AppTypography.displayTitle)
                .foregroundStyle(AppColors.textTertiary)

            Text("Todavía no hay sesiones en tu Carpeta Raíz")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("Hacé clic en \"Nueva Sesión de Filtrado\" para crear las carpetas RAW, JPG, Para_Edicion y Archivadas y empezar a disparar.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Button {
                appState.homeViewModel.prepareNewSessionSheet()
            } label: {
                Label("Nueva Sesión de Filtrado", systemImage: "plus")
            }
            .buttonStyle(StudioButtonStyle(.primaryLight))
            .padding(.top, AppSpacing.xs)
        }
        .padding(.vertical, AppSpacing.xxxl)
        .frame(maxWidth: .infinity)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }
}
