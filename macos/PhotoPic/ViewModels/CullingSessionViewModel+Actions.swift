import CoreGraphics
import Foundation

extension CullingSessionViewModel {
    // MARK: - Free Navigation (↑ / ↓)

    package func navigatePrevious() {
        guard currentIndex > 0 else { return }
        resetZoomState()
        currentIndex -= 1
        renderActivePhotoIfNeeded(force: true)
    }

    package func navigateNext() {
        guard currentIndex + 1 < visiblePendingItems.count else { return }
        resetZoomState()
        currentIndex += 1
        renderActivePhotoIfNeeded(force: true)
    }

    package func jumpToIndex(_ index: Int) {
        guard index >= 0, index < visiblePendingItems.count else { return }
        resetZoomState()
        currentIndex = index
        renderActivePhotoIfNeeded(force: true)
    }

    // MARK: - Physical Classification Moves (→ Approve / ← Archive / ⌘Z Undo)

    package func approveCurrentToEditing() {
        moveCurrentItem(to: .forEditing, pillText: "Para Edición", kind: .approved)
    }

    package func archiveCurrent() {
        moveCurrentItem(to: .archived, pillText: "Archivada", kind: .archived)
    }

    package func undoLastMove() {
        guard let record = undoStack.popLast() else { return }
        do {
            let restored = try SessionFileManager.undoMove(record)
            if record.destinationFolder == .archived {
                archivedItems.removeAll { $0.id == record.item.id }
            }
            let insertionIndex = min(max(0, currentIndex), pendingItems.count)
            pendingItems.insert(restored, at: insertionIndex)
            if let visibleIdx = visiblePendingItems.firstIndex(where: { $0.id == restored.id }) {
                currentIndex = visibleIdx
            }
            session.counts = SessionFileManager.readDiskCounts(for: session)
            resetZoomState()
            renderActivePhotoIfNeeded(force: true)
            showFeedbackPill("Deshecho → RAW", kind: .undone)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func recoverArchivedItemToEditing(_ item: PhotoItem) {
        do {
            _ = try SessionFileManager.moveItem(item, to: .forEditing, in: session)
            let removedIndex = archivedItems.firstIndex(where: { $0.id == item.id }) ?? 0
            archivedItems.removeAll { $0.id == item.id }
            undoStack.removeAll { $0.item.id == item.id }
            if !archivedItems.isEmpty {
                selectedArchivedID = archivedItems[min(removedIndex, archivedItems.count - 1)].id
            } else {
                selectedArchivedID = nil
                archivedPreviewImage = nil
            }
            session.counts = SessionFileManager.readDiskCounts(for: session)
            showFeedbackPill("Recuperada para Edición", kind: .recovered)
            if let next = selectedArchivedItem {
                loadArchivedPreview(for: next)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func deleteArchivedItemPermanently(_ item: PhotoItem, alsoDeleteCompanionJpg: Bool = false) {
        do {
            try SessionArchiveCleaner.permanentlyDeleteArchivedItem(
                item,
                alsoDeleteCompanionJpg: alsoDeleteCompanionJpg,
                in: session
            )
            let removedIndex = archivedItems.firstIndex(where: { $0.id == item.id }) ?? 0
            archivedItems.removeAll { $0.id == item.id }
            archivedThumbnails.removeValue(forKey: item.id)
            undoStack.removeAll { $0.item.id == item.id }

            let deletedURL = item.fileURL
            Task { [renderer] in
                await renderer.evictCache(for: deletedURL)
            }

            if !archivedItems.isEmpty {
                let nextItem = archivedItems[min(removedIndex, archivedItems.count - 1)]
                selectedArchivedID = nextItem.id
                loadArchivedPreview(for: nextItem)
            } else {
                selectedArchivedID = nil
                archivedPreviewImage = nil
            }

            session.counts = SessionFileManager.readDiskCounts(for: session)
            showFeedbackPill("Eliminada definitivamente", kind: .deletedPermanently)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func emptyAllArchivedPermanently(alsoDeleteCompanionJpgs: Bool = false) {
        do {
            let urlsToEvict = archivedItems.map(\.fileURL)
            let deletedIDs = Set(archivedItems.map(\.id))
            let removedCount = try SessionArchiveCleaner.permanentlyDeleteAllArchived(
                alsoDeleteCompanionJpgs: alsoDeleteCompanionJpgs,
                in: session
            )

            archivedItems.removeAll()
            archivedThumbnails.removeAll()
            selectedArchivedID = nil
            archivedPreviewImage = nil
            undoStack.removeAll { deletedIDs.contains($0.item.id) }

            Task { [renderer] in
                for url in urlsToEvict {
                    await renderer.evictCache(for: url)
                }
            }

            session.counts = SessionFileManager.readDiskCounts(for: session)
            if removedCount > 0 {
                showFeedbackPill("Archivadas vaciada (\(removedCount))", kind: .deletedPermanently)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCurrentItem(to folder: SessionSubfolder, pillText: String, kind: CullingFeedbackPill.Kind) {
        guard let current = currentPendingItem else { return }
        do {
            let record = try SessionFileManager.moveItem(current, to: folder, in: session)
            undoStack.append(record)
            pendingItems.removeAll { $0.id == current.id }
            if folder == .archived {
                archivedItems.append(record.item)
            }
            clampCurrentIndex()
            session.counts = SessionFileManager.readDiskCounts(for: session)
            resetZoomState()
            renderActivePhotoIfNeeded(force: true)
            showFeedbackPill(pillText, kind: kind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
