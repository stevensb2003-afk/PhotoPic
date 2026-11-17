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

            if hasSessionRawSubfolder(at: entry) {
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
                guard subValues?.isDirectory == true, hasSessionRawSubfolder(at: subEntry) else { continue }
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
            guard values?.isDirectory == true, !hasSessionRawSubfolder(at: entry) else { continue }

            let markerURL = entry.appendingPathComponent(groupMarkerFilename, isDirectory: false)
            if fm.fileExists(atPath: markerURL.path) {
                groups.append(entry.lastPathComponent)
                continue
            }
            if let nested = try? fm.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ), nested.contains(where: { hasSessionRawSubfolder(at: $0) }) {
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
        if hasSessionRawSubfolder(at: groupURL) {
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
        guard hasSessionRawSubfolder(at: session.directoryURL) else {
            throw SessionFileError.unsafeDeleteTarget
        }

        try FileManager.default.removeItem(at: session.directoryURL)
    }

    private static func hasSessionRawSubfolder(at directoryURL: URL) -> Bool {
        var isDir: ObjCBool = false
        let rawURL = directoryURL.appendingPathComponent(SessionSubfolder.raw.rawValue, isDirectory: true)
        return FileManager.default.fileExists(atPath: rawURL.path, isDirectory: &isDir) && isDir.boolValue
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
        if FileManager.default.fileExists(atPath: candidate.path), !hasSessionRawSubfolder(at: candidate) {
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
