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

    package func requestAnimatedApprove() {
        guard currentPendingItem != nil else { return }
        pendingSwipeAnimation = SwipeAnimationCommand(direction: 1)
    }

    package func requestAnimatedArchive() {
        guard currentPendingItem != nil else { return }
        pendingSwipeAnimation = SwipeAnimationCommand(direction: -1)
    }

    package func approveCurrentToEditing() {
        moveCurrentItem(to: .forEditing, pillText: "Seleccionada", kind: .approved)
    }

    package func archiveCurrent() {
        moveCurrentItem(to: .archived, pillText: "Archivada", kind: .archived)
    }

    package func undoLastMove() {
        guard let record = undoStack.popLast() else { return }
        do {
            let restored = try SessionFileManager.undoMove(record)
            switch record.destinationFolder {
            case .archived:
                archivedItems.removeAll { $0.id == record.item.id }
                archivedThumbnails.removeValue(forKey: record.item.id)
                if selectedArchivedID == record.item.id {
                    selectedArchivedID = archivedItems.first?.id
                    if let next = selectedArchivedItem {
                        loadArchivedPreview(for: next)
                    } else {
                        archivedPreviewImage = nil
                    }
                }
            case .forEditing:
                forEditingItems.removeAll { $0.id == record.item.id }
                if selectedEditingID == record.item.id {
                    selectedEditingID = forEditingItems.first?.id
                    if let next = selectedEditingItem {
                        loadEditingPreview(for: next)
                    } else {
                        editingPreviewImage = nil
                    }
                }
            case .raw, .jpg:
                break
            }
            pendingItems.append(restored)
            sortChronologically(&pendingItems)
            if let visibleIdx = visiblePendingItems.firstIndex(where: { $0.id == restored.id }) {
                currentIndex = visibleIdx
            } else {
                clampCurrentIndex()
            }
            session.counts = SessionFileManager.readDiskCounts(for: session)
            resetZoomState()
            renderActivePhotoIfNeeded(force: true)
            showFeedbackPill("Deshecho → Filtrar", kind: .undone)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func recoverArchivedItemToEditing(_ item: PhotoItem) {
        do {
            let record = try SessionFileManager.moveItem(item, to: .forEditing, in: session)
            let removedIndex = archivedItems.firstIndex(where: { $0.id == item.id }) ?? 0
            archivedItems.removeAll { $0.id == item.id }
            archivedThumbnails.removeValue(forKey: item.id)
            forEditingItems.append(record.item)
            sortChronologically(&forEditingItems)
            if selectedEditingID == nil {
                selectedEditingID = record.item.id
            }
            undoStack.removeAll { $0.item.id == item.id }
            if !archivedItems.isEmpty {
                selectedArchivedID = archivedItems[min(removedIndex, archivedItems.count - 1)].id
            } else {
                selectedArchivedID = nil
                archivedPreviewImage = nil
            }
            session.counts = SessionFileManager.readDiskCounts(for: session)
            showFeedbackPill("Recuperada a Seleccionadas", kind: .recovered)
            if let next = selectedArchivedItem {
                loadArchivedPreview(for: next)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func moveEditingItemToArchived(_ item: PhotoItem) {
        do {
            let record = try SessionFileManager.moveItem(item, to: .archived, in: session)
            let removedIndex = forEditingItems.firstIndex(where: { $0.id == item.id }) ?? 0
            forEditingItems.removeAll { $0.id == item.id }
            archivedItems.append(record.item)
            sortChronologically(&archivedItems)
            if selectedArchivedID == nil {
                selectedArchivedID = record.item.id
            }
            undoStack.removeAll { $0.item.id == item.id }
            if !forEditingItems.isEmpty {
                selectedEditingID = forEditingItems[min(removedIndex, forEditingItems.count - 1)].id
            } else {
                selectedEditingID = nil
                editingPreviewImage = nil
            }
            session.counts = SessionFileManager.readDiskCounts(for: session)
            showFeedbackPill("Movida a Archivadas", kind: .archived)
            if let next = selectedEditingItem {
                loadEditingPreview(for: next)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func returnEditingItemToPending(_ item: PhotoItem) {
        do {
            let record = try SessionFileManager.moveItem(item, to: .raw, in: session)
            let removedIndex = forEditingItems.firstIndex(where: { $0.id == item.id }) ?? 0
            forEditingItems.removeAll { $0.id == item.id }
            pendingItems.append(record.item)
            sortChronologically(&pendingItems)
            undoStack.removeAll { $0.item.id == item.id }
            if !forEditingItems.isEmpty {
                selectedEditingID = forEditingItems[min(removedIndex, forEditingItems.count - 1)].id
            } else {
                selectedEditingID = nil
                editingPreviewImage = nil
            }
            clampCurrentIndex()
            session.counts = SessionFileManager.readDiskCounts(for: session)
            renderActivePhotoIfNeeded(force: true)
            showFeedbackPill("Devuelta a Filtrar", kind: .recovered)
            if let next = selectedEditingItem {
                loadEditingPreview(for: next)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func stepEditingSelection(delta: Int) {
        if let target = steppedItem(in: forEditingItems, currentID: selectedEditingID, delta: delta) {
            selectEditingItem(target)
        }
    }

    package func stepArchivedSelection(delta: Int) {
        if let target = steppedItem(in: archivedItems, currentID: selectedArchivedID, delta: delta) {
            selectArchivedItem(target)
        }
    }

    package func rotateActivePhotoClockwise() {
        let targetItem: PhotoItem?
        switch activeTab {
        case .cullPending:
            targetItem = currentPendingItem
        case .forEditing:
            targetItem = selectedEditingItem
        case .archived:
            targetItem = selectedArchivedItem
        case .liveView:
            targetItem = nil
        }
        guard let item = targetItem else { return }
        rotatePhotoClockwise(item)
    }

    package func rotatePhotoClockwise(_ item: PhotoItem) {
        let currentTab = activeTab
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try PhotoOrientationService.rotateClockwise90(item: item)
                }.value
                await self.renderer.evictCache(for: item.fileURL)
                if let companion = item.pairedCompressedURL {
                    await self.renderer.evictCache(for: companion)
                }
                self.archivedThumbnails.removeValue(forKey: item.id)
                self.resetZoomState()
                switch currentTab {
                case .cullPending:
                    if self.currentPendingItem?.id == item.id {
                        self.renderActivePhotoIfNeeded(force: true)
                    }
                case .forEditing:
                    if self.selectedEditingItem?.id == item.id {
                        self.loadEditingPreview(for: item)
                    }
                case .archived:
                    if self.selectedArchivedItem?.id == item.id {
                        self.loadArchivedPreview(for: item)
                    }
                case .liveView:
                    break
                }
                self.showFeedbackPill("Rotada 90° (guardada)", kind: .recovered)
            } catch {
                self.errorMessage = error.localizedDescription
            }
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
                sortChronologically(&archivedItems)
                if selectedArchivedID == nil {
                    selectedArchivedID = record.item.id
                }
            } else if folder == .forEditing {
                forEditingItems.append(record.item)
                sortChronologically(&forEditingItems)
                if selectedEditingID == nil {
                    selectedEditingID = record.item.id
                }
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

    private func sortChronologically(_ items: inout [PhotoItem]) {
        items.sort { lhs, rhs in
            if lhs.capturedAt == rhs.capturedAt {
                return lhs.filename < rhs.filename
            }
            return lhs.capturedAt < rhs.capturedAt
        }
    }

    private func steppedItem(in items: [PhotoItem], currentID: String?, delta: Int) -> PhotoItem? {
        guard !items.isEmpty else { return nil }
        let currentIdx = currentID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIdx = min(max(0, currentIdx + delta), items.count - 1)
        return items[nextIdx]
    }
}
