import Foundation
import Observation

/// Filter mode for Master Folders on the Home Dashboard.
package enum SessionGroupFilter: Hashable, Sendable {
    case all
    case ungrouped
    case group(String)
}

/// Manages session discovery, Master Groups, project tags, search filtering,
/// permanent deletion, and real-time disk counters on the Home screen.
@MainActor
@Observable
package final class HomeViewModel {
    package private(set) var sessions: [PhotoSession] = []
    package private(set) var masterGroups: [String] = []
    package var searchQuery: String = ""
    package var groupFilter: SessionGroupFilter = .all
    package var selectedTagFilter: String? = nil

    package var isPresentingNewSessionSheet: Bool = false
    package var newSessionNameDraft: String = ""
    package var newSessionGroupDraft: String = ""
    package var newSessionTagsDraft: String = ""
    package var sessionPendingDeletion: PhotoSession? = nil
    package var errorMessage: String?

    package init() {}

    package var filteredSessions: [PhotoSession] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { session in
            let matchesGroup: Bool
            switch groupFilter {
            case .all:
                matchesGroup = true
            case .ungrouped:
                matchesGroup = session.groupName == nil
            case .group(let target):
                matchesGroup = session.groupName?.caseInsensitiveCompare(target) == .orderedSame
            }
            guard matchesGroup else { return false }

            if let tagFilter = selectedTagFilter, !tagFilter.isEmpty {
                let hasTag = session.metadata.tags.contains { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }
                guard hasTag else { return false }
            }

            guard !trimmedQuery.isEmpty else { return true }
            if session.name.localizedStandardContains(trimmedQuery) { return true }
            if let group = session.groupName, group.localizedStandardContains(trimmedQuery) { return true }
            return session.metadata.tags.contains { $0.localizedStandardContains(trimmedQuery) }
        }
    }

    package var availableProjectTags: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for session in sessions {
            for tag in session.metadata.tags {
                let lower = tag.lowercased()
                if seen.insert(lower).inserted {
                    result.append(tag)
                }
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    package var hasUngroupedSessions: Bool {
        sessions.contains { $0.groupName == nil }
    }

    package func reloadSessions(in rootURL: URL?) {
        guard let rootURL else {
            sessions = []
            masterGroups = []
            return
        }
        sessions = SessionFileManager.loadSessions(in: rootURL)
        masterGroups = SessionFileManager.loadMasterGroups(in: rootURL)
        if case .group(let selected) = groupFilter,
           !masterGroups.contains(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
            groupFilter = .all
        }
        if let selectedTag = selectedTagFilter,
           !availableProjectTags.contains(where: { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }) {
            selectedTagFilter = nil
        }
    }

    package func prepareNewSessionSheet() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let prefix = formatter.string(from: Date())
        newSessionNameDraft = "Sesion_\(prefix)"
        if case .group(let activeGroup) = groupFilter {
            newSessionGroupDraft = activeGroup
        } else {
            newSessionGroupDraft = ""
        }
        newSessionTagsDraft = ""
        errorMessage = nil
        isPresentingNewSessionSheet = true
    }

    @discardableResult
    package func createSession(
        named name: String,
        groupName: String? = nil,
        rawTags: String = "",
        in rootURL: URL
    ) -> PhotoSession? {
        do {
            let parsedTags = SessionMetadata.parseCommaSeparatedTags(rawTags)
            let created = try SessionFileManager.createSession(
                named: name,
                groupName: groupName,
                initialTags: parsedTags,
                in: rootURL
            )
            sessions.insert(created, at: 0)
            masterGroups = SessionFileManager.loadMasterGroups(in: rootURL)
            isPresentingNewSessionSheet = false
            newSessionNameDraft = ""
            newSessionGroupDraft = ""
            newSessionTagsDraft = ""
            errorMessage = nil
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    package func createMasterGroup(named name: String, in rootURL: URL) -> String? {
        do {
            let createdName = try SessionFileManager.createMasterGroup(named: name, in: rootURL)
            masterGroups = SessionFileManager.loadMasterGroups(in: rootURL)
            errorMessage = nil
            return createdName
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    package func addTag(_ rawTag: String, to session: PhotoSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var meta = sessions[idx].metadata
        meta.addTag(rawTag)
        SessionMetadataStore.save(meta, for: sessions[idx].directoryURL)
        sessions[idx].metadata = meta
    }

    package func removeTag(_ tag: String, from session: PhotoSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var meta = sessions[idx].metadata
        meta.removeTag(tag)
        SessionMetadataStore.save(meta, for: sessions[idx].directoryURL)
        sessions[idx].metadata = meta
    }

    package func moveSession(_ session: PhotoSession, toGroup groupName: String?, in rootURL: URL) {
        do {
            let moved = try SessionFileManager.moveSession(session, toGroup: groupName, in: rootURL)
            reloadSessions(in: rootURL)
            if !sessions.contains(where: { $0.id == moved.id }) {
                sessions.insert(moved, at: 0)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    package func permanentlyDeleteSession(_ session: PhotoSession, in rootURL: URL) -> Bool {
        do {
            try SessionFileManager.permanentlyDeleteSession(session, in: rootURL)
            sessions.removeAll { $0.id == session.id }
            masterGroups = SessionFileManager.loadMasterGroups(in: rootURL)
            sessionPendingDeletion = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    package func updateSessionCounts(_ updatedSession: PhotoSession) {
        if let idx = sessions.firstIndex(where: { $0.id == updatedSession.id }) {
            sessions[idx] = updatedSession
        }
    }

    package static func defaultSuggestedSessionName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "Tether_\(formatter.string(from: Date()))"
    }
}
