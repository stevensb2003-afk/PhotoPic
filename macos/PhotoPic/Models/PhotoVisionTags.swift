import Foundation

/// Offline Apple Vision analysis results and semantic tags for a single photo.
package struct PhotoVisionTags: Sendable, Codable, Equatable, Hashable {
    package var analyzedAt: Date
    package var personCount: Int
    package var faceCount: Int
    package var hasClosedEyesWarning: Bool
    package var autoTags: [String]
    package var customTags: [String]

    package init(
        analyzedAt: Date = Date(),
        personCount: Int = 0,
        faceCount: Int = 0,
        hasClosedEyesWarning: Bool = false,
        autoTags: [String] = [],
        customTags: [String] = []
    ) {
        self.analyzedAt = analyzedAt
        self.personCount = personCount
        self.faceCount = faceCount
        self.hasClosedEyesWarning = hasClosedEyesWarning
        self.autoTags = autoTags
        self.customTags = customTags
    }

    /// Deduplicated ordered list of automatic + custom studio tags.
    package var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in autoTags + customTags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    package var peopleSummaryBadge: String {
        switch personCount {
        case 0: return "Sin personas"
        case 1: return "1 persona"
        case 2: return "2 personas · Pareja"
        default: return "\(personCount) personas"
        }
    }

    package mutating func addCustomTag(_ rawTag: String) {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !allTags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            customTags.append(trimmed)
        }
    }

    package mutating func removeCustomTag(_ tag: String) {
        customTags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }
}
