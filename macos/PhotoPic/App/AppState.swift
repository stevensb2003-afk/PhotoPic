import AppKit
import Foundation
import Observation

/// Active tab inside the Settings & Device Manager modal sheet.
package enum SettingsTab: String, CaseIterable, Sendable {
    case devices
    case general

    package var title: String {
        switch self {
        case .devices: return "Dispositivos"
        case .general: return "General y Rendimiento"
        }
    }
}

/// Root `@MainActor @Observable` coordinator wiring persistence, USB tethering,
/// session management, and global navigation state.
@MainActor
@Observable
package final class AppState {
    package let bookmarkManager: BookmarkManager
    package let knownDevicesStore: KnownDevicesStore
    package let discoveryService: DeviceDiscoveryService
    package let folderWatchService: FolderWatchTetherService
    package let liveViewService: LiveViewCameraService
    package let ptpLiveViewService = PTPLiveViewService()
    package let gphotoBridge: GPhoto2LiveBridge
    package let networkStreamService = NetworkMJPEGStreamService()
    package let cloudUpdater: CloudUpdateService
    package let rawRenderer: RawImageRenderer
    package let visionAnalyzer: PhotoVisionAnalyzer
    package let homeViewModel: HomeViewModel
    package let deviceManagerViewModel: DeviceManagerViewModel
    private let performanceStore: PerformancePreferencesStore

    package private(set) var hardwareAudit: HardwareAuditReport
    package var performancePrefs: PerformancePreferences {
        didSet {
            performanceStore.save(performancePrefs)
            activeSessionViewModel?.applyPerformancePreferences(performancePrefs)
            cloudUpdater.autoCheckEnabled = performancePrefs.autoCheckForUpdates
            cloudUpdater.autoDownloadEnabled = performancePrefs.autoDownloadUpdates
            if performancePrefs.autoCheckForUpdates {
                cloudUpdater.startAutomaticLifecycle()
            } else {
                cloudUpdater.stopAutomaticLifecycle()
            }
        }
    }
    package private(set) var rootFolderURL: URL?
    package private(set) var activeSessionViewModel: CullingSessionViewModel?
    package var isPresentingSettings: Bool = false
    package var isPresentingHelp: Bool = false
    package var settingsTab: SettingsTab = .devices
    package var globalNoticeBanner: String?

    private var toastClearTask: Task<Void, Never>?

    package init(
        bookmarkManager: BookmarkManager = BookmarkManager(),
        knownDevicesStore: KnownDevicesStore = KnownDevicesStore(),
        performanceStore: PerformancePreferencesStore? = nil,
        startDeviceBrowser: Bool = true
    ) {
        self.bookmarkManager = bookmarkManager
        self.knownDevicesStore = knownDevicesStore
        let resolvedPerfStore = performanceStore ?? PerformancePreferencesStore()
        self.performanceStore = resolvedPerfStore
        let audit = HardwareCapabilityAuditor.auditCurrentMac()
        self.hardwareAudit = audit
        let loadedPrefs = resolvedPerfStore.loadOrSeed(from: audit)
        self.performancePrefs = loadedPrefs
        self.cloudUpdater = CloudUpdateService(
            autoCheckEnabled: loadedPrefs.autoCheckForUpdates,
            autoDownloadEnabled: loadedPrefs.autoDownloadUpdates
        )

        let capture = TetherCaptureService()
        let discovery = DeviceDiscoveryService(knownStore: knownDevicesStore, captureService: capture)
        self.discoveryService = discovery
        self.folderWatchService = FolderWatchTetherService()
        self.liveViewService = LiveViewCameraService()
        self.gphotoBridge = GPhoto2LiveBridge()
        self.rawRenderer = RawImageRenderer()
        self.visionAnalyzer = PhotoVisionAnalyzer()
        self.homeViewModel = HomeViewModel()
        self.deviceManagerViewModel = DeviceManagerViewModel(discoveryService: discovery)

        self.rootFolderURL = bookmarkManager.resolveRootFolderURL()
        if let rootFolderURL {
            homeViewModel.reloadSessions(in: rootFolderURL)
        }

        wireCapturePipeline()
        if startDeviceBrowser {
            discovery.startBrowsing()
            cloudUpdater.startAutomaticLifecycle()
        }
    }

    package var needsOnboarding: Bool {
        rootFolderURL == nil
    }

    package func pickAndSetRootFolder() {
        guard let picked = bookmarkManager.presentRootFolderPicker() else { return }
        setRootFolderURL(picked)
    }

    package func setRootFolderURL(_ url: URL) {
        bookmarkManager.saveBookmark(for: url)
        rootFolderURL = url
        if !performancePrefs.hasCompletedGuidedSetup {
            performancePrefs.hasCompletedGuidedSetup = true
        }
        homeViewModel.reloadSessions(in: url)
    }

    package func updatePerformancePreferences(_ updated: PerformancePreferences) {
        performancePrefs = updated
    }

    package func selectPerformanceTier(_ tier: PerformanceTier) {
        performancePrefs = PerformancePreferences.preset(
            for: tier,
            completedSetup: performancePrefs.hasCompletedGuidedSetup,
            autoStartTimer: performancePrefs.autoStartSessionTimerOnFirstShot,
            autoCheckUpdates: performancePrefs.autoCheckForUpdates,
            autoDownloadUpdates: performancePrefs.autoDownloadUpdates
        )
    }

    package func reAuditAndApplyRecommendedProfile() {
        let freshAudit = HardwareCapabilityAuditor.auditCurrentMac()
        hardwareAudit = freshAudit
        performancePrefs = PerformancePreferences.preset(
            for: freshAudit.recommendedTier,
            completedSetup: performancePrefs.hasCompletedGuidedSetup,
            autoStartTimer: performancePrefs.autoStartSessionTimerOnFirstShot,
            autoCheckUpdates: performancePrefs.autoCheckForUpdates,
            autoDownloadUpdates: performancePrefs.autoDownloadUpdates
        )
        showTransientNotice("Auditoría completada: \(freshAudit.recommendedTier.shortBadge)")
    }

    package func createAndOpenSession(
        named name: String,
        groupName: String? = nil,
        rawTags: String = ""
    ) {
        guard let rootFolderURL else { return }
        if let created = homeViewModel.createSession(
            named: name,
            groupName: groupName,
            rawTags: rawTags,
            in: rootFolderURL
        ) {
            openSession(created)
        }
    }

    package func presentImportSessionFolderPicker() {
        guard let chosenURL = pickSourceFolderPanel(
            title: "Importar carpeta de fotos",
            message: "Elegí una carpeta de tu Mac para organizar RAW, JPG o HEIC como nueva sesión"
        ) else {
            return
        }
        homeViewModel.prepareImportSheet(for: chosenURL)
    }

    package func repickImportSourceFolder() {
        guard !homeViewModel.isImportingFolder,
              let chosenURL = pickSourceFolderPanel(
                  title: "Cambiar carpeta origen",
                  message: "Elegí la carpeta de fotos que querés importar a PhotoPic"
              ) else {
            return
        }
        let suggested = SessionFileManager.sanitizeSessionName(chosenURL.lastPathComponent)
        if !suggested.isEmpty {
            homeViewModel.importSessionNameDraft = suggested
        }
        homeViewModel.scanImportFolder(at: chosenURL, includeSubfolders: homeViewModel.importIncludeSubfolders)
    }

    package func executeImportSession(
        named name: String,
        groupName: String?,
        rawTags: String
    ) {
        guard !homeViewModel.isImportingFolder,
              let rootFolderURL,
              let summary = homeViewModel.importSourceSummary,
              !summary.units.isEmpty else {
            return
        }

        let parsedTags = SessionMetadata.parseCommaSeparatedTags(rawTags)
        let transferMode = homeViewModel.importTransferMode
        let runVisionAI = homeViewModel.importRunVisionAIOnOpen
        let totalCount = summary.totalPhotoUnitsCount

        homeViewModel.isImportingFolder = true
        homeViewModel.importErrorMessage = nil
        homeViewModel.importProgress = FolderImportProgress(
            completedUnits: 0,
            totalUnits: totalCount,
            currentFilename: ""
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await SessionFolderImporter.importAsNewSession(
                    from: summary,
                    sessionName: name,
                    groupName: groupName,
                    initialTags: parsedTags,
                    transferMode: transferMode,
                    in: rootFolderURL
                ) { progress in
                    Task { @MainActor [weak self] in
                        self?.homeViewModel.importProgress = progress
                    }
                }
                self.homeViewModel.isImportingFolder = false
                self.homeViewModel.isPresentingImportSheet = false
                self.homeViewModel.importProgress = nil
                self.homeViewModel.reloadSessions(in: rootFolderURL)
                self.openSession(result.session)
                if runVisionAI {
                    self.activeSessionViewModel?.runManualVisionAnalysisBatch()
                }
                self.showTransientNotice(Self.formatImportSummaryNotice(result))
            } catch {
                self.homeViewModel.isImportingFolder = false
                self.homeViewModel.importProgress = nil
                self.homeViewModel.importErrorMessage = error.localizedDescription
            }
        }
    }

    package func importPhotosIntoActiveSessionFromPicker() {
        guard let workspace = activeSessionViewModel,
              let chosenURL = pickSourceFolderPanel(
                  title: "Importar fotos a \"\(workspace.session.name)\"",
                  message: "Elegí una carpeta para segregar sus RAW y JPG dentro de esta sesión"
              ) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try SessionFolderImporter.scanFolder(at: chosenURL, includeSubfolders: true)
                }.value
                guard !summary.units.isEmpty else {
                    self.showTransientNotice(SessionImportError.noSupportedPhotosFound.localizedDescription)
                    return
                }
                let result = try await SessionFolderImporter.importIntoExistingSession(
                    from: summary,
                    into: workspace.session,
                    transferMode: .copy
                )
                workspace.reloadFromDisk()
                workspace.runManualVisionAnalysisBatch()
                self.homeViewModel.updateSessionCounts(workspace.session)
                self.showTransientNotice(Self.formatImportSummaryNotice(result))
            } catch {
                self.showTransientNotice(error.localizedDescription)
            }
        }
    }

    private func pickSourceFolderPanel(title: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Seleccionar carpeta"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func formatImportSummaryNotice(_ result: FolderImportResult) -> String {
        if result.rawCount > 0 && result.pairedJpgCount > 0 {
            return "Importadas \(result.importedUnitsCount) tomas (\(result.rawCount) RAW · \(result.pairedJpgCount) JPG vinculados)"
        }
        return "Importadas \(result.importedUnitsCount) fotos listas para filtrar"
    }

    package func deleteSessionPermanently(_ session: PhotoSession) {
        guard let rootFolderURL else { return }
        if activeSessionViewModel?.session.id == session.id {
            stopAllLiveView()
            activeSessionViewModel = nil
        }
        if homeViewModel.permanentlyDeleteSession(session, in: rootFolderURL) {
            showTransientNotice("Proyecto \"\(session.name)\" eliminado permanentemente.")
        }
    }

    package func openSession(_ session: PhotoSession) {
        activeSessionViewModel = CullingSessionViewModel(
            session: session,
            renderer: rawRenderer,
            visionAnalyzer: visionAnalyzer,
            performancePreferences: performancePrefs
        )
    }

    package func closeActiveSession() {
        stopAllLiveView()
        if let activeSessionViewModel {
            homeViewModel.updateSessionCounts(activeSessionViewModel.session)
        }
        activeSessionViewModel = nil
        homeViewModel.reloadSessions(in: rootFolderURL)
    }

    package func stopAllLiveView() {
        liveViewService.stop()
        ptpLiveViewService.stopStream()
        discoveryService.directCanonService.stopLiveView()
        networkStreamService.stopStream()
        if gphotoBridge.isStreaming {
            gphotoBridge.stopPreviewStream()
            discoveryService.resumeSessionsAfterExternalBridge()
        }
    }

    package func openSettings(tab: SettingsTab = .devices) {
        deviceManagerViewModel.syncAliasDrafts()
        settingsTab = tab
        isPresentingSettings = true
    }

    package func dismissAllPopups() {
        isPresentingSettings = false
        isPresentingHelp = false
        homeViewModel.isPresentingNewSessionSheet = false
        if !homeViewModel.isImportingFolder {
            homeViewModel.isPresentingImportSheet = false
        }
    }

    package func attachWatchFolderFromPicker() {
        folderWatchService.presentFolderPickerAndAttach(blockingSubtreeOf: rootFolderURL) { [weak self] blockedReason in
            self?.showTransientNotice(blockedReason)
        }
        if let watched = folderWatchService.watchedFolderURL {
            showTransientNotice("Carpeta puente activa: \(watched.lastPathComponent)")
        }
    }

    package func detachWatchFolder() {
        folderWatchService.detach()
        showTransientNotice("Carpeta puente desvinculada")
    }

    package func showTransientNotice(_ message: String) {
        toastClearTask?.cancel()
        globalNoticeBanner = message
        toastClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.globalNoticeBanner = nil
        }
    }

    @discardableResult
    package func routeStagedCapture(
        stagedURL: URL,
        originalFilename: String,
        deviceProfile: KnownDevice
    ) -> IngestResult? {
        if let workspace = activeSessionViewModel {
            let result = workspace.handleCapturedFileStaged(
                stagedURL: stagedURL,
                originalFilename: originalFilename,
                deviceProfile: deviceProfile
            )
            homeViewModel.updateSessionCounts(workspace.session)
            warnIfOrphanJpgFiltered(result: result, filename: originalFilename, profile: deviceProfile)
            return result
        }

        if let rootFolderURL {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let quickName = "Sesion_Rapida_\(formatter.string(from: Date()))"
            let existing = homeViewModel.sessions.first { $0.name == quickName }
            guard let targetSession = existing ?? homeViewModel.createSession(named: quickName, in: rootFolderURL) else {
                try? FileManager.default.removeItem(at: stagedURL)
                return nil
            }
            openSession(targetSession)
            let result = activeSessionViewModel?.handleCapturedFileStaged(
                stagedURL: stagedURL,
                originalFilename: originalFilename,
                deviceProfile: deviceProfile
            )
            if let workspace = activeSessionViewModel {
                homeViewModel.updateSessionCounts(workspace.session)
            }
            showTransientNotice("Sesión abierta automáticamente para guardar \(originalFilename)")
            return result
        }

        try? FileManager.default.removeItem(at: stagedURL)
        showTransientNotice("Captura recibida (\(originalFilename)). Completá el asistente inicial.")
        return nil
    }

    private func warnIfOrphanJpgFiltered(result: IngestResult?, filename: String, profile: KnownDevice) {
        guard case .separatedCompanionJpg(_, let matchedBase) = result,
              !profile.allowJpgWhenNoRaw else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, let workspace = self.activeSessionViewModel else { return }
            let hasRawTwin = workspace.pendingItems.contains { $0.baseFilename == matchedBase }
            if !hasRawTwin {
                self.showTransientNotice("Se guardó \(filename) en JPG/, pero no llegó RAW. Activá 'Permitir filtrar JPG' en Dispositivos si disparás solo JPG.")
            }
        }
    }

    private func wireCapturePipeline() {
        let routeFile: @MainActor (URL, String, KnownDevice) -> Void = { [weak self] stagedURL, filename, profile in
            _ = self?.routeStagedCapture(stagedURL: stagedURL, originalFilename: filename, deviceProfile: profile)
        }
        discoveryService.onCapturedFileReady = routeFile
        folderWatchService.onFileReady = routeFile
    }
}
