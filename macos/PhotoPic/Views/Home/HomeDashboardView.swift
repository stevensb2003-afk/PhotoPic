import SwiftUI

/// Screen 2: Home & Session Manager with persistent USB bar, Master Groups, search/tag filters,
/// New Session sheet, and permanent project deletion confirmation.
package struct HomeDashboardView: View {
    @Bindable var appState: AppState

    @State private var isPresentingGroupRenamePopover = false

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
        .sheet(isPresented: Binding(
            get: { appState.homeViewModel.isPresentingImportSheet },
            set: { newValue in
                if !newValue { appState.homeViewModel.cancelImportSheet() }
            }
        )) {
            ImportSessionSheet(
                sessionName: Binding(
                    get: { appState.homeViewModel.importSessionNameDraft },
                    set: { appState.homeViewModel.importSessionNameDraft = $0 }
                ),
                selectedGroup: Binding(
                    get: { appState.homeViewModel.importSessionGroupDraft },
                    set: { appState.homeViewModel.importSessionGroupDraft = $0 }
                ),
                tagsDraft: Binding(
                    get: { appState.homeViewModel.importSessionTagsDraft },
                    set: { appState.homeViewModel.importSessionTagsDraft = $0 }
                ),
                includeSubfolders: Binding(
                    get: { appState.homeViewModel.importIncludeSubfolders },
                    set: { appState.homeViewModel.importIncludeSubfolders = $0 }
                ),
                transferMode: Binding(
                    get: { appState.homeViewModel.importTransferMode },
                    set: { appState.homeViewModel.importTransferMode = $0 }
                ),
                runVisionAIOnOpen: Binding(
                    get: { appState.homeViewModel.importRunVisionAIOnOpen },
                    set: { appState.homeViewModel.importRunVisionAIOnOpen = $0 }
                ),
                scanSummary: appState.homeViewModel.importSourceSummary,
                availableGroups: appState.homeViewModel.masterGroups,
                rootFolderURL: appState.rootFolderURL,
                isScanning: appState.homeViewModel.isScanningImportFolder,
                isImporting: appState.homeViewModel.isImportingFolder,
                progress: appState.homeViewModel.importProgress,
                errorMessage: appState.homeViewModel.importErrorMessage,
                onChangeSourceFolder: { appState.repickImportSourceFolder() },
                onRescan: { sourceURL, includeSub in
                    appState.homeViewModel.scanImportFolder(at: sourceURL, includeSubfolders: includeSub)
                },
                onCancel: { appState.homeViewModel.cancelImportSheet() },
                onConfirmImport: { name, groupName, rawTags in
                    appState.executeImportSession(named: name, groupName: groupName, rawTags: rawTags)
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
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(AppColors.elevatedSurface)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
                        )
                    Image(systemName: "camera.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Sesiones de Fotografía")
                        .font(AppTypography.displayTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Organizá tus sesiones, grupos y capturas en vivo.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            Button {
                appState.homeViewModel.reloadSessions(in: appState.rootFolderURL)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(StudioButtonStyle(.secondaryDark))
            .help("Actualizar sesiones desde el disco")

            Button {
                appState.presentImportSessionFolderPicker()
            } label: {
                Label("Importar carpeta", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(StudioButtonStyle(.secondaryDark))
            .help("Importar fotos desde una carpeta de tu Mac y segregar RAW/JPG (⌘I)")

            Button("Nueva sesión") {
                appState.homeViewModel.prepareNewSessionSheet()
            }
            .buttonStyle(StudioButtonStyle(.primaryLight))
            .help("Crear nueva sesión de fotografía (⌘N)")
        }
    }

    @ViewBuilder
    private var sessionsHistorySection: some View {
        let vm = appState.homeViewModel
        let visibleSessions = vm.filteredSessions
        let isSearchingOrTagFiltering = !vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.selectedTagFilter != nil

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

                if case .group(let activeGroup) = vm.groupFilter {
                    groupDetailHeader(group: activeGroup, sessionCount: visibleSessions.count, vm: vm)

                    if visibleSessions.isEmpty && !isSearchingOrTagFiltering {
                        emptyGroupState(group: activeGroup, vm: vm)
                    } else if visibleSessions.isEmpty {
                        filteredEmptyState
                    } else {
                        sessionGrid(visibleSessions, vm: vm, showGroupBadge: false)
                    }
                } else if vm.groupFilter == .all && !isSearchingOrTagFiltering {
                    if !vm.masterGroups.isEmpty {
                        HStack {
                            Text("Grupos")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text("\(vm.masterGroups.count) grupo(s)")
                                .font(AppTypography.monoCaption)
                                .foregroundStyle(AppColors.textTertiary)
                        }

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: AppSpacing.cardGridMinWidth), spacing: AppSpacing.md)],
                            spacing: AppSpacing.md
                        ) {
                            ForEach(vm.masterGroups, id: \.self) { group in
                                let count = vm.sessions.filter { $0.groupName?.caseInsensitiveCompare(group) == .orderedSame }.count
                                GroupCardView(
                                    groupName: group,
                                    sessionCount: count,
                                    onOpen: { vm.groupFilter = .group(group) },
                                    onRename: { newName in
                                        guard let root = appState.rootFolderURL else { return }
                                        if let renamed = vm.renameMasterGroup(named: group, to: newName, in: root) {
                                            appState.showTransientNotice("Grupo renombrado a \"\(renamed)\"")
                                        }
                                    }
                                )
                            }
                        }
                    }

                    let rootSessions = vm.masterGroups.isEmpty ? visibleSessions : visibleSessions.filter { $0.groupName == nil }
                    if !rootSessions.isEmpty || vm.masterGroups.isEmpty {
                        HStack {
                            Text(vm.masterGroups.isEmpty ? "Sesiones" : "Sesiones sin grupo")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text("\(rootSessions.count)")
                                .font(AppTypography.monoCaption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(.top, vm.masterGroups.isEmpty ? 0 : AppSpacing.sm)

                        if rootSessions.isEmpty {
                            filteredEmptyState
                        } else {
                            sessionGrid(rootSessions, vm: vm)
                        }
                    }
                } else {
                    HStack {
                        Text("Resultados")
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
                        sessionGrid(visibleSessions, vm: vm)
                    }
                }
            }
        }
    }

    private func groupDetailHeader(group: String, sessionCount: Int, vm: HomeViewModel) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                vm.groupFilter = .all
            } label: {
                Label("Regresar", systemImage: "chevron.left")
            }
            .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            .help("Volver a todos los grupos y sesiones")

            Image(systemName: "rectangle.stack.fill")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.infoBlue)

            Text(group)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Button {
                isPresentingGroupRenamePopover = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(StudioButtonStyle(.ghost, compact: true))
            .help("Renombrar este grupo y su carpeta en Finder")
            .popover(isPresented: $isPresentingGroupRenamePopover, arrowEdge: .bottom) {
                RenameFolderPopover(
                    title: "Renombrar grupo",
                    subtitle: "También renombra la carpeta del grupo en Finder.",
                    currentName: group,
                    placeholder: "Ej. Bodas 2026",
                    onCancel: { isPresentingGroupRenamePopover = false },
                    onConfirm: { newName in
                        isPresentingGroupRenamePopover = false
                        guard let root = appState.rootFolderURL else { return }
                        if let renamed = vm.renameMasterGroup(named: group, to: newName, in: root) {
                            appState.showTransientNotice("Grupo renombrado a \"\(renamed)\"")
                        }
                    }
                )
            }

            Spacer()

            Text("\(sessionCount) sesión(es)")
                .font(AppTypography.monoCaption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func sessionGrid(_ items: [PhotoSession], vm: HomeViewModel, showGroupBadge: Bool = true) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: AppSpacing.cardGridMinWidth), spacing: AppSpacing.md)],
            spacing: AppSpacing.md
        ) {
            ForEach(items) { session in
                SessionCardView(
                    session: session,
                    availableGroups: vm.masterGroups,
                    showGroupBadge: showGroupBadge,
                    onOpen: { appState.openSession(session) },
                    onRename: { newName in
                        guard let root = appState.rootFolderURL else { return }
                        if let renamed = vm.renameSession(session, to: newName, in: root) {
                            appState.showTransientNotice("Sesión renombrada a \"\(renamed.name)\"")
                        }
                    },
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

    private func emptyGroupState(group: String, vm: HomeViewModel) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Text("El grupo \"\(group)\" todavía no tiene sesiones")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
            HStack(spacing: AppSpacing.sm) {
                Button {
                    appState.presentImportSessionFolderPicker()
                } label: {
                    Label("Importar carpeta", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help("Importar una carpeta existente dentro de este grupo (⌘I)")

                Button("Nueva sesión") {
                    vm.prepareNewSessionSheet()
                }
                .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                .help("Crear una sesión dentro del grupo \(group)")
            }
        }
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
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
            PhotoPicBrandLogo(size: 56)

            Text("Todavía no hay sesiones")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("Creá una sesión vacía para disparos en vivo o importá una carpeta existente de tu Mac para organizar RAW y detectar rostros.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            HStack(spacing: AppSpacing.md) {
                Button {
                    appState.presentImportSessionFolderPicker()
                } label: {
                    Label("Importar carpeta", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark))
                .help("Importar una carpeta existente de tu Mac (⌘I)")

                Button("Nueva sesión") {
                    appState.homeViewModel.prepareNewSessionSheet()
                }
                .buttonStyle(StudioButtonStyle(.primaryLight))
                .help("Crear nueva sesión de fotografía (⌘N)")
            }
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

private struct GroupCardView: View {
    let groupName: String
    let sessionCount: Int
    let onOpen: () -> Void
    let onRename: (String) -> Void

    @State private var isHovering = false
    @State private var isRenameHovered = false
    @State private var isPresentingRenamePopover = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onOpen) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.infoBlue)
                        .frame(width: 38, height: 38)
                        .background(AppColors.infoBlueTint)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(groupName)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Text(sessionCount == 1 ? "1 sesión" : "\(sessionCount) sesiones")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()
                }
                .padding(.trailing, 54)
                .padding(AppSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovering ? AppColors.elevatedSurface : AppColors.panelSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(isHovering ? AppColors.infoBlue.opacity(0.45) : AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
                )
            }
            .buttonStyle(.plain)
            .help("Entrar al grupo \(groupName)")

            HStack(spacing: AppSpacing.xs) {
                Button {
                    isPresentingRenamePopover.toggle()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isRenameHovered ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(isRenameHovered ? AppColors.controlHover : AppColors.stageBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isRenameHovered = $0 }
                .help("Renombrar grupo y su carpeta en Finder")
                .popover(isPresented: $isPresentingRenamePopover, arrowEdge: .bottom) {
                    RenameFolderPopover(
                        title: "Renombrar grupo",
                        subtitle: "También renombra la carpeta del grupo en Finder.",
                        currentName: groupName,
                        placeholder: "Ej. Bodas 2026",
                        onCancel: { isPresentingRenamePopover = false },
                        onConfirm: { newName in
                            isPresentingRenamePopover = false
                            onRename(newName)
                        }
                    )
                }

                Image(systemName: "chevron.right")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(isHovering ? AppColors.textPrimary : AppColors.textTertiary)
            }
            .padding(.trailing, AppSpacing.lg)
        }
        .onHover { hovering in
            withAnimation(AppMotion.quickEaseOut) {
                isHovering = hovering
            }
        }
    }
}
