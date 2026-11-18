import SwiftUI

/// Modal sheet to create a new shooting session folder (`RAW`, `JPG`, `Para_Edicion`, `Archivadas`),
/// optionally grouped inside a Master Category folder and tagged.
package struct NewSessionSheet: View {
    private static let newGroupSentinel = "__PHOTOPIC_NEW_GROUP__"

    @Binding var sessionName: String
    @Binding var selectedGroup: String
    @Binding var tagsDraft: String
    let availableGroups: [String]
    let rootFolderURL: URL?
    let errorMessage: String?
    let onCancel: () -> Void
    let onCreate: (String, String?, String) -> Void

    @State private var pickerChoice: String = ""
    @State private var customGroupDraft: String = ""

    package init(
        sessionName: Binding<String>,
        selectedGroup: Binding<String>,
        tagsDraft: Binding<String>,
        availableGroups: [String],
        rootFolderURL: URL?,
        errorMessage: String?,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (String, String?, String) -> Void
    ) {
        self._sessionName = sessionName
        self._selectedGroup = selectedGroup
        self._tagsDraft = tagsDraft
        self.availableGroups = availableGroups
        self.rootFolderURL = rootFolderURL
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onCreate = onCreate
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("Nueva sesión")
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Nombre de la sesión")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                TextField("Ej. Boda_Laura_Y_Mateo", text: $sessionName)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.body)
                    .onSubmit { submitIfValid() }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Grupo (opcional)")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                Picker("Grupo", selection: $pickerChoice) {
                    Text("Sin grupo").tag("")
                    ForEach(availableGroups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                    Text("+ Nuevo grupo...").tag(Self.newGroupSentinel)
                }
                .labelsHidden()

                if pickerChoice == Self.newGroupSentinel {
                    TextField("Ej. Bodas 2026", text: $customGroupDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTypography.body)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Etiquetas iniciales (opcional, separadas por coma)")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                TextField("Ej. Navidad, Familia, Estudio", text: $tagsDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.body)
            }

            if let rootFolderURL {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Estructura que se creará en disco:")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(previewPath(rootFolderURL: rootFolderURL))
                        .font(AppTypography.monoPath)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .padding(AppSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.stageBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.archiveRed)
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .buttonStyle(StudioButtonStyle(.ghost))
                    .keyboardShortcut(.cancelAction)

                Button("Crear sesión") {
                    submitIfValid()
                }
                .buttonStyle(StudioButtonStyle(.primaryLight))
                .keyboardShortcut(.defaultAction)
                .disabled(effectiveFolderName.isEmpty)
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 460)
        .background(AppColors.panelSurface)
        .onAppear {
            if !selectedGroup.isEmpty && availableGroups.contains(selectedGroup) {
                pickerChoice = selectedGroup
            } else {
                pickerChoice = ""
            }
        }
    }

    private var resolvedGroupName: String? {
        if pickerChoice == Self.newGroupSentinel {
            let trimmed = customGroupDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let trimmed = pickerChoice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var effectiveFolderName: String {
        sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func previewPath(rootFolderURL: URL) -> String {
        if let group = resolvedGroupName {
            return "\(rootFolderURL.path)/\(group)/\(effectiveFolderName)/{RAW, JPG, Para_Edicion, Archivadas}"
        }
        return "\(rootFolderURL.path)/\(effectiveFolderName)/{RAW, JPG, Para_Edicion, Archivadas}"
    }

    private func submitIfValid() {
        guard !effectiveFolderName.isEmpty else { return }
        selectedGroup = resolvedGroupName ?? ""
        onCreate(effectiveFolderName, resolvedGroupName, tagsDraft)
    }
}
