import SwiftUI

/// Horizontal studio bar allowing instant queue filtering by Vision AI tags (faces, people, poses).
package struct VisionTagFilterStrip: View {
    let availableTags: [TagSummaryBadge]
    @Binding var selectedTag: String?
    let totalPendingCount: Int
    let isAnalyzing: Bool

    package init(
        availableTags: [TagSummaryBadge],
        selectedTag: Binding<String?>,
        totalPendingCount: Int,
        isAnalyzing: Bool
    ) {
        self.availableTags = availableTags
        self._selectedTag = selectedTag
        self.totalPendingCount = totalPendingCount
        self.isAnalyzing = isAnalyzing
    }

    package var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xxs) {
                    PictogrammersIcon(.creationSparkles, size: 13)
                        .foregroundStyle(AppColors.warningAmber)
                    Text("IA:")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.trailing, AppSpacing.xxs)

                filterChip(title: "Todas", count: totalPendingCount, isSelected: selectedTag == nil) {
                    selectedTag = nil
                }

                ForEach(availableTags) { entry in
                    filterChip(
                        title: entry.tag,
                        count: entry.count,
                        isSelected: selectedTag?.caseInsensitiveCompare(entry.tag) == .orderedSame
                    ) {
                        if selectedTag?.caseInsensitiveCompare(entry.tag) == .orderedSame {
                            selectedTag = nil
                        } else {
                            selectedTag = entry.tag
                        }
                    }
                }

                if isAnalyzing {
                    HStack(spacing: AppSpacing.xxs) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Etiquetando...")
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.leading, AppSpacing.sm)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xs)
        }
        .background(AppColors.panelSurface)
        .overlay(
            Rectangle()
                .frame(height: AppSpacing.hairline)
                .foregroundStyle(AppColors.borderSubtle),
            alignment: .bottom
        )
    }

    private func filterChip(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let isWarningTag = title == "Ojos cerrados"
        let accent: Color = isWarningTag ? AppColors.warningAmber : AppColors.infoBlue

        return Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let asset = iconForTag(title) {
                    PictogrammersIcon(asset, size: 12)
                        .foregroundStyle(isSelected ? accent : AppColors.textSecondary)
                }
                Text(title)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                Text("\(count)")
                    .font(AppTypography.monoMicro)
                    .foregroundStyle(isSelected ? accent : AppColors.textTertiary)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(isSelected ? AppColors.elevatedSurface : AppColors.stageBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? accent.opacity(0.55) : AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconForTag(_ tag: String) -> PictogrammersAsset? {
        switch tag {
        case "1 persona", "Individual": return .account
        case "2 personas", "Pareja": return .accountMultiple
        case "Grupo", "Grupo grande": return .accountGroup
        case "Brazos arriba": return .humanHandsUp
        case "De pie", "Sentado", "Cuerpo entero": return .humanStanding
        case "Ojos abiertos": return .eyeCheckOutline
        case "Ojos cerrados": return .eyeOffOutline
        case "Primer plano", "Plano medio", "Retrato": return .faceRecognition
        default: return nil
        }
    }
}

/// Compact tag badges rendered inside the photo HUD plus custom tag quick-add popover.
package struct VisionHudTagChips: View {
    let tags: PhotoVisionTags?
    let onAddCustomTag: (String) -> Void
    @State private var isPresentingAddTag = false
    @State private var draftTag = ""

    package init(tags: PhotoVisionTags?, onAddCustomTag: @escaping (String) -> Void) {
        self.tags = tags
        self.onAddCustomTag = onAddCustomTag
    }

    package var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let tags, !tags.allTags.isEmpty {
                ForEach(tags.allTags.prefix(6), id: \.self) { tag in
                    let isClosedEyes = tag == "Ojos cerrados"
                    Text(tag)
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(isClosedEyes ? AppColors.warningAmber : AppColors.textPrimary)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(isClosedEyes ? AppColors.warningAmberTint : AppColors.elevatedSurface)
                        .clipShape(Capsule())
                }
            } else {
                HStack(spacing: AppSpacing.xxs) {
                    PictogrammersIcon(.faceRecognition, size: 11)
                    Text("Analizando pose y caras...")
                        .font(AppTypography.micro)
                }
                .foregroundStyle(AppColors.textTertiary)
            }

            Button {
                isPresentingAddTag.toggle()
            } label: {
                HStack(spacing: 3) {
                    PictogrammersIcon(.tagMultipleOutline, size: 11)
                    Text("+ Etiqueta")
                        .font(AppTypography.micro)
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 2)
                .background(AppColors.elevatedSurface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresentingAddTag, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Agregar etiqueta manual (se guarda en .XMP)")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    HStack(spacing: AppSpacing.xs) {
                        TextField("Ej. Favorita, Novia, Saltando", text: $draftTag)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 190)
                            .onSubmit { submitTag() }
                        Button("Agregar") { submitTag() }
                            .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                    }
                }
                .padding(AppSpacing.md)
                .background(AppColors.panelSurface)
            }
        }
    }

    private func submitTag() {
        let trimmed = draftTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddCustomTag(trimmed)
        draftTag = ""
        isPresentingAddTag = false
    }
}
