import CoreGraphics
import Foundation

extension CullingSessionViewModel {
    // MARK: - Zoom 1:1 Sensor Controls

    package func toggleLockedOneToOneZoom() {
        guard currentPendingItem != nil else { return }
        isSpringLoadedZoom = false
        isLockedOneToOneZoom.toggle()
        zoomPanOffset = .zero
        if isLockedOneToOneZoom {
            ensureFullSensorImageLoaded()
        }
    }

    package func engageSpringLoadedZoom(normalizedAnchor: CGPoint) {
        guard currentPendingItem != nil, !isLockedOneToOneZoom else { return }
        zoomNormalizedAnchor = normalizedAnchor
        zoomPanOffset = .zero
        isSpringLoadedZoom = true
        ensureFullSensorImageLoaded()
    }

    package func releaseSpringLoadedZoom() {
        guard isSpringLoadedZoom else { return }
        isSpringLoadedZoom = false
        zoomPanOffset = .zero
    }

    package func resetZoomState() {
        isLockedOneToOneZoom = false
        isSpringLoadedZoom = false
        zoomPanOffset = .zero
        fullSensorTask?.cancel()
        activeFullSensorImage = nil
    }

    // MARK: - Archived & Thumbnail Rendering

    package func selectArchivedItem(_ item: PhotoItem) {
        selectedArchivedID = item.id
        loadArchivedPreview(for: item)
    }

    package func loadArchivedPreview(for item: PhotoItem) {
        isRenderingArchivedPreview = true
        Task { [weak self] in
            guard let self else { return }
            let payload = await self.renderer.renderViewportImage(for: item, maxDimension: 1600)
            guard !Task.isCancelled, self.selectedArchivedItem?.id == item.id else { return }
            self.archivedPreviewImage = payload?.cgImage
            self.isRenderingArchivedPreview = false
        }
    }

    @discardableResult
    package func renderThumbnail(for item: PhotoItem) async -> CGImage? {
        if let cached = archivedThumbnails[item.id] {
            return cached
        }
        let payload = await renderer.renderViewportImage(for: item, maxDimension: 420)
        if let cg = payload?.cgImage {
            archivedThumbnails[item.id] = cg
        }
        return payload?.cgImage
    }

    // MARK: - Active Stage GPU Pipeline

    func renderActivePhotoIfNeeded(force: Bool) {
        guard let item = currentPendingItem else {
            renderTask?.cancel()
            activeViewportImage = nil
            activeFullSensorImage = nil
            activeNativeSize = .zero
            activeRenderedItemID = nil
            isRenderingViewport = false
            return
        }

        if !force, activeRenderedItemID == item.id, activeViewportImage != nil {
            return
        }

        renderTask?.cancel()
        isRenderingViewport = true
        activeRenderedItemID = item.id

        let upcoming = Array(visiblePendingItems.dropFirst(currentIndex + 1).prefix(2))
        renderTask = Task { [weak self] in
            guard let self else { return }
            let payload = await self.renderer.renderViewportImage(for: item, maxDimension: 2400)
            guard !Task.isCancelled, self.currentPendingItem?.id == item.id else { return }
            self.activeViewportImage = payload?.cgImage
            self.activeNativeSize = payload?.nativeSize ?? .zero
            self.isRenderingViewport = false

            if self.isAnyZoomActive {
                self.ensureFullSensorImageLoaded()
            }
            await self.renderer.prefetch(items: upcoming, maxDimension: 2200)
        }
    }

    func ensureFullSensorImageLoaded() {
        guard let item = currentPendingItem else { return }
        fullSensorTask?.cancel()
        isRenderingFullSensor = true
        fullSensorTask = Task { [weak self] in
            guard let self else { return }
            let payload = await self.renderer.renderFullSensorImage(for: item)
            guard !Task.isCancelled, self.currentPendingItem?.id == item.id else { return }
            self.activeFullSensorImage = payload?.cgImage
            if let native = payload?.nativeSize, native != .zero {
                self.activeNativeSize = native
            }
            self.isRenderingFullSensor = false
        }
    }

    func showFeedbackPill(_ text: String, kind: CullingFeedbackPill.Kind) {
        feedbackDismissTask?.cancel()
        feedbackPill = CullingFeedbackPill(text: text, kind: kind)
        feedbackDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            self?.feedbackPill = nil
        }
    }
}
