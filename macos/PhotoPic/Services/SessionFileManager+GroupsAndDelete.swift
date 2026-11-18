import Foundation

extension SessionFileManager {
    package static let groupMarkerFilename = ".photopic_group.json"

    static func loadAllFlatAndGroupedSessions(in rootURL: URL) -> [PhotoSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sessions: [PhotoSession] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
            guard values?.isDirectory == true else { continue }

            if isSessionDirectory(at: entry) {
                sessions.append(buildLoadedSession(at: entry, groupName: nil, createdAt: values?.creationDate))
                continue
            }

            guard let nested = try? fm.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for subEntry in nested {
                let subValues = try? subEntry.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
                guard subValues?.isDirectory == true, isSessionDirectory(at: subEntry) else { continue }
                sessions.append(
                    buildLoadedSession(
                        at: subEntry,
                        groupName: entry.lastPathComponent,
                        createdAt: subValues?.creationDate
                    )
                )
            }
        }

        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    package static func loadMasterGroups(in rootURL: URL) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var groups: [String] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true, !isSessionDirectory(at: entry) else { continue }

            if hasGroupMarker(at: entry) {
                groups.append(entry.lastPathComponent)
                continue
            }
            if let nested = try? fm.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ), nested.contains(where: { isSessionDirectory(at: $0) }) {
                groups.append(entry.lastPathComponent)
            }
        }

        return groups.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @discardableResult
    package static func createMasterGroup(named rawGroupName: String, in rootURL: URL) throws -> String {
        let sanitized = sanitizeSessionName(rawGroupName)
        guard !sanitized.isEmpty else {
            throw SessionFileError.invalidGroupName
        }
        var targetName = sanitized
        var groupURL = rootURL.appendingPathComponent(targetName, isDirectory: true)
        if isSessionDirectory(at: groupURL) {
            groupURL = uniqueDirectoryURL(in: rootURL, preferredName: "\(sanitized)_Grupo")
            targetName = groupURL.lastPathComponent
        }
        try FileManager.default.createDirectory(at: groupURL, withIntermediateDirectories: true)
        writeGroupMarkerIfNeeded(in: groupURL)
        return targetName
    }

    package static func createSession(
        named rawName: String,
        groupName rawGroupName: String?,
        initialTags: [String] = [],
        in rootURL: URL
    ) throws -> PhotoSession {
        let sanitized = sanitizeSessionName(rawName)
        guard !sanitized.isEmpty else {
            throw SessionFileError.invalidSessionName
        }

        let trimmedGroup = rawGroupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var resolvedGroup: String?
        let parentURL: URL
        if trimmedGroup.isEmpty {
            parentURL = rootURL
        } else {
            let groupFolder = try resolveOrCreateGroupDirectory(named: trimmedGroup, in: rootURL)
            resolvedGroup = groupFolder.lastPathComponent
            parentURL = groupFolder
        }

        let sessionURL = uniqueDirectoryURL(in: parentURL, preferredName: sanitized)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: true)
        var session = PhotoSession(
            name: sessionURL.lastPathComponent,
            directoryURL: sessionURL,
            groupName: resolvedGroup
        )
        try ensureSubfoldersExist(for: session)

        if !initialTags.isEmpty {
            var meta = SessionMetadata()
            for tag in initialTags { meta.addTag(tag) }
            session.metadata = meta
            SessionMetadataStore.save(meta, for: sessionURL)
        }
        return session
    }

    package static func moveSession(
        _ session: PhotoSession,
        toGroup rawGroupName: String?,
        in rootURL: URL
    ) throws -> PhotoSession {
        let trimmed = rawGroupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetParentURL: URL
        let resolvedGroup: String?
        if trimmed.isEmpty {
            targetParentURL = rootURL
            resolvedGroup = nil
        } else {
            let groupDir = try resolveOrCreateGroupDirectory(named: trimmed, in: rootURL)
            targetParentURL = groupDir
            resolvedGroup = groupDir.lastPathComponent
        }

        if session.directoryURL.deletingLastPathComponent().standardizedFileURL == targetParentURL.standardizedFileURL {
            return session
        }

        let destinationURL = uniqueDirectoryURL(in: targetParentURL, preferredName: session.directoryURL.lastPathComponent)
        try FileManager.default.moveItem(at: session.directoryURL, to: destinationURL)
        var updated = PhotoSession(
            name: destinationURL.lastPathComponent,
            directoryURL: destinationURL,
            createdAt: session.createdAt,
            groupName: resolvedGroup,
            metadata: SessionMetadataStore.load(for: destinationURL)
        )
        updated.counts = readDiskCounts(for: updated)
        return updated
    }

    /// Renames a session directory directly on disk (Finder / Explorer compatible),
    /// supporting case-only renames on case-insensitive filesystems like APFS.
    @discardableResult
    package static func renameSession(
        _ session: PhotoSession,
        to rawNewName: String,
        in rootURL: URL
    ) throws -> PhotoSession {
        let sanitized = sanitizeSessionName(rawNewName)
        guard !sanitized.isEmpty else {
            throw SessionFileError.invalidSessionName
        }

        let fm = FileManager.default
        let rootStd = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let sourceStd = session.directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard !rootStd.isEmpty,
              rootStd != "/",
              sourceStd.hasPrefix(rootStd + "/"),
              isSessionDirectory(at: session.directoryURL) else {
            throw SessionFileError.unsafeDeleteTarget
        }

        let currentName = session.directoryURL.lastPathComponent
        if sanitized == currentName {
            return session
        }

        let parentURL = session.directoryURL.deletingLastPathComponent()
        let destinationURL: URL
        if sanitized.lowercased() == currentName.lowercased() {
            let tempURL = uniqueDirectoryURL(in: parentURL, preferredName: ".photopic_rename_\(UUID().uuidString)")
            try fm.moveItem(at: session.directoryURL, to: tempURL)
            destinationURL = parentURL.appendingPathComponent(sanitized, isDirectory: true)
            try fm.moveItem(at: tempURL, to: destinationURL)
        } else {
            destinationURL = uniqueDirectoryURL(in: parentURL, preferredName: sanitized)
            try fm.moveItem(at: session.directoryURL, to: destinationURL)
        }

        var updated = PhotoSession(
            name: destinationURL.lastPathComponent,
            directoryURL: destinationURL,
            createdAt: session.createdAt,
            groupName: session.groupName,
            metadata: SessionMetadataStore.load(for: destinationURL)
        )
        updated.counts = readDiskCounts(for: updated)
        return updated
    }

    /// Renames a Master Group folder directly on disk so Finder / Explorer stay in sync.
    @discardableResult
    package static func renameMasterGroup(
        named oldGroupName: String,
        to rawNewName: String,
        in rootURL: URL
    ) throws -> String {
        let sanitized = sanitizeSessionName(rawNewName)
        guard !sanitized.isEmpty else {
            throw SessionFileError.invalidGroupName
        }
        if sanitized == oldGroupName {
            return oldGroupName
        }

        let fm = FileManager.default
        let oldURL = rootURL.appendingPathComponent(oldGroupName, isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: oldURL.path, isDirectory: &isDir),
              isDir.boolValue,
              !isSessionDirectory(at: oldURL) else {
            throw SessionFileError.invalidGroupName
        }

        let targetURL: URL
        if sanitized.lowercased() == oldGroupName.lowercased() {
            let tempURL = uniqueDirectoryURL(in: rootURL, preferredName: ".photopic_group_rename_\(UUID().uuidString)")
            try fm.moveItem(at: oldURL, to: tempURL)
            targetURL = rootURL.appendingPathComponent(sanitized, isDirectory: true)
            try fm.moveItem(at: tempURL, to: targetURL)
        } else {
            targetURL = uniqueDirectoryURL(in: rootURL, preferredName: sanitized)
            try fm.moveItem(at: oldURL, to: targetURL)
        }

        writeGroupMarkerIfNeeded(in: targetURL)
        return targetURL.lastPathComponent
    }

    /// Permanently removes a session directory and all its photos from disk after verifying
    /// strict containment inside `rootURL` at valid depth (flat or inside a Master Group).
    package static func permanentlyDeleteSession(_ session: PhotoSession, in rootURL: URL) throws {
        let rootStd = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let targetStd = session.directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard !rootStd.isEmpty,
              rootStd != "/",
              targetStd != rootStd,
              targetStd.hasPrefix(rootStd + "/") else {
            throw SessionFileError.unsafeDeleteTarget
        }

        let relativeComponents = String(targetStd.dropFirst(rootStd.count + 1)).split(separator: "/")
        guard relativeComponents.count == 1 || relativeComponents.count == 2 else {
            throw SessionFileError.unsafeDeleteTarget
        }
        guard isSessionDirectory(at: session.directoryURL) else {
            throw SessionFileError.unsafeDeleteTarget
        }

        try FileManager.default.removeItem(at: session.directoryURL)
    }

    private static func hasGroupMarker(at directoryURL: URL) -> Bool {
        let markerURL = directoryURL.appendingPathComponent(groupMarkerFilename, isDirectory: false)
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Distinguishes a PhotoPic session from a Master Group even if a session inside a group
    /// happens to be named `RAW`.
    private static func isSessionDirectory(at directoryURL: URL) -> Bool {
        guard !hasGroupMarker(at: directoryURL) else { return false }
        let fm = FileManager.default
        let rawURL = directoryURL.appendingPathComponent(SessionSubfolder.raw.rawValue, isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: rawURL.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let nestedRaw = rawURL.appendingPathComponent(SessionSubfolder.raw.rawValue, isDirectory: true)
        let nestedEditing = rawURL.appendingPathComponent(SessionSubfolder.forEditing.rawValue, isDirectory: true)
        if fm.fileExists(atPath: nestedRaw.path), fm.fileExists(atPath: nestedEditing.path) {
            return false
        }
        return true
    }

    private static func buildLoadedSession(at entry: URL, groupName: String?, createdAt: Date?) -> PhotoSession {
        let metadata = SessionMetadataStore.load(for: entry)
        var session = PhotoSession(
            name: entry.lastPathComponent,
            directoryURL: entry,
            createdAt: createdAt ?? Date(),
            groupName: groupName,
            metadata: metadata
        )
        session.counts = readDiskCounts(for: session)
        return session
    }

    private static func resolveOrCreateGroupDirectory(named rawGroupName: String, in rootURL: URL) throws -> URL {
        let sanitized = sanitizeSessionName(rawGroupName)
        guard !sanitized.isEmpty else {
            throw SessionFileError.invalidGroupName
        }
        let candidate = rootURL.appendingPathComponent(sanitized, isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path), !isSessionDirectory(at: candidate) {
            writeGroupMarkerIfNeeded(in: candidate)
            return candidate
        }
        let finalName = try createMasterGroup(named: sanitized, in: rootURL)
        return rootURL.appendingPathComponent(finalName, isDirectory: true)
    }

    private static func writeGroupMarkerIfNeeded(in groupURL: URL) {
        let markerURL = groupURL.appendingPathComponent(groupMarkerFilename, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }
        let payload = Data("{\"kind\":\"photopic_master_group\"}\n".utf8)
        try? payload.write(to: markerURL, options: .atomic)
    }
}
