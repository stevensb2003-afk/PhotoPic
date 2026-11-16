import SwiftUI

/// Modal sheet to create a new shooting session folder (`RAW`, `JPG`, `Para_Edicion`, `Archivadas`).
package struct NewSessionSheet: View {
    @Binding var sessionName: String
    let rootFolderURL: URL?
    let errorMessage: String?
    let onCancel: () -> Void
    let onCreate: (String) -> Void

    package init(
        sessionName: Binding<String>,
        rootFolderURL: URL?,
        errorMessage: String?,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (String) -> Void
    ) {
        self._sessionName = sessionName
        self.rootFolderURL = rootFolderURL
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onCreate = onCreate
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("Nueva Sesión de Filtrado")
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Nombre de la sesión")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                TextField("Ej. Boda_Laura_Y_Mateo", text: $sessionName)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.body)
                    .onSubmit {
                        submitIfValid()
                    }
            }

            if let rootFolderURL {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Estructura que se creará en disco:")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text("\(rootFolderURL.path)/\(effectiveFolderName)/{RAW, JPG, Para_Edicion, Archivadas}")
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

                Button("Crear y Abrir Estudio") {
                    submitIfValid()
                }
                .buttonStyle(StudioButtonStyle(.primaryLight))
                .keyboardShortcut(.defaultAction)
                .disabled(effectiveFolderName.isEmpty)
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: AppSpacing.newSessionSheetWidth)
        .background(AppColors.panelSurface)
    }

    private var effectiveFolderName: String {
        sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitIfValid() {
        guard !effectiveFolderName.isEmpty else { return }
        onCreate(effectiveFolderName)
    }
}
