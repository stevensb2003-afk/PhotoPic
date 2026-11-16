import AppKit
import SwiftUI

/// Settings Tab 2: Global Root Folder configuration and visual summary of studio shortcuts.
package struct GeneralSettingsView: View {
    let rootFolderURL: URL?
    let onChangeRootFolder: () -> Void

    package init(rootFolderURL: URL?, onChangeRootFolder: @escaping () -> Void) {
        self.rootFolderURL = rootFolderURL
        self.onChangeRootFolder = onChangeRootFolder
    }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                rootFolderSection
                shortcutsSummarySection
            }
            .padding(AppSpacing.xl)
        }
    }

    private var rootFolderSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Carpeta Raíz Global")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(rootFolderURL?.path ?? "Sin carpeta configurada")
                    .font(AppTypography.monoPath)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.stageBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

                HStack(spacing: AppSpacing.sm) {
                    Button("Cambiar carpeta...", action: onChangeRootFolder)
                        .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))

                    if let rootFolderURL {
                        Button("Abrir en Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([rootFolderURL])
                        }
                        .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(AppColors.panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
        }
    }

    private var shortcutsSummarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Atajos de Teclado y Gestos en Estudio")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            VStack(spacing: AppSpacing.xs) {
                shortcutRow(keys: ["↑", "↓"], title: "Navegar cola pendiente sin mover archivos")
                shortcutRow(keys: ["←"], title: "Archivar foto actual (mueve a Archivadas/)")
                shortcutRow(keys: ["→"], title: "Aprobar foto actual (mueve a Para_Edicion/)")
                shortcutRow(keys: ["Espacio"], title: "Activar / salir de Zoom 1:1 píxel real")
                shortcutRow(keys: ["Clic + Arrastrar"], title: "Lupa 1:1 instantánea al sostener sobre detalles")
                shortcutRow(keys: ["⌘Z"], title: "Deshacer última clasificación (restaura a RAW/)")
            }
            .padding(AppSpacing.md)
            .background(AppColors.panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )
        }
    }

    private func shortcutRow(keys: [String], title: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            HStack(spacing: AppSpacing.xxs) {
                ForEach(keys, id: \.self) { key in
                    KeycapBadge(key)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
