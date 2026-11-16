import Foundation

/// Undoable disk movement record used by Cmd+Z (tracks both RAW and paired JPG).
package struct MoveHistoryRecord: Sendable, Equatable {
    package let item: PhotoItem
    package let originalURL: URL
    package let movedURL: URL
    package let destinationFolder: SessionSubfolder
    package let originalCompanionURL: URL?
    package let movedCompanionURL: URL?

    package init(
        item: PhotoItem,
        originalURL: URL,
        movedURL: URL,
        destinationFolder: SessionSubfolder,
        originalCompanionURL: URL? = nil,
        movedCompanionURL: URL? = nil
    ) {
        self.item = item
        self.originalURL = originalURL
        self.movedURL = movedURL
        self.destinationFolder = destinationFolder
        self.originalCompanionURL = originalCompanionURL
        self.movedCompanionURL = movedCompanionURL
    }
}

/// Manages session folder trees (`RAW`, `JPG`, `Para_Edicion`, `Archivadas`),
/// queue scanning, atomic disk moves, and Undo restoration.
package enum SessionFileManager {
    package enum SessionFileError: LocalizedError {
        case invalidSessionName
        case fileMoveFailed(String)

        package var errorDescription: String? {
            switch self {
            case .invalidSessionName:
                return "El nombre de la sesión no es válido."
            case .fileMoveFailed(let reason):
                return "No se pudo mover el archivo: \(reason)"
            }
        }
    }

    package static func createSession(named rawName: String, in rootURL: URL) throws -> PhotoSession {
        let sanitized = sanitizeSessionName(rawName)
        guard !sanitized.isEmpty else {
            throw SessionFileError.invalidSessionName
        }

        let sessionURL = uniqueDirectoryURL(in: rootURL, preferredName: sanitized)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: true)

        for subfolder in SessionSubfolder.allCases {
            let subURL = sessionURL.appendingPathComponent(subfolder.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: subURL, withIntermediateDirectories: true)
        }

        return PhotoSession(name: sessionURL.lastPathComponent, directoryURL: sessionURL)
    }

    package static func ensureSubfoldersExist(for session: PhotoSession) throws {
        let fm = FileManager.default
        for subfolder in SessionSubfolder.allCases {
            let subURL = session.directoryURL.appendingPathComponent(subfolder.rawValue, isDirectory: true)
            try fm.createDirectory(at: subURL, withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: session.forEditingRawFolderURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: session.forEditingJpgFolderURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: session.archivedRawFolderURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: session.archivedJpgFolderURL, withIntermediateDirectories: true)
    }

    package static func loadSessions(in rootURL: URL) -> [PhotoSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sessions: [PhotoSession] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
            guard values?.isDirectory == true else { continue }

            let rawURL = entry.appendingPathComponent(SessionSubfolder.raw.rawValue, isDirectory: true)
            guard fm.fileExists(atPath: rawURL.path) else { continue }

            let createdAt = values?.creationDate ?? Date()
            var session = PhotoSession(name: entry.lastPathComponent, directoryURL: entry, createdAt: createdAt)
            session.counts = readDiskCounts(for: session)
            sessions.append(session)
        }

        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    package static func readDiskCounts(for session: PhotoSession) -> SessionDiskCounts {
        SessionDiskCounts(
            pending: countSupportedImages(in: session.rawFolderURL),
            forEditing: countBucketEntries(
                rawFolder: session.forEditingRawFolderURL,
                jpgFolder: session.forEditingJpgFolderURL,
                legacyRoot: session.forEditingFolderURL
            ),
            archived: countBucketEntries(
                rawFolder: session.archivedRawFolderURL,
                jpgFolder: session.archivedJpgFolderURL,
                legacyRoot: session.archivedFolderURL
            ),
            companionJpgs: countSupportedImages(in: session.jpgFolderURL)
        )
    }

    package static func loadPhotoItems(
        in folderURL: URL,
        jpgFolderURL: URL,
        fallbackJpgFolderURL: URL? = nil,
        cachedTagsByBase: [String: PhotoVisionTags] = [:]
    ) -> [PhotoItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var companionIndex = fallbackJpgFolderURL.map { indexFilesByBaseName(in: $0) } ?? [:]
        for (k, v) in indexFilesByBaseName(in: jpgFolderURL) {
            companionIndex[k] = v
        }
        var items: [PhotoItem] = []

        for url in files where MediaFormatClassifier.isSupportedImage(url: url) {
            let base = MediaFormatClassifier.baseFilename(for: url)
            var item = buildPhotoItem(url: url, pairedURL: companionIndex[base], alias: nil, category: nil)
            item.visionTags = cachedTagsByBase[base]
            items.append(item)
        }

        return items.sorted {
            $0.capturedAt == $1.capturedAt ? $0.filename < $1.filename : $0.capturedAt < $1.capturedAt
        }
    }

    package static func buildPhotoItem(
        url: URL,
        pairedURL: URL?,
        alias: String?,
        category: DeviceCategory?
    ) -> PhotoItem {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let size = Int64(values?.fileSize ?? 0)
        let exif = ExifMetadataReader.read(from: url, fallbackCompanionURL: pairedURL)
        let timestamp = exif.captureDate ?? values?.creationDate ?? values?.contentModificationDate ?? Date()
        return PhotoItem(
            fileURL: url,
            pairedCompressedURL: pairedURL,
            fileSizeBytes: size,
            capturedAt: timestamp,
            sourceDeviceAlias: alias ?? exif.cameraModel,
            sourceCategory: category,
            exif: exif
        )
    }

    package static func uniqueDestinationURL(in folderURL: URL, preferredFilename: String) -> URL {
        let fm = FileManager.default
        let base = (preferredFilename as NSString).deletingPathExtension
        let ext = (preferredFilename as NSString).pathExtension
        var candidate = folderURL.appendingPathComponent(preferredFilename, isDirectory: false)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
            candidate = folderURL.appendingPathComponent(name, isDirectory: false)
            suffix += 1
        }
        return candidate
    }

    static func countSupportedImages(in folderURL: URL) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return urls.reduce(0) { MediaFormatClassifier.isSupportedImage(url: $1) ? $0 + 1 : $0 }
    }

    static func indexFilesByBaseName(in folderURL: URL) -> [String: URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }
        var index: [String: URL] = [:]
        for url in urls where MediaFormatClassifier.isSupportedImage(url: url) {
            index[MediaFormatClassifier.baseFilename(for: url)] = url
        }
        return index
    }

    private static func sanitizeSessionName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueDirectoryURL(in parentURL: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        var candidate = parentURL.appendingPathComponent(preferredName, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(preferredName)_\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }
}
