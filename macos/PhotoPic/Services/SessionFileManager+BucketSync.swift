import Foundation

/// Synchronized RAW + JPG bucket movement, Undo, and archived loading across
/// `Para_Edicion/{RAW,JPG}` and `Archivadas/{RAW,JPG}`.
extension SessionFileManager {
    package static func loadArchivedItems(
        in session: PhotoSession,
        cachedTagsByBase: [String: PhotoVisionTags] = [:]
    ) -> [PhotoItem] {
        loadBucketItems(
            rawFolder: session.archivedRawFolderURL,
            legacyFolder: session.archivedFolderURL,
            jpgFolder: session.archivedJpgFolderURL,
            fallbackJpgFolderURL: session.jpgFolderURL,
            cachedTagsByBase: cachedTagsByBase
        )
    }

    package static func loadForEditingItems(
        in session: PhotoSession,
        cachedTagsByBase: [String: PhotoVisionTags] = [:]
    ) -> [PhotoItem] {
        loadBucketItems(
            rawFolder: session.forEditingRawFolderURL,
            legacyFolder: session.forEditingFolderURL,
            jpgFolder: session.forEditingJpgFolderURL,
            fallbackJpgFolderURL: session.jpgFolderURL,
            cachedTagsByBase: cachedTagsByBase
        )
    }

    private static func loadBucketItems(
        rawFolder: URL,
        legacyFolder: URL,
        jpgFolder: URL,
        fallbackJpgFolderURL: URL,
        cachedTagsByBase: [String: PhotoVisionTags]
    ) -> [PhotoItem] {
        let primary = loadPhotoItems(
            in: rawFolder,
            jpgFolderURL: jpgFolder,
            fallbackJpgFolderURL: fallbackJpgFolderURL,
            cachedTagsByBase: cachedTagsByBase
        )
        let legacy = loadPhotoItems(
            in: legacyFolder,
            jpgFolderURL: jpgFolder,
            fallbackJpgFolderURL: fallbackJpgFolderURL,
            cachedTagsByBase: cachedTagsByBase
        )
        let rawBases = Set((primary + legacy).map(\.baseFilename))
        let standaloneJpgs = loadPhotoItems(
            in: jpgFolder,
            jpgFolderURL: jpgFolder,
            cachedTagsByBase: cachedTagsByBase
        ).filter { !rawBases.contains($0.baseFilename) }
        return (primary + legacy + standaloneJpgs).sorted {
            $0.capturedAt == $1.capturedAt ? $0.filename < $1.filename : $0.capturedAt < $1.capturedAt
        }
    }

    package static func moveItem(
        _ item: PhotoItem,
        to destinationFolder: SessionSubfolder,
        in session: PhotoSession
    ) throws -> MoveHistoryRecord {
        try ensureSubfoldersExist(for: session)
        // Standalone compressed shots live alongside RAWs in `RAW/` while pending culling so `loadPhotoItems` finds them.
        let folderURL = (destinationFolder == .raw || item.formatKind == .raw)
            ? session.rawBucketURL(for: destinationFolder)
            : session.jpgBucketURL(for: destinationFolder)
        let targetURL = uniqueDestinationURL(in: folderURL, preferredFilename: item.fileURL.lastPathComponent)

        do {
            try FileManager.default.moveItem(at: item.fileURL, to: targetURL)
            PhotoTagStore.relocateSidecarIfPresent(from: item.fileURL, to: targetURL)
        } catch {
            throw SessionFileError.fileMoveFailed(error.localizedDescription)
        }

        var originalCompanion: URL?
        var movedCompanion: URL?
        var nextCompanionURL = item.pairedCompressedURL

        if item.formatKind == .raw, let companion = resolveCompanionURL(for: item, in: session) {
            let jpgDestDir = session.jpgBucketURL(for: destinationFolder)
            if companion.deletingLastPathComponent().standardizedFileURL.path != jpgDestDir.standardizedFileURL.path {
                let jpgTarget = uniqueDestinationURL(in: jpgDestDir, preferredFilename: companion.lastPathComponent)
                try? FileManager.default.moveItem(at: companion, to: jpgTarget)
                originalCompanion = companion
                movedCompanion = jpgTarget
                nextCompanionURL = jpgTarget
            }
        }

        let updatedItem = PhotoItem(
            fileURL: targetURL,
            pairedCompressedURL: nextCompanionURL,
            fileSizeBytes: item.fileSizeBytes,
            capturedAt: item.capturedAt,
            sourceDeviceAlias: item.sourceDeviceAlias,
            sourceCategory: item.sourceCategory,
            exif: item.exif,
            visionTags: item.visionTags
        )

        return MoveHistoryRecord(
            item: updatedItem,
            originalURL: item.fileURL,
            movedURL: targetURL,
            destinationFolder: destinationFolder,
            originalCompanionURL: originalCompanion,
            movedCompanionURL: movedCompanion
        )
    }

    package static func undoMove(_ record: MoveHistoryRecord) throws -> PhotoItem {
        let targetURL: URL = !FileManager.default.fileExists(atPath: record.originalURL.path)
            ? record.originalURL
            : uniqueDestinationURL(
                in: record.originalURL.deletingLastPathComponent(),
                preferredFilename: record.originalURL.lastPathComponent
            )

        do {
            try FileManager.default.moveItem(at: record.movedURL, to: targetURL)
            PhotoTagStore.relocateSidecarIfPresent(from: record.movedURL, to: targetURL)
        } catch {
            throw SessionFileError.fileMoveFailed(error.localizedDescription)
        }

        var restoredCompanionURL = record.item.pairedCompressedURL
        if let movedComp = record.movedCompanionURL,
           let origComp = record.originalCompanionURL,
           FileManager.default.fileExists(atPath: movedComp.path) {
            let restoredComp = !FileManager.default.fileExists(atPath: origComp.path)
                ? origComp
                : uniqueDestinationURL(in: origComp.deletingLastPathComponent(), preferredFilename: origComp.lastPathComponent)
            try? FileManager.default.moveItem(at: movedComp, to: restoredComp)
            restoredCompanionURL = restoredComp
        }

        return PhotoItem(
            fileURL: targetURL,
            pairedCompressedURL: restoredCompanionURL,
            fileSizeBytes: record.item.fileSizeBytes,
            capturedAt: record.item.capturedAt,
            sourceDeviceAlias: record.item.sourceDeviceAlias,
            sourceCategory: record.item.sourceCategory,
            exif: record.item.exif,
            visionTags: record.item.visionTags
        )
    }

    static func resolveCompanionURL(for item: PhotoItem, in session: PhotoSession) -> URL? {
        if let paired = item.pairedCompressedURL, FileManager.default.fileExists(atPath: paired.path) {
            return paired
        }
        let searchFolders = [session.jpgFolderURL, session.archivedJpgFolderURL, session.forEditingJpgFolderURL]
        for folder in searchFolders {
            if let match = indexFilesByBaseName(in: folder)[item.baseFilename] {
                return match
            }
        }
        return nil
    }

    static func countBucketEntries(rawFolder: URL, jpgFolder: URL, legacyRoot: URL) -> Int {
        let rawBases = Set(indexFilesByBaseName(in: rawFolder).keys)
        let legacyCount = countSupportedImages(in: legacyRoot)
        let standaloneJpgs = indexFilesByBaseName(in: jpgFolder).keys.filter { !rawBases.contains($0) }.count
        return rawBases.count + legacyCount + standaloneJpgs
    }
}
