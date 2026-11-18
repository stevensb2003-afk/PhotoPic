import CoreGraphics
import Foundation
import Observation

/// Tabs available inside the active photo culling workspace.
package enum WorkspaceTab: String, CaseIterable, Sendable {
    case cullPending
    case liveView
    case forEditing
    case archived

    package var title: String {
        switch self {
        case .cullPending: return "Filtrar"
        case .liveView: return "Vista en Vivo"
        case .forEditing: return "Seleccionadas"
        case .archived: return "Archivadas"
        }
    }
}

/// Non-blocking visual pill feedback for rapid culling decisions.
package struct CullingFeedbackPill: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case approved
        case archived
        case undone
        case recovered
        case liveCaptured
        case deletedPermanently
    }

    package let id = UUID()
    package let text: String
    package let kind: Kind
}

/// Triggers an animated horizontal Tinder card throw from keyboard arrows or control buttons.
package struct SwipeAnimationCommand: Equatable, Sendable {
    package let id = UUID()
    package let direction: Int // +1 = Para Edición, -1 = Archivar
}

/// Manages real-time tethered ingestion, Vision AI tag filtering, queue state,
/// physical disk moves, and Archived recovery inside a shooting session.
@MainActor
@Observable
package final class CullingSessionViewModel {
    let renderer: RawImageRenderer
    let visionAnalyzer: PhotoVisionAnalyzer
    var renderTask: Task<Void, Never>?
    var fullSensorTask: Task<Void, Never>?
    var visionBatchTask: Task<Void, Never>?
    var visionBatchGeneration: Int = 0
    var feedbackDismissTask: Task<Void, Never>?
    var timerTickTask: Task<Void, Never>?
    var undoStack: [MoveHistoryRecord] = []

    package internal(set) var session: PhotoSession
    package internal(set) var pendingItems: [PhotoItem] = []
    package internal(set) var forEditingItems: [PhotoItem] = []
    package internal(set) var archivedItems: [PhotoItem] = []
    package internal(set) var currentIndex: Int = 0
    package var activeTab: WorkspaceTab = .cullPending
    package var followLatestCapture: Bool = false
    package var autoTagOnIngest: Bool = true
    package var detectBodyPoses: Bool = true
    package var autoStartTimerOnFirstShot: Bool = true
    package internal(set) var timerNow: Date = Date()
    package var viewportMaxDimension: CGFloat = 2400
    package var selectedTagFilter: String? {
        didSet {
            clampCurrentIndex()
            renderActivePhotoIfNeeded(force: true)
        }
    }

    // Zoom 1:1 state
    package var isLockedOneToOneZoom: Bool = false
    package var isSpringLoadedZoom: Bool = false
    package var zoomNormalizedAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    package var zoomPanOffset: CGSize = .zero

    // Active GPU textures & Vision state
    package internal(set) var activeViewportImage: CGImage?
    package internal(set) var activeFullSensorImage: CGImage?
    package internal(set) var activeNativeSize: CGSize = .zero
    package internal(set) var isRenderingViewport: Bool = false
    package internal(set) var isRenderingFullSensor: Bool = false
    package internal(set) var activeRenderedItemID: String?
    package internal(set) var isAnalyzingVision: Bool = false
    package internal(set) var visionCompletedCount: Int = 0
    package internal(set) var visionTotalCount: Int = 0

    // Selected (Para_Edicion) & Archived inspectors
    package var selectedEditingID: String?
    package internal(set) var editingPreviewImage: CGImage?
    package internal(set) var isRenderingEditingPreview: Bool = false
    package var selectedArchivedID: String?
    package internal(set) var archivedPreviewImage: CGImage?
    package internal(set) var archivedThumbnails: [String: CGImage] = [:]
    package internal(set) var isRenderingArchivedPreview: Bool = false

    package internal(set) var feedbackPill: CullingFeedbackPill?
    package var pendingSwipeAnimation: SwipeAnimationCommand?
    package var errorMessage: String?

    package init(
        session: PhotoSession,
        renderer: RawImageRenderer = RawImageRenderer(),
        visionAnalyzer: PhotoVisionAnalyzer = PhotoVisionAnalyzer(),
        performancePreferences: PerformancePreferences? = nil
    ) {
        self.session = session
        self.renderer = renderer
        self.visionAnalyzer = visionAnalyzer
        if let prefs = performancePreferences {
            self.autoTagOnIngest = prefs.enableVisionAutoTagging
            self.detectBodyPoses = prefs.detectBodyPoses
            self.autoStartTimerOnFirstShot = prefs.autoStartSessionTimerOnFirstShot
            self.viewportMaxDimension = CGFloat(prefs.viewportMaxDimension)
        }
        reloadFromDisk()
    }

    package func applyPerformancePreferences(_ prefs: PerformancePreferences) {
        let wasAutoTag = autoTagOnIngest
        autoTagOnIngest = prefs.enableVisionAutoTagging
        detectBodyPoses = prefs.detectBodyPoses
        autoStartTimerOnFirstShot = prefs.autoStartSessionTimerOnFirstShot
        viewportMaxDimension = CGFloat(prefs.viewportMaxDimension)

        if !autoTagOnIngest {
            visionBatchTask?.cancel()
            visionBatchTask = nil
            isAnalyzingVision = false
            if selectedTagFilter != nil {
                selectedTagFilter = nil
            }
        } else if !wasAutoTag {
            scheduleVisionAnalysisForPending()
        }
        renderActivePhotoIfNeeded(force: true)
    }

    package var visiblePendingItems: [PhotoItem] {
        guard let filter = selectedTagFilter else { return pendingItems }
        return pendingItems.filter { item in
            item.visionTags?.allTags.contains { $0.caseInsensitiveCompare(filter) == .orderedSame } == true
        }
    }

    package var currentPendingItem: PhotoItem? {
        let items = visiblePendingItems
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    package var selectedEditingItem: PhotoItem? {
        if let id = selectedEditingID, let match = forEditingItems.first(where: { $0.id == id }) {
            return match
        }
        return forEditingItems.first
    }

    package var selectedArchivedItem: PhotoItem? {
        if let id = selectedArchivedID, let match = archivedItems.first(where: { $0.id == id }) {
            return match
        }
        return archivedItems.first
    }

    package var isAnyZoomActive: Bool {
        isLockedOneToOneZoom || isSpringLoadedZoom
    }

    package var canUndo: Bool {
        !undoStack.isEmpty
    }

    package func reloadFromDisk() {
        let tagMap = PhotoTagStore.loadAll(for: session)
        pendingItems = SessionFileManager.loadPhotoItems(
            in: session.rawFolderURL,
            jpgFolderURL: session.jpgFolderURL,
            cachedTagsByBase: tagMap
        )
        forEditingItems = SessionFileManager.loadForEditingItems(
            in: session,
            cachedTagsByBase: tagMap
        )
        archivedItems = SessionFileManager.loadArchivedItems(
            in: session,
            cachedTagsByBase: tagMap
        )
        session.counts = SessionFileManager.readDiskCounts(for: session)
        session.metadata = SessionMetadataStore.load(for: session.directoryURL)
        syncTimerTicker()
        clampCurrentIndex()
        if selectedEditingID == nil || !forEditingItems.contains(where: { $0.id == selectedEditingID }) {
            selectedEditingID = forEditingItems.first?.id
        }
        if selectedArchivedID == nil || !archivedItems.contains(where: { $0.id == selectedArchivedID }) {
            selectedArchivedID = archivedItems.first?.id
        }
        renderActivePhotoIfNeeded(force: true)
        if autoTagOnIngest {
            scheduleVisionAnalysisForPending()
        }
    }

    @discardableResult
    package func handleCapturedFileStaged(
        stagedURL: URL,
        originalFilename: String,
        deviceProfile: KnownDevice
    ) -> IngestResult? {
        do {
            let result = try SessionIngestRouter.ingestCapturedFile(
                stagedURL: stagedURL,
                originalFilename: originalFilename,
                deviceAlias: deviceProfile.alias,
                deviceCategory: deviceProfile.category,
                allowJpgWhenNoRaw: deviceProfile.allowJpgWhenNoRaw,
                in: session
            )

            switch result {
            case .addedRaw(let newItem, let demotedFilename):
                if let demotedFilename,
                   let demotedIdx = pendingItems.firstIndex(where: { $0.filename == demotedFilename }) {
                    pendingItems.remove(at: demotedIdx)
                    clampCurrentIndex()
                }
                appendLivePendingItem(newItem)

            case .addedMobileFallbackCompressed(let newItem):
                appendLivePendingItem(newItem)

            case .separatedCompanionJpg(let destURL, let matchedBase):
                if let idx = pendingItems.firstIndex(where: { $0.baseFilename == matchedBase }) {
                    pendingItems[idx].pairedCompressedURL = destURL
                }
                if let editIdx = forEditingItems.firstIndex(where: { $0.baseFilename == matchedBase }) {
                    forEditingItems[editIdx].pairedCompressedURL = destURL
                }
                if let archIdx = archivedItems.firstIndex(where: { $0.baseFilename == matchedBase }) {
                    archivedItems[archIdx].pairedCompressedURL = destURL
                }

            case .ignoredUnsupported:
                break
            }

            session.counts = SessionFileManager.readDiskCounts(for: session)
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func appendLivePendingItem(_ item: PhotoItem) {
        let wasEmpty = visiblePendingItems.isEmpty
        pendingItems.append(item)
        handleFirstShotTimerAutoStartIfNeeded(capturedAt: item.capturedAt)

        if autoTagOnIngest {
            scheduleVisionAnalysis(for: item)
        }

        if wasEmpty || followLatestCapture {
            if selectedTagFilter != nil {
                selectedTagFilter = nil
            }
            currentIndex = max(0, visiblePendingItems.count - 1)
            resetZoomState()
            renderActivePhotoIfNeeded(force: true)
        } else {
            let target = item
            let targetDim = max(1200, viewportMaxDimension - 200)
            Task { [renderer] in
                _ = await renderer.renderViewportImage(for: target, maxDimension: targetDim)
            }
        }
        showFeedbackPill("Nueva captura: \(item.filename)", kind: .liveCaptured)
    }

    func clampCurrentIndex() {
        let count = visiblePendingItems.count
        currentIndex = count == 0 ? 0 : min(max(0, currentIndex), count - 1)
    }
}
