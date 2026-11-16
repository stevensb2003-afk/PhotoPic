import Foundation

/// Permanently deletes rejected files stored inside `Archivadas/` (alongside their `.xmp`
/// sidecars, cached tags, and optional companion `.JPG`/`.HEIC`), never touching `RAW/` or `Para_Edicion/`.
package enum SessionArchiveCleaner {
    package enum ArchiveCleanError: LocalizedError {
        case pathOutsideArchivedFolder
        case deleteFailed(String)

        package var errorDescription: String? {
            switch self {
            case .pathOutsideArchivedFolder:
                return "Operación bloqueada: el archivo no pertenece a la carpeta Archivadas/ de esta sesión."
            case .deleteFailed(let reason):
                return "No se pudo eliminar definitivamente: \(reason)"
            }
        }
    }

    package static func permanentlyDeleteArchivedItem(
        _ item: PhotoItem,
        alsoDeleteCompanionJpg: Bool,
        in session: PhotoSession
    ) throws {
        let allowedDirs: Set<String> = [
            session.archivedFolderURL.standardizedFileURL.path,
            session.archivedRawFolderURL.standardizedFileURL.path,
            session.archivedJpgFolderURL.standardizedFileURL.path,
        ]
        let fileDir = item.fileURL.standardizedFileURL.deletingLastPathComponent().path
        guard allowedDirs.contains(fileDir) else {
            throw ArchiveCleanError.pathOutsideArchivedFolder
        }

        do {
            if FileManager.default.fileExists(atPath: item.fileURL.path) {
                try FileManager.default.removeItem(at: item.fileURL)
            }
        } catch {
            throw ArchiveCleanError.deleteFailed(error.localizedDescription)
        }

        PhotoTagStore.removeTagsAndSidecar(for: item, in: session)

        if let companion = item.pairedCompressedURL {
            let isInArchivedJpg = companion.standardizedFileURL.deletingLastPathComponent().path
                == session.archivedJpgFolderURL.standardizedFileURL.path
            if isInArchivedJpg || alsoDeleteCompanionJpg {
                deleteCompanionJpgIfInsideSession(companion, in: session)
            }
        }
    }

    @discardableResult
    package static func permanentlyDeleteAllArchived(
        alsoDeleteCompanionJpgs: Bool,
        in session: PhotoSession
    ) throws -> Int {
        let items = SessionFileManager.loadArchivedItems(in: session)
        guard !items.isEmpty else { return 0 }

        var deletedURLs: [URL] = []
        var baseNames = Set<String>()

        for item in items {
            do {
                if FileManager.default.fileExists(atPath: item.fileURL.path) {
                    try FileManager.default.removeItem(at: item.fileURL)
                }
            } catch {
                throw ArchiveCleanError.deleteFailed(error.localizedDescription)
            }
            deletedURLs.append(item.fileURL)
            baseNames.insert(item.baseFilename)

            if let companion = item.pairedCompressedURL {
                let isInArchivedJpg = companion.standardizedFileURL.deletingLastPathComponent().path
                    == session.archivedJpgFolderURL.standardizedFileURL.path
                if isInArchivedJpg || alsoDeleteCompanionJpgs {
                    deleteCompanionJpgIfInsideSession(companion, in: session)
                }
            }
        }

        PhotoTagStore.removeTagsAndSidecars(
            forBaseFilenames: baseNames,
            imageURLs: deletedURLs,
            in: session
        )
        return items.count
    }

    private static func deleteCompanionJpgIfInsideSession(_ companionURL: URL, in session: PhotoSession) {
        let allowedJpgDirs: Set<String> = [
            session.jpgFolderURL.standardizedFileURL.path,
            session.archivedJpgFolderURL.standardizedFileURL.path,
        ]
        let companionDir = companionURL.standardizedFileURL.deletingLastPathComponent().path
        guard allowedJpgDirs.contains(companionDir), FileManager.default.fileExists(atPath: companionURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: companionURL)
    }
}
