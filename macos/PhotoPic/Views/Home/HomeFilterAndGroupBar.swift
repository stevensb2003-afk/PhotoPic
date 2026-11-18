import SwiftUI

/// Search bar, Master Group filter pills, "+ Carpeta Máster" creator, and project tag filter bar.
package struct HomeFilterAndGroupBar: View {
    @Binding var searchQuery: String
    @Binding var groupFilter: SessionGroupFilter
    @Binding var selectedTagFilter: String?

    let masterGroups: [String]
    let availableTags: [String]
    let totalSessionCount: Int
    let hasUngroupedSessions: Bool
    let groupSessionCount: (String) -> Int
    let onCreateMasterGroup: (String) -> Void

    @State private var isPresentingNewGroupPopover = false
    @State private var newGroupDraft = ""

    package init(
        searchQuery: Binding<String>,
        groupFilter: Binding<SessionGroupFilter>,
        selectedTagFilter: Binding<String?>,
        masterGroups: [String],
        availableTags: [String],
        totalSessionCount: Int,
        hasUngroupedSessions: Bool,
        groupSessionCount: @escaping (String) -> Int,
        onCreateMasterGroup: @escaping (String) -> Void
    ) {
        self._searchQuery = searchQuery
        self._groupFilter = groupFilter
        self._selectedTagFilter = selectedTagFilter
        self.masterGroups = masterGroups
        self.availableTags = availableTags
        self.totalSessionCount = totalSessionCount
        self.hasUngroupedSessions = hasUngroupedSessions
        self.groupSessionCount = groupSessionCount
        self.onCreateMasterGroup = onCreateMasterGroup
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    TextField("Buscar sesión, grupo o etiqueta...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Limpiar búsqueda")
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.panelSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
                )

                Button {
                    isPresentingNewGroupPopover.toggle()
                } label: {
                    Label("Crear grupo", systemImage: "folder.badge.plus")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .help("Crear un grupo para organizar sesiones")
                .popover(isPresented: $isPresentingNewGroupPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Crear grupo")
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Agrupá sesiones de un mismo cliente, campaña o evento.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: AppSpacing.xs) {
                            TextField("Ej. Bodas 2026", text: $newGroupDraft)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { submitGroup() }
                            Button("Crear") { submitGroup() }
                                .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(width: 310)
                    .background(AppColors.panelSurface)
                }
            }

            if !masterGroups.isEmpty || !availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        GroupFilterPill(
                            title: "Todas (\(totalSessionCount))",
                            icon: "square.grid.2x2",
                            isSelected: groupFilter == .all
                        ) {
                            groupFilter = .all
                        }
                        .help("Ver todos los grupos y sesiones")

                        if hasUngroupedSessions && !masterGroups.isEmpty {
                            GroupFilterPill(
                                title: "Sin grupo",
                                icon: "tray",
                                isSelected: groupFilter == .ungrouped
                            ) {
                                groupFilter = (groupFilter == .ungrouped) ? .all : .ungrouped
                            }
                            .help("Mostrar solo sesiones sin grupo")
                        }

                        ForEach(masterGroups, id: \.self) { group in
                            GroupFilterPill(
                                title: "\(group) (\(groupSessionCount(group)))",
                                icon: "rectangle.stack.fill",
                                isSelected: groupFilter == .group(group)
                            ) {
                                groupFilter = (groupFilter == .group(group)) ? .all : .group(group)
                            }
                            .help("Entrar al grupo \(group)")
                        }

                        if !availableTags.isEmpty {
                            Divider()
                                .frame(height: 16)
                                .padding(.horizontal, AppSpacing.xxs)

                            ForEach(availableTags, id: \.self) { tag in
                                let isTagActive = selectedTagFilter?.caseInsensitiveCompare(tag) == .orderedSame
                                TagFilterPill(tag: tag, isActive: isTagActive) {
                                    selectedTagFilter = isTagActive ? nil : tag
                                }
                                .help("Filtrar sesiones con la etiqueta #\(tag)")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func submitGroup() {
        let trimmed = newGroupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreateMasterGroup(trimmed)
        newGroupDraft = ""
        isPresentingNewGroupPopover = false
    }
}

private struct GroupFilterPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: icon)
                    .font(AppTypography.micro)
                Text(title)
                    .font(AppTypography.captionMedium)
            }
            .foregroundStyle(isSelected || isHovered ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(isSelected ? AppColors.elevatedSurface : (isHovered ? AppColors.controlHover : AppColors.panelSurface))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected || isHovered ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct TagFilterPill: View {
    let tag: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(AppTypography.monoMicro)
                .foregroundStyle(isActive ? AppColors.infoBlue : (isHovered ? AppColors.textPrimary : AppColors.textSecondary))
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(isActive ? AppColors.infoBlueTint : (isHovered ? AppColors.controlHover : AppColors.panelSurface))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isActive ? AppColors.infoBlue.opacity(0.6) : (isHovered ? AppColors.borderStrong : AppColors.borderSubtle),
                            lineWidth: AppSpacing.hairline
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
