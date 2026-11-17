import Foundation

/// Live folder counts read directly from disk inside a session directory.
package struct SessionDiskCounts: Sendable, Equatable, Hashable {
    package var pending: Int
    package var forEditing: Int
    package var archived: Int
    package var companionJpgs: Int

    package init(
        pending: Int = 0,
        forEditing: Int = 0,
        archived: Int = 0,
        companionJpgs: Int = 0
    ) {
        self.pending = pending
        self.forEditing = forEditing
        self.archived = archived
        self.companionJpgs = companionJpgs
    }

    package var totalCulled: Int {
        forEditing + archived
    }

    package var totalAllImages: Int {
        pending + forEditing + archived
    }
}

/// Canonical subfolder layout inside each shooting session.
package enum SessionSubfolder: String, CaseIterable, Sendable {
    case raw = "RAW"
    case jpg = "JPG"
    case forEditing = "Para_Edicion"
    case archived = "Archivadas"
}

/// A physical mini-project directory under the user's Global Root Folder.
package struct PhotoSession: Identifiable, Sendable, Equatable, Hashable {
    package let id: String
    package var name: String
    package var directoryURL: URL
    package var createdAt: Date
    package var counts: SessionDiskCounts
    package var groupName: String?
    package var metadata: SessionMetadata

    package init(
        name: String,
        directoryURL: URL,
        createdAt: Date = Date(),
        counts: SessionDiskCounts = SessionDiskCounts(),
        groupName: String? = nil,
        metadata: SessionMetadata = SessionMetadata()
    ) {
        self.id = directoryURL.standardizedFileURL.path
        self.name = name
        self.directoryURL = directoryURL
        self.createdAt = createdAt
        self.counts = counts
        self.groupName = groupName
        self.metadata = metadata
    }

    package var rawFolderURL: URL {
        directoryURL.appendingPathComponent(SessionSubfolder.raw.rawValue, isDirectory: true)
    }

    package var jpgFolderURL: URL {
        directoryURL.appendingPathComponent(SessionSubfolder.jpg.rawValue, isDirectory: true)
    }

    package var forEditingFolderURL: URL {
        directoryURL.appendingPathComponent(SessionSubfolder.forEditing.rawValue, isDirectory: true)
    }

    package var archivedFolderURL: URL {
        directoryURL.appendingPathComponent(SessionSubfolder.archived.rawValue, isDirectory: true)
    }

    package var forEditingRawFolderURL: URL {
        forEditingFolderURL.appendingPathComponent(SessionSubfolder.raw.rawValue, isDirectory: true)
    }

    package var forEditingJpgFolderURL: URL {
        forEditingFolderURL.appendingPathComponent(SessionSubfolder.jpg.rawValue, isDirectory: true)
    }

    package var archivedRawFolderURL: URL {
        archivedFolderURL.appendingPathComponent(SessionSubfolder.raw.rawValue, isDirectory: true)
    }

    package var archivedJpgFolderURL: URL {
        archivedFolderURL.appendingPathComponent(SessionSubfolder.jpg.rawValue, isDirectory: true)
    }

    package func rawBucketURL(for subfolder: SessionSubfolder) -> URL {
        switch subfolder {
        case .raw, .jpg: return rawFolderURL
        case .forEditing: return forEditingRawFolderURL
        case .archived: return archivedRawFolderURL
        }
    }

    package func jpgBucketURL(for subfolder: SessionSubfolder) -> URL {
        switch subfolder {
        case .raw, .jpg: return jpgFolderURL
        case .forEditing: return forEditingJpgFolderURL
        case .archived: return archivedJpgFolderURL
        }
    }
}
