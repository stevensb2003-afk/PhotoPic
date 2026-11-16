import Foundation
import Observation

/// Active tab inside the Settings & Device Manager modal sheet.
package enum SettingsTab: String, CaseIterable, Sendable {
    case devices
    case general

    package var title: String {
        switch self {
        case .devices: return "Dispositivos"
        case .general: return "General y Atajos"
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
    package let rawRenderer: RawImageRenderer
    package let visionAnalyzer: PhotoVisionAnalyzer
    package let homeViewModel: HomeViewModel
    package let deviceManagerViewModel: DeviceManagerViewModel

    package private(set) var rootFolderURL: URL?
    package private(set) var activeSessionViewModel: CullingSessionViewModel?
    package var isPresentingSettings: Bool = false
    package var settingsTab: SettingsTab = .devices
    package var globalNoticeBanner: String?

    private var toastClearTask: Task<Void, Never>?

    package init(
        bookmarkManager: BookmarkManager = BookmarkManager(),
        knownDevicesStore: KnownDevicesStore = KnownDevicesStore(),
        startDeviceBrowser: Bool = true
    ) {
        self.bookmarkManager = bookmarkManager
        self.knownDevicesStore = knownDevicesStore
        let capture = TetherCaptureService()
        let discovery = DeviceDiscoveryService(knownStore: knownDevicesStore, captureService: capture)
        self.discoveryService = discovery
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
        homeViewModel.reloadSessions(in: url)
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
            visionAnalyzer: visionAnalyzer
        )
    }

    package func closeActiveSession() {
        if let activeSessionViewModel {
            homeViewModel.updateSessionCounts(activeSessionViewModel.session)
        }
        activeSessionViewModel = nil
        homeViewModel.reloadSessions(in: rootFolderURL)
    }

    package func openSettings(tab: SettingsTab = .devices) {
        deviceManagerViewModel.syncAliasDrafts()
        settingsTab = tab
        isPresentingSettings = true
    }

    package func dismissAllPopups() {
        isPresentingSettings = false
        homeViewModel.isPresentingNewSessionSheet = false
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

    private func wireCapturePipeline() {
        discoveryService.onCapturedFileReady = { [weak self] stagedURL, filename, profile in
            guard let self else { return }
            if let workspace = self.activeSessionViewModel {
                _ = workspace.handleCapturedFileStaged(
                    stagedURL: stagedURL,
                    originalFilename: filename,
                    deviceProfile: profile
                )
                self.homeViewModel.updateSessionCounts(workspace.session)
            } else {
                try? FileManager.default.removeItem(at: stagedURL)
                self.showTransientNotice(
                    "Captura recibida (\(filename)). Abrí o creá una sesión para guardarla en RAW/."
                )
            }
        }
    }
}
