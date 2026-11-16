import CoreGraphics
import Foundation

package struct TagSummaryBadge: Identifiable, Sendable, Equatable {
    package let tag: String
    package let count: Int
    package var id: String { tag }
}

extension CullingSessionViewModel {
    /// Aggregated tag frequencies across pending photos for the live filter bar.
    package var availablePendingTags: [TagSummaryBadge] {
        var counts: [String: (canonical: String, count: Int)] = [:]
        for item in pendingItems {
            guard let tags = item.visionTags?.allTags else { continue }
            for tag in tags {
                let key = tag.lowercased()
                if let existing = counts[key] {
                    counts[key] = (existing.canonical, existing.count + 1)
                } else {
                    counts[key] = (tag, 1)
                }
            }
        }
        return counts.values
            .map { TagSummaryBadge(tag: $0.canonical, count: $0.count) }
            .sorted { $0.count == $1.count ? $0.tag < $1.tag : $0.count > $1.count }
    }

    package func scheduleVisionAnalysisForPending() {
        visionBatchTask?.cancel()
        guard autoTagOnIngest else {
            isAnalyzingVision = false
            return
        }
        let unanalyzed = pendingItems.filter { $0.visionTags == nil }
        guard !unanalyzed.isEmpty else { return }

        isAnalyzingVision = true
        visionBatchTask = Task { [weak self] in
            guard let self else { return }
            for item in unanalyzed {
                guard !Task.isCancelled, self.autoTagOnIngest else { break }
                await self.runVisionAnalysis(for: item)
            }
            self.isAnalyzingVision = false
        }
    }

    package func scheduleVisionAnalysis(for item: PhotoItem) {
        guard autoTagOnIngest else { return }
        isAnalyzingVision = true
        Task { [weak self] in
            guard let self else { return }
            await self.runVisionAnalysis(for: item)
            self.isAnalyzingVision = false
        }
    }

    @discardableResult
    package func runVisionAnalysis(for item: PhotoItem) async -> PhotoVisionTags? {
        guard let payload = await renderer.renderViewportImage(for: item, maxDimension: 1280) else {
            return nil
        }
        let tags = await visionAnalyzer.analyze(cgImage: payload.cgImage, includeBodyPose: detectBodyPoses)
        applyVisionTags(tags, forBaseFilename: item.baseFilename, syncSidecar: true)
        return tags
    }

    package func addCustomTag(_ rawTag: String, to item: PhotoItem) {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var tags = item.visionTags ?? PhotoVisionTags()
        tags.addCustomTag(trimmed)
        applyVisionTags(tags, forBaseFilename: item.baseFilename, syncSidecar: true)
    }

    package func removeCustomTag(_ tag: String, from item: PhotoItem) {
        guard var tags = item.visionTags else { return }
        tags.removeCustomTag(tag)
        applyVisionTags(tags, forBaseFilename: item.baseFilename, syncSidecar: true)
    }

    private func applyVisionTags(
        _ tags: PhotoVisionTags,
        forBaseFilename base: String,
        syncSidecar: Bool
    ) {
        if let idx = pendingItems.firstIndex(where: { $0.baseFilename == base }) {
            pendingItems[idx].visionTags = tags
            PhotoTagStore.save(
                tags: tags,
                for: pendingItems[idx],
                in: session,
                writeSidecarAndFinderTags: syncSidecar
            )
        } else if let idx = archivedItems.firstIndex(where: { $0.baseFilename == base }) {
            archivedItems[idx].visionTags = tags
            PhotoTagStore.save(
                tags: tags,
                for: archivedItems[idx],
                in: session,
                writeSidecarAndFinderTags: syncSidecar
            )
        }
    }
}
