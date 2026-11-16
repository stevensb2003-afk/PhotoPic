import Foundation

/// Outcome of routing an incoming tethered file into a session's folder tree.
package enum IngestResult: Sendable, Equatable {
    case addedRaw(PhotoItem, demotedCompressedFilename: String?)
    case addedMobileFallbackCompressed(PhotoItem)
    case separatedCompanionJpg(destinationURL: URL, matchedBaseName: String)
    case ignoredUnsupported
}

/// Handles smart RAW + JPG separation and mobile fallback ingestion into a session.
package enum SessionIngestRouter {
    package static func ingestCapturedFile(
        stagedURL: URL,
        originalFilename: String,
        deviceAlias: String?,
        deviceCategory: DeviceCategory?,
        allowJpgWhenNoRaw: Bool,
        in session: PhotoSession
    ) throws -> IngestResult {
        try SessionFileManager.ensureSubfoldersExist(for: session)

        guard let formatKind = MediaFormatClassifier.classify(filename: originalFilename) else {
            return .ignoredUnsupported
        }

        let baseName = (originalFilename as NSString).deletingPathExtension.lowercased()
        let fm = FileManager.default

        switch formatKind {
        case .raw:
            let destURL = SessionFileManager.uniqueDestinationURL(
                in: session.rawFolderURL,
                preferredFilename: originalFilename
            )
            try fm.moveItem(at: stagedURL, to: destURL)

            // If a compressed mobile-fallback twin arrived earlier in RAW/, demote it to JPG/.
            var demotedFilename: String?
            if let existingCompressedInRaw = findMatchingImage(
                baseName: baseName,
                kind: .compressed,
                in: session.rawFolderURL
            ) {
                let jpgDest = SessionFileManager.uniqueDestinationURL(
                    in: session.jpgFolderURL,
                    preferredFilename: existingCompressedInRaw.lastPathComponent
                )
                try? fm.moveItem(at: existingCompressedInRaw, to: jpgDest)
                demotedFilename = existingCompressedInRaw.lastPathComponent
            }

            let companion = findMatchingImage(baseName: baseName, kind: .compressed, in: session.jpgFolderURL)
            let item = SessionFileManager.buildPhotoItem(
                url: destURL,
                pairedURL: companion,
                alias: deviceAlias,
                category: deviceCategory
            )
            return .addedRaw(item, demotedCompressedFilename: demotedFilename)

        case .compressed:
            let inPendingRaw = findMatchingImage(baseName: baseName, kind: .raw, in: session.rawFolderURL) != nil
            let inEditingRaw =
                findMatchingImage(baseName: baseName, kind: .raw, in: session.forEditingRawFolderURL) != nil ||
                findMatchingImage(baseName: baseName, kind: .raw, in: session.forEditingFolderURL) != nil
            let inArchivedRaw =
                findMatchingImage(baseName: baseName, kind: .raw, in: session.archivedRawFolderURL) != nil ||
                findMatchingImage(baseName: baseName, kind: .raw, in: session.archivedFolderURL) != nil

            if inEditingRaw || inArchivedRaw || inPendingRaw || !allowJpgWhenNoRaw {
                let targetJpgFolder: URL = if inEditingRaw {
                    session.forEditingJpgFolderURL
                } else if inArchivedRaw {
                    session.archivedJpgFolderURL
                } else {
                    session.jpgFolderURL
                }
                let destURL = SessionFileManager.uniqueDestinationURL(
                    in: targetJpgFolder,
                    preferredFilename: originalFilename
                )
                try fm.moveItem(at: stagedURL, to: destURL)
                return .separatedCompanionJpg(destinationURL: destURL, matchedBaseName: baseName)
            } else {
                let destURL = SessionFileManager.uniqueDestinationURL(
                    in: session.rawFolderURL,
                    preferredFilename: originalFilename
                )
                try fm.moveItem(at: stagedURL, to: destURL)
                let item = SessionFileManager.buildPhotoItem(
                    url: destURL,
                    pairedURL: nil,
                    alias: deviceAlias,
                    category: deviceCategory
                )
                return .addedMobileFallbackCompressed(item)
            }
        }
    }

    private static func findMatchingImage(
        baseName: String,
        kind: MediaFormatKind,
        in folderURL: URL
    ) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return urls.first {
            MediaFormatClassifier.baseFilename(for: $0) == baseName &&
                MediaFormatClassifier.classify(filename: $0.lastPathComponent) == kind
        }
    }
}
