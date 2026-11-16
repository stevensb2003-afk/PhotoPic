import SwiftUI

/// Screen 1 (Step 2 of Guided Setup): Requests the Global Root Folder via NSOpenPanel.
package struct RootFolderOnboardingView: View {
    let embeddedInWizard: Bool
    let onChooseFolder: () -> Void
    let onBack: (() -> Void)?

    package init(
        embeddedInWizard: Bool = false,
        onChooseFolder: @escaping () -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self.embeddedInWizard = embeddedInWizard
        self.onChooseFolder = onChooseFolder
        self.onBack = onBack
    }

    package var body: some View {
        if embeddedInWizard {
            folderCardAndActions
        } else {
            ZStack {
                AppColors.windowCanvas.ignoresSafeArea()
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    standaloneHeader
                    folderCardAndActions
                }
                .frame(maxWidth: AppSpacing.onboardingMaxWidth)
                .padding(AppSpacing.xxl)
            }
        }
    }

    private var standaloneHeader: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.elevatedSurface)
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.borderStrong, lineWidth: AppSpacing.hairline)
                    )
                PictogrammersIcon(.cameraIris, size: 28)
                    .foregroundStyle(AppColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("PhotoPic")
                    .font(AppTypography.displayTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Estudio nativo de tethering y culling RAW con IA offline")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var folderCardAndActions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Paso 2: Elegí tu Carpeta Raíz Global")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Cada sesión creará automáticamente 4 subcarpetas organizadas en disco para tus disparos RAW y JPG sin depender de internet ni catálogos externos.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                folderTreePreview
            }
            .padding(AppSpacing.xl)
            .background(AppColors.panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
            )

            HStack {
                if let onBack {
                    Button("← Volver a Hardware e IA", action: onBack)
                        .buttonStyle(StudioButtonStyle(.secondaryDark))
                } else {
                    Label("Permiso permanente con Security-Scoped Bookmark", systemImage: "lock.shield")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Button(action: onChooseFolder) {
                    Label("Elegir Carpeta Raíz...", systemImage: "folder.badge.plus")
                }
                .buttonStyle(StudioButtonStyle(.primaryLight))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var folderTreePreview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            folderLine(icon: "folder.fill", name: "Sesiones_Tether/", detail: "Carpeta Raíz Global", tint: AppColors.textPrimary)
            folderLine(icon: "doc.richtext", name: "  └── RAW/", detail: "Cola pendiente (.CR2, .CR3, .DNG, .ARW, .NEF, .RAF)", tint: AppColors.warningAmber)
            folderLine(icon: "photo", name: "  └── JPG/", detail: "Copias comprimidas separadas automáticamente", tint: AppColors.textSecondary)
            folderLine(icon: "checkmark.circle.fill", name: "  └── Para_Edicion/", detail: "Aprobadas con Swipe Derecha / →", tint: AppColors.approveGreen)
            folderLine(icon: "archivebox", name: "  └── Archivadas/", detail: "Descartadas con Swipe Izquierda / ← (recuperables)", tint: AppColors.archiveRed)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }

    private func folderLine(icon: String, name: String, detail: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppTypography.caption)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(name)
                .font(AppTypography.monoCaption)
                .foregroundStyle(AppColors.textPrimary)
            Text(detail)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
        }
    }
}
