import SwiftUI

/// Structured offline Help Center with instant keyword search, category pills,
/// step-by-step instructions, explicit capabilities, and honest system limitations.
package struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: HelpCategory = .all
    @State private var selectedTopicID: String = HelpGuideCatalog.allTopics.first?.id ?? "e2e-workflow"
    @State private var searchQuery: String = ""

    package init(initialCategory: HelpCategory = .all, initialQuery: String = "") {
        self._selectedCategory = State(initialValue: initialCategory)
        self._searchQuery = State(initialValue: initialQuery)
    }

    private var filteredTopics: [HelpTopic] {
        HelpGuideCatalog.filter(query: searchQuery, category: selectedCategory)
    }

    private var activeTopic: HelpTopic? {
        filteredTopics.first(where: { $0.id == selectedTopicID }) ?? filteredTopics.first
    }

    package var body: some View {
        VStack(spacing: 0) {
            headerBar
            categoryStrip
            HSplitView {
                sidebarPane
                    .frame(minWidth: 265, maxWidth: 295)
                detailPane
                    .frame(minWidth: 500, maxWidth: .infinity)
            }
        }
        .frame(width: 880, height: 630)
        .background(AppColors.windowCanvas)
    }

    private var headerBar: some View {
        HStack(spacing: AppSpacing.md) {
            PhotoPicBrandLogo(size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Centro de Ayuda")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Guías rápidas, controles en vivo, atajos y compatibilidad")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Text("\(filteredTopics.count) tema(s)")
                .font(AppTypography.monoMicro)
                .foregroundStyle(AppColors.textTertiary)

            Button("Listo") { dismiss() }
                .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                .keyboardShortcut(.cancelAction)
                .help("Cerrar Centro de Ayuda")
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .background(AppColors.panelSurface)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(HelpCategory.allCases) { category in
                    HelpCategoryPill(
                        title: category.rawValue,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.sm)
        }
        .background(AppColors.windowCanvas)
        .overlay(
            Rectangle().frame(height: AppSpacing.hairline).foregroundStyle(AppColors.borderSubtle),
            alignment: .bottom
        )
    }

    private var sidebarPane: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                TextField("Buscar tema, atajo o limitación...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(AppTypography.caption)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 7)
            .background(AppColors.stageBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)

            ScrollView {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(filteredTopics) { topic in
                        topicRow(topic)
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.bottom, AppSpacing.md)
            }
        }
        .background(AppColors.panelSurface)
    }

    private func topicRow(_ topic: HelpTopic) -> some View {
        HelpTopicRowButton(
            topic: topic,
            isSelected: activeTopic?.id == topic.id
        ) {
            selectedTopicID = topic.id
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let topic = activeTopic {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(topic.docCode)
                            .font(AppTypography.monoMicro)
                            .foregroundStyle(AppColors.infoBlue)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 2)
                            .background(AppColors.elevatedSurface)
                            .clipShape(Capsule())
                        Text(topic.subtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text(topic.title)
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(topic.summary)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    bulletSection(
                        title: "Qué SÍ podés hacer",
                        items: topic.canDo,
                        icon: "checkmark.circle.fill",
                        tint: AppColors.approveGreen,
                        bg: AppColors.approveGreenTint
                    )

                    bulletSection(
                        title: "Limitaciones reales · Qué NO hace",
                        items: topic.limitations,
                        icon: "exclamationmark.triangle.fill",
                        tint: AppColors.warningAmber,
                        bg: AppColors.warningAmberTint
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Guía Paso a Paso")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        ForEach(topic.steps, id: \.self) { step in
                            Text(step)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(AppSpacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColors.panelSurface)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        }
                    }

                    if !topic.tips.isEmpty {
                        bulletSection(
                            title: "Consejos de Estudio",
                            items: topic.tips,
                            icon: "lightbulb.fill",
                            tint: AppColors.infoBlue,
                            bg: AppColors.elevatedSurface
                        )
                    }
                }
                .padding(AppSpacing.xl)
            }
        } else {
            VStack(spacing: AppSpacing.md) {
                Text("Sin resultados para \"\(searchQuery)\" en \(selectedCategory.rawValue)")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textSecondary)
                Button("Limpiar filtros") {
                    searchQuery = ""
                    selectedCategory = .all
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func bulletSection(title: String, items: [String], icon: String, tint: Color, bg: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.captionMedium)
                .foregroundStyle(tint)
            ForEach(items, id: \.self) { entry in
                Label(entry, systemImage: icon)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: AppSpacing.hairline)
        )
    }
}

private struct HelpCategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.captionMedium)
                .foregroundStyle(isSelected ? AppColors.textOnAccent : (isHovered ? AppColors.textPrimary : AppColors.textSecondary))
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, 5)
                .background(isSelected ? AppColors.primaryActionFill : (isHovered ? AppColors.controlHover : AppColors.elevatedSurface))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct HelpTopicRowButton: View {
    let topic: HelpTopic
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: topic.iconSystemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.infoBlue : AppColors.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(isSelected ? AppColors.infoBlueTint : AppColors.stageBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("\(topic.docCode) · \(topic.category.rawValue)")
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? AppColors.elevatedSurface : (isHovered ? AppColors.controlHover : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .stroke(isSelected ? AppColors.borderStrong : (isHovered ? AppColors.borderSubtle : Color.clear), lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(topic.docCode): \(topic.subtitle)")
    }
}
