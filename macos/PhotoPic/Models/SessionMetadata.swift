import Foundation

/// Per-session studio metadata (project tags and shooting timer state)
/// stored backward-compatibly inside `<Session>/.photopic_session.json`.
package struct SessionMetadata: Codable, Sendable, Equatable, Hashable {
    package var tags: [String]
    package var timerStartedAtEpoch: Double?
    package var timerEndedAtEpoch: Double?
    package var accumulatedSeconds: Double
    package var firstShotEpoch: Double?
    package var isTimerRunning: Bool
    package var isTimerFinished: Bool

    package init(
        tags: [String] = [],
        timerStartedAtEpoch: Double? = nil,
        timerEndedAtEpoch: Double? = nil,
        accumulatedSeconds: Double = 0,
        firstShotEpoch: Double? = nil,
        isTimerRunning: Bool = false,
        isTimerFinished: Bool = false
    ) {
        self.tags = tags
        self.timerStartedAtEpoch = timerStartedAtEpoch
        self.timerEndedAtEpoch = timerEndedAtEpoch
        self.accumulatedSeconds = accumulatedSeconds
        self.firstShotEpoch = firstShotEpoch
        self.isTimerRunning = isTimerRunning
        self.isTimerFinished = isTimerFinished
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.timerStartedAtEpoch = try c.decodeIfPresent(Double.self, forKey: .timerStartedAtEpoch)
        self.timerEndedAtEpoch = try c.decodeIfPresent(Double.self, forKey: .timerEndedAtEpoch)
        self.accumulatedSeconds = try c.decodeIfPresent(Double.self, forKey: .accumulatedSeconds) ?? 0
        self.firstShotEpoch = try c.decodeIfPresent(Double.self, forKey: .firstShotEpoch)
        self.isTimerRunning = try c.decodeIfPresent(Bool.self, forKey: .isTimerRunning) ?? false
        self.isTimerFinished = try c.decodeIfPresent(Bool.self, forKey: .isTimerFinished) ?? false
    }

    package var hasRecordedTime: Bool {
        isTimerRunning || isTimerFinished || accumulatedSeconds > 0
    }

    package var hasNeverStartedTimer: Bool {
        !isTimerRunning && !isTimerFinished && accumulatedSeconds == 0 && timerStartedAtEpoch == nil
    }

    package var firstShotDate: Date? {
        firstShotEpoch.map { Date(timeIntervalSince1970: $0) }
    }

    package func elapsedSeconds(at now: Date = Date()) -> Double {
        if isTimerRunning, let started = timerStartedAtEpoch {
            return max(0, accumulatedSeconds + max(0, now.timeIntervalSince1970 - started))
        }
        return max(0, accumulatedSeconds)
    }

    package func formattedDuration(at now: Date = Date()) -> String {
        let total = Int(elapsedSeconds(at: now).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    package mutating func startManual(at now: Date = Date()) {
        guard !isTimerRunning else { return }
        timerStartedAtEpoch = now.timeIntervalSince1970
        timerEndedAtEpoch = nil
        isTimerRunning = true
        isTimerFinished = false
    }

    /// Starts the session clock using the first live shot's timestamp, clamped if
    /// the camera's internal clock is uncalibrated or skewed >12h vs host time.
    package mutating func autoStartFromFirstShot(capturedAt: Date, now: Date = Date()) {
        guard hasNeverStartedTimer else { return }
        firstShotEpoch = capturedAt.timeIntervalSince1970
        let diff = now.timeIntervalSince(capturedAt)
        let anchor: Double = (diff >= 0 && diff <= 12 * 3600)
            ? capturedAt.timeIntervalSince1970
            : now.timeIntervalSince1970
        timerStartedAtEpoch = anchor
        timerEndedAtEpoch = nil
        isTimerRunning = true
        isTimerFinished = false
    }

    package mutating func stopAndFinish(at now: Date = Date()) {
        if isTimerRunning, let started = timerStartedAtEpoch {
            accumulatedSeconds += max(0, now.timeIntervalSince1970 - started)
        }
        timerStartedAtEpoch = nil
        timerEndedAtEpoch = now.timeIntervalSince1970
        isTimerRunning = false
        isTimerFinished = true
    }

    package mutating func resetTimer() {
        timerStartedAtEpoch = nil
        timerEndedAtEpoch = nil
        accumulatedSeconds = 0
        firstShotEpoch = nil
        isTimerRunning = false
        isTimerFinished = false
    }

    package mutating func addTag(_ rawTag: String) {
        let clean = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        tags.append(clean)
    }

    package mutating func removeTag(_ tag: String) {
        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    package static func parseCommaSeparatedTags(_ raw: String) -> [String] {
        var meta = SessionMetadata()
        for part in raw.split(separator: ",") {
            meta.addTag(String(part))
        }
        return meta.tags
    }
}

/// Reads and writes `.photopic_session.json` inside each session directory.
package enum SessionMetadataStore {
    package static let filename = ".photopic_session.json"

    package static func metadataFileURL(for sessionDirectoryURL: URL) -> URL {
        sessionDirectoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    package static func load(for sessionDirectoryURL: URL) -> SessionMetadata {
        let url = metadataFileURL(for: sessionDirectoryURL)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SessionMetadata.self, from: data) else {
            return SessionMetadata()
        }
        return decoded
    }

    package static func save(_ metadata: SessionMetadata, for sessionDirectoryURL: URL) {
        let url = metadataFileURL(for: sessionDirectoryURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
