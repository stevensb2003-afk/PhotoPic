import Foundation
import Observation

/// Manages session discovery, creation, and real-time disk counters on the Home screen.
@MainActor
@Observable
package final class HomeViewModel {
    package private(set) var sessions: [PhotoSession] = []
    package var isPresentingNewSessionSheet: Bool = false
    package var newSessionNameDraft: String = ""
    package var errorMessage: String?

    package init() {}

    package func reloadSessions(in rootURL: URL?) {
        guard let rootURL else {
            sessions = []
            return
        }
        sessions = SessionFileManager.loadSessions(in: rootURL)
    }

    package func prepareNewSessionSheet() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let prefix = formatter.string(from: Date())
        newSessionNameDraft = "Sesion_\(prefix)"
        errorMessage = nil
        isPresentingNewSessionSheet = true
    }

    package func createSession(named name: String, in rootURL: URL) -> PhotoSession? {
        do {
            let created = try SessionFileManager.createSession(named: name, in: rootURL)
            sessions.insert(created, at: 0)
            isPresentingNewSessionSheet = false
            newSessionNameDraft = ""
            errorMessage = nil
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
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
