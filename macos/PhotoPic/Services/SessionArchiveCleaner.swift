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
        let archivedDir = session.archivedFolderURL.standardizedFileURL.path
        let fileDir = item.fileURL.standardizedFileURL.deletingLastPathComponent().path
        guard fileDir == archivedDir else {
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

        if alsoDeleteCompanionJpg, let companion = item.pairedCompressedURL {
            deleteCompanionJpgIfInsideSession(companion, in: session)
        }
    }

    @discardableResult
    package static func permanentlyDeleteAllArchived(
        alsoDeleteCompanionJpgs: Bool,
        in session: PhotoSession
    ) throws -> Int {
        let items = SessionFileManager.loadPhotoItems(
            in: session.archivedFolderURL,
            jpgFolderURL: session.jpgFolderURL
        )
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

            if alsoDeleteCompanionJpgs, let companion = item.pairedCompressedURL {
                deleteCompanionJpgIfInsideSession(companion, in: session)
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
        let jpgDir = session.jpgFolderURL.standardizedFileURL.path
        let companionDir = companionURL.standardizedFileURL.deletingLastPathComponent().path
        guard companionDir == jpgDir, FileManager.default.fileExists(atPath: companionURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: companionURL)
    }
}
