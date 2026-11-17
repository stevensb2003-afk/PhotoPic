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
    package let gphotoBridge: GPhoto2LiveBridge
    package let networkStreamService = NetworkMJPEGStreamService()
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
        self.performancePrefs = resolvedPerfStore.loadOrSeed(from: audit)

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
            completedSetup: performancePrefs.hasCompletedGuidedSetup
        )
    }

    package func reAuditAndApplyRecommendedProfile() {
        let freshAudit = HardwareCapabilityAuditor.auditCurrentMac()
        hardwareAudit = freshAudit
        performancePrefs = PerformancePreferences.preset(
            for: freshAudit.recommendedTier,
            completedSetup: performancePrefs.hasCompletedGuidedSetup
        )
        showTransientNotice("Auditoría completada: \(freshAudit.recommendedTier.shortBadge)")
    }

    package func createAndOpenSession(named name: String) {
        guard let rootFolderURL else { return }
        if let created = homeViewModel.createSession(named: name, in: rootFolderURL) {
            openSession(created)
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
    }

    package func attachWatchFolderFromPicker() {
        folderWatchService.presentFolderPickerAndAttach(blockingSubtreeOf: rootFolderURL) { [weak self] blockedReason in
            self?.showTransientNotice(blockedReason)
        }
        if let watched = folderWatchService.watchedFolderURL {
            showTransientNotice("Watchfolder Wi-Fi/SD activo: \(watched.lastPathComponent)")
        }
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

    private func wireCapturePipeline() {
        let routeFile: @MainActor (URL, String, KnownDevice) -> Void = { [weak self] stagedURL, filename, profile in
            _ = self?.routeStagedCapture(stagedURL: stagedURL, originalFilename: filename, deviceProfile: profile)
        }
        discoveryService.onCapturedFileReady = routeFile
        folderWatchService.onFileReady = routeFile
    }
}
