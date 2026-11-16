import AppKit
import SwiftUI

/// Built-in offline Help Center modal synchronized with PhotoPic's BRD documentation.
package struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopicID: String = HelpGuideCatalog.allTopics.first?.id ?? "e2e-workflow"
    @State private var searchQuery: String = ""

    package init() {}

    private var filteredTopics: [HelpTopic] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return HelpGuideCatalog.allTopics }
        return HelpGuideCatalog.allTopics.filter { topic in
            topic.title.localizedCaseInsensitiveContains(q)
                || topic.subtitle.localizedCaseInsensitiveContains(q)
                || topic.summary.localizedCaseInsensitiveContains(q)
                || topic.steps.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    private var activeTopic: HelpTopic? {
        filteredTopics.first(where: { $0.id == selectedTopicID }) ?? filteredTopics.first
    }

    package var body: some View {
        VStack(spacing: 0) {
            headerBar
            HSplitView {
                sidebarPane
                    .frame(minWidth: 230, maxWidth: 265)
                detailPane
                    .frame(minWidth: 440, maxWidth: .infinity)
            }
        }
        .frame(width: 780, height: 560)
        .background(AppColors.windowCanvas)
    }

    private var headerBar: some View {
        HStack(spacing: AppSpacing.md) {
            PictogrammersIcon(.cameraIris, size: 18)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Centro de Ayuda de PhotoPic")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Guía operativa 100% offline · Flujos, hardware, atajos y organización RAW + JPG")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button("Listo") {
                dismiss()
            }
            .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle()
                .frame(height: AppSpacing.hairline)
                .foregroundStyle(AppColors.borderSubtle),
            alignment: .bottom
        )
    }

    private var sidebarPane: some View {
        VStack(spacing: AppSpacing.sm) {
            TextField("Buscar tema o atajo...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)

            ScrollView {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(filteredTopics) { topic in
                        let isSelected = activeTopic?.id == topic.id
                        Button {
                            selectedTopicID = topic.id
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: topic.iconSystemName)
                                    .font(AppTypography.captionMedium)
                                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textTertiary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(topic.title)
                                        .font(AppTypography.captionMedium)
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                    Text(topic.docCode)
                                        .font(AppTypography.monoMicro)
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.sm)
                            .background(isSelected ? AppColors.elevatedSurface : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                    .stroke(isSelected ? AppColors.borderStrong : Color.clear, lineWidth: AppSpacing.hairline)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.bottom, AppSpacing.md)
            }
        }
        .background(AppColors.panelSurface)
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
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                        .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
                                )
                        }
                    }

                    if !topic.tips.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            ForEach(topic.tips, id: \.self) { tip in
                                Label(tip, systemImage: "lightbulb.fill")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.approveGreen)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.approveGreenTint)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                }
                .padding(AppSpacing.xl)
            }
        } else {
            VStack(spacing: AppSpacing.sm) {
                Text("Sin resultados para \"\(searchQuery)\"")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
