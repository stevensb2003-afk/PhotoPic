import SwiftUI

/// Modal sheet configuring how an existing Mac photo folder is segregated (`RAW/`, `JPG/`)
/// and imported into a managed PhotoPic session with optional batch Vision AI face detection.
package struct ImportSessionSheet: View {
    @Binding var sessionName: String
    @Binding var selectedGroup: String
    @Binding var tagsDraft: String
    @Binding var includeSubfolders: Bool
    @Binding var transferMode: FolderImportTransferMode
    @Binding var runVisionAIOnOpen: Bool

    let scanSummary: FolderImportScanSummary?
    let availableGroups: [String]
    let rootFolderURL: URL?
    let isScanning: Bool
    let isImporting: Bool
    let progress: FolderImportProgress?
    let errorMessage: String?

    let onChangeSourceFolder: () -> Void
    let onRescan: (URL, Bool) -> Void
    let onCancel: () -> Void
    let onConfirmImport: (String, String?, String) -> Void

    @State private var pickerChoice: String = ""
    @State private var customGroupDraft: String = ""

    package init(
        sessionName: Binding<String>,
        selectedGroup: Binding<String>,
        tagsDraft: Binding<String>,
        includeSubfolders: Binding<Bool>,
        transferMode: Binding<FolderImportTransferMode>,
        runVisionAIOnOpen: Binding<Bool>,
        scanSummary: FolderImportScanSummary?,
        availableGroups: [String],
        rootFolderURL: URL?,
        isScanning: Bool,
        isImporting: Bool,
        progress: FolderImportProgress?,
        errorMessage: String?,
        onChangeSourceFolder: @escaping () -> Void,
        onRescan: @escaping (URL, Bool) -> Void,
        onCancel: @escaping () -> Void,
        onConfirmImport: @escaping (String, String?, String) -> Void
    ) {
        self._sessionName = sessionName
        self._selectedGroup = selectedGroup
        self._tagsDraft = tagsDraft
        self._includeSubfolders = includeSubfolders
        self._transferMode = transferMode
        self._runVisionAIOnOpen = runVisionAIOnOpen
        self.scanSummary = scanSummary
        self.availableGroups = availableGroups
        self.rootFolderURL = rootFolderURL
        self.isScanning = isScanning
        self.isImporting = isImporting
        self.progress = progress
        self.errorMessage = errorMessage
        self.onChangeSourceFolder = onChangeSourceFolder
        self.onRescan = onRescan
        self.onCancel = onCancel
        self.onConfirmImport = onConfirmImport
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.xl)
                .padding(.bottom, AppSpacing.md)

            Divider().overlay(AppColors.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    sourceSummaryCard
                    sessionDetailsSection
                    transferAndAISection

                    if let rootFolderURL {
                        destinationPreviewSection(rootFolderURL: rootFolderURL)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.archiveRed)
                    }

                    if isImporting, let progress {
                        importProgressBanner(progress)
                    }
                }
                .padding(AppSpacing.xl)
            }

            Divider().overlay(AppColors.borderSubtle)

            footerActions
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.lg)
        }
        .frame(width: 560, height: 610)
        .background(AppColors.panelSurface)
        .onAppear {
            pickerChoice = SessionGroupPickerField.initialPickerChoice(
                selectedGroup: selectedGroup,
                availableGroups: availableGroups
            )
        }
    }

    private var headerSection: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.infoBlueTint)
                    .frame(width: 40, height: 40)
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.infoBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Importar carpeta como sesión")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Segrega RAW, pares JPG u otros formatos y prepara detección facial con IA.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var sourceSummaryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(AppColors.warningAmber)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scanSummary?.sourceURL.lastPathComponent ?? "Carpeta seleccionada")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    if let sourcePath = scanSummary?.sourceURL.path {
                        Text(sourcePath)
                            .font(AppTypography.monoMicro)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Button("Cambiar...", action: onChangeSourceFolder)
                    .buttonStyle(StudioButtonStyle(.secondaryDark, compact: true))
                    .disabled(isImporting)
                    .help("Elegir otra carpeta de tu Mac")
            }

            Divider().overlay(AppColors.borderSubtle)

            if isScanning {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Escaneando formatos RAW, JPG y HEIC...")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.vertical, AppSpacing.xs)
            } else if let summary = scanSummary {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.sm) {
                        summaryStatPill(
                            title: "Tomas",
                            value: "\(summary.totalPhotoUnitsCount)",
                            tint: AppColors.textPrimary
                        )
                        summaryStatPill(
                            title: "RAW → RAW/",
                            value: "\(summary.rawUnitsCount)",
                            tint: AppColors.warningAmber
                        )
                        summaryStatPill(
                            title: "Pares → JPG/",
                            value: "\(summary.pairedJpgCount)",
                            tint: AppColors.infoBlue
                        )
                        summaryStatPill(
                            title: "Otros → Filtrar",
                            value: "\(summary.standaloneCompressedCount)",
                            tint: AppColors.approveGreen
                        )
                        Spacer()
                        Text(summary.formattedTotalBytes)
                            .font(AppTypography.monoCaption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if !summary.extensionBreakdown.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.xs) {
                                ForEach(summary.extensionBreakdown) { entry in
                                    Text(".\(entry.ext) ×\(entry.count)")
                                        .font(AppTypography.monoMicro)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .padding(.horizontal, AppSpacing.xs)
                                        .padding(.vertical, 2)
                                        .background(AppColors.elevatedSurface)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }

    private func summaryStatPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(AppTypography.monoCounter)
                .foregroundStyle(tint)
            Text(title)
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
    }

    private var sessionDetailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Nombre de la sesión")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                TextField("Ej. Boda_Laura_RAW", text: $sessionName)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.body)
                    .disabled(isImporting)
            }

            SessionGroupPickerField(
                pickerChoice: $pickerChoice,
                customGroupDraft: $customGroupDraft,
                availableGroups: availableGroups
            )
            .disabled(isImporting)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Etiquetas iniciales (opcional, separadas por coma)")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)

                TextField("Ej. Cliente, Retratos, Exterior", text: $tagsDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.body)
                    .disabled(isImporting)
            }
        }
    }

    private var transferAndAISection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Cómo acomodar los archivos")
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppColors.textSecondary)

            Picker("Transferencia", selection: $transferMode) {
                ForEach(FolderImportTransferMode.allCases) { mode in
                    Text(mode.displayTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isImporting)

            Text(transferMode.subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)

            Toggle(isOn: Binding(
                get: { includeSubfolders },
                set: { newValue in
                    includeSubfolders = newValue
                    if let sourceURL = scanSummary?.sourceURL {
                        onRescan(sourceURL, newValue)
                    }
                }
            )) {
                Text("Incluir fotos dentro de subcarpetas")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .disabled(isImporting || scanSummary == nil)

            Toggle(isOn: $runVisionAIOnOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Detectar rostros, ojos cerrados y poses con IA al abrir")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Analiza toda la sesión automáticamente aunque estés en Modo Ligero.")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .disabled(isImporting)
        }
        .padding(AppSpacing.md)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }

    private func destinationPreviewSection(rootFolderURL: URL) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("Destino en tu Carpeta Raíz:")
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

    private func importProgressBanner(_ progress: FolderImportProgress) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
            HStack {
                Text("Acomodando \(progress.completedUnits) de \(progress.totalUnits)...")
                    .font(AppTypography.monoCaption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if !progress.currentFilename.isEmpty {
                    Text(progress.currentFilename)
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
    }

    private var footerActions: some View {
        HStack {
            Spacer()
            Button("Cancelar", action: onCancel)
                .buttonStyle(StudioButtonStyle(.ghost))
                .keyboardShortcut(.cancelAction)
                .disabled(isImporting)

            Button(isImporting ? "Importando..." : "Importar y abrir sesión") {
                submitIfValid()
            }
            .buttonStyle(StudioButtonStyle(.primaryLight))
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
    }

    private var resolvedGroupName: String? {
        SessionGroupPickerField.resolvedGroupName(
            pickerChoice: pickerChoice,
            customGroupDraft: customGroupDraft
        )
    }

    private var effectiveSessionName: String {
        sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isScanning &&
        !isImporting &&
        !effectiveSessionName.isEmpty &&
        (scanSummary?.units.isEmpty == false)
    }

    private func previewPath(rootFolderURL: URL) -> String {
        if let group = resolvedGroupName {
            return "\(rootFolderURL.path)/\(group)/\(effectiveSessionName)/{RAW, JPG, Para_Edicion, Archivadas}"
        }
        return "\(rootFolderURL.path)/\(effectiveSessionName)/{RAW, JPG, Para_Edicion, Archivadas}"
    }

    private func submitIfValid() {
        guard canSubmit else { return }
        selectedGroup = resolvedGroupName ?? ""
        onConfirmImport(effectiveSessionName, resolvedGroupName, tagsDraft)
    }
}
