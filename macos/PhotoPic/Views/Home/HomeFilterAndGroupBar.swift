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
                    TextField("Buscar sesión, carpeta máster o etiqueta...", text: $searchQuery)
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
                    Label("Nueva Carpeta Máster", systemImage: "folder.badge.plus")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                .popover(isPresented: $isPresentingNewGroupPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Crear Carpeta Máster de Sesiones")
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Crea una carpeta contenedora en tu Raíz Global para agrupar sesiones (ej. Sesiones Navideñas 2026).")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: AppSpacing.xs) {
                            TextField("Ej. Sesiones Navideñas 2026", text: $newGroupDraft)
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
                        filterPill(
                            title: "Todas (\(totalSessionCount))",
                            icon: "square.grid.2x2",
                            isSelected: groupFilter == .all
                        ) {
                            groupFilter = .all
                        }

                        if hasUngroupedSessions && !masterGroups.isEmpty {
                            filterPill(
                                title: "Sin grupo (Raíz)",
                                icon: "folder",
                                isSelected: groupFilter == .ungrouped
                            ) {
                                groupFilter = (groupFilter == .ungrouped) ? .all : .ungrouped
                            }
                        }

                        ForEach(masterGroups, id: \.self) { group in
                            filterPill(
                                title: "\(group) (\(groupSessionCount(group)))",
                                icon: "folder.fill",
                                isSelected: groupFilter == .group(group)
                            ) {
                                groupFilter = (groupFilter == .group(group)) ? .all : .group(group)
                            }
                        }

                        if !availableTags.isEmpty {
                            Divider()
                                .frame(height: 16)
                                .padding(.horizontal, AppSpacing.xxs)

                            ForEach(availableTags, id: \.self) { tag in
                                let isTagActive = selectedTagFilter?.caseInsensitiveCompare(tag) == .orderedSame
                                Button {
                                    selectedTagFilter = isTagActive ? nil : tag
                                } label: {
                                    Text("#\(tag)")
                                        .font(AppTypography.monoMicro)
                                        .foregroundStyle(isTagActive ? AppColors.infoBlue : AppColors.textSecondary)
                                        .padding(.horizontal, AppSpacing.sm)
                                        .padding(.vertical, AppSpacing.xxs)
                                        .background(isTagActive ? AppColors.infoBlueTint : AppColors.panelSurface)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(
                                                    isTagActive ? AppColors.infoBlue.opacity(0.6) : AppColors.borderSubtle,
                                                    lineWidth: AppSpacing.hairline
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func filterPill(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: icon)
                    .font(AppTypography.micro)
                Text(title)
                    .font(AppTypography.captionMedium)
            }
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(isSelected ? AppColors.elevatedSurface : AppColors.panelSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppColors.borderStrong : AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private func submitGroup() {
        let trimmed = newGroupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreateMasterGroup(trimmed)
        newGroupDraft = ""
        isPresentingNewGroupPopover = false
    }
}
