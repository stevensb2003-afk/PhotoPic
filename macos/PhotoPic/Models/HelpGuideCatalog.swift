import Foundation

/// Topic grouping pills shown at the top of the built-in Help Center.
package enum HelpCategory: String, CaseIterable, Sendable, Identifiable {
    case all = "Todos"
    case setupFlow = "Inicio y Hardware"
    case connectionsLive = "Conexión y Vivo"
    case cullingAI = "Culling e IA"
    case foldersLimits = "Carpetas y Límites"

    package var id: String { rawValue }
}

/// Structured operational help topic aligned with PhotoPic's BRD documentation.
package struct HelpTopic: Identifiable, Sendable, Equatable, Hashable {
    package let id: String
    package let docCode: String
    package let category: HelpCategory
    package let title: String
    package let subtitle: String
    package let iconSystemName: String
    package let keywords: [String]
    package let summary: String
    package let steps: [String]
    package let canDo: [String]
    package let limitations: [String]
    package let tips: [String]

    package init(
        id: String,
        docCode: String,
        category: HelpCategory,
        title: String,
        subtitle: String,
        iconSystemName: String,
        keywords: [String],
        summary: String,
        steps: [String],
        canDo: [String],
        limitations: [String],
        tips: [String]
    ) {
        self.id = id
        self.docCode = docCode
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.keywords = keywords
        self.summary = summary
        self.steps = steps
        self.canDo = canDo
        self.limitations = limitations
        self.tips = tips
    }

    package func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let fields = [docCode, category.rawValue, title, subtitle, summary]
            + keywords + steps + canDo + limitations + tips
        return fields.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

/// Search & category filter helpers for PhotoPic's embedded offline knowledge base.
package enum HelpGuideCatalog {
    package static func filter(query: String, category: HelpCategory) -> [HelpTopic] {
        allTopics.filter { topic in
            let matchesCategory = category == .all || topic.category == category
            return matchesCategory && topic.matches(query: query)
        }
    }
}
