import SwiftUI

/// Isolated right-side floating rounded inspector card showing full EXIF telemetry,
/// camera/lens details, file metrics, and AI/custom tags without obstructing the photo stage.
package struct PhotoInspectorCardView: View {
    let item: PhotoItem
    let currentIndex: Int
    let totalCount: Int
    let nativeSize: CGSize
    let onAddCustomTag: (String) -> Void
    let onRemoveCustomTag: (String) -> Void

    @State private var isPresentingAddTag = false
    @State private var draftTag = ""

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss · dd/MM/yyyy"
        return f
    }()

    package init(
        item: PhotoItem,
        currentIndex: Int,
        totalCount: Int,
        nativeSize: CGSize,
        onAddCustomTag: @escaping (String) -> Void,
        onRemoveCustomTag: @escaping (String) -> Void
    ) {
        self.item = item
        self.currentIndex = currentIndex
        self.totalCount = totalCount
        self.nativeSize = nativeSize
        self.onAddCustomTag = onAddCustomTag
        self.onRemoveCustomTag = onRemoveCustomTag
    }

    package var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                headerSection
                Divider().overlay(AppColors.borderSubtle)
                fileAndSensorSection
                Divider().overlay(AppColors.borderSubtle)
                exposureGridSection
                Divider().overlay(AppColors.borderSubtle)
                cameraAndLensSection
                Divider().overlay(AppColors.borderSubtle)
                tagsSection
            }
            .padding(AppSpacing.md)
        }
        .frame(width: 256)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .stroke(AppColors.borderStrong.opacity(0.65), lineWidth: AppSpacing.hairline)
        )
        .shadow(color: .black.opacity(0.32), radius: 14, x: 0, y: 6)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Foto \(currentIndex + 1) de \(totalCount)")
                    .font(AppTypography.monoMicro)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 3)
                    .background(AppColors.elevatedSurface)
                    .clipShape(Capsule())

                Spacer()

                Text(item.formatExtension)
                    .font(AppTypography.monoMicro)
                    .foregroundStyle(item.formatKind == .raw ? AppColors.warningAmber : AppColors.infoBlue)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 2)
                    .background(item.formatKind == .raw ? AppColors.warningAmberTint : AppColors.infoBlueTint)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))

                if item.pairedCompressedURL != nil {
                    Text("+JPG")
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(AppColors.approveGreen)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(AppColors.approveGreenTint)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                }
            }

            Text(item.filename)
                .font(AppTypography.monoCounter)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var fileAndSensorSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("ARCHIVO Y SENSOR")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textTertiary)

            metricRow(label: "Tamaño", value: item.formattedFileSize)
            metricRow(label: "Resolución", value: resolutionSummary)
            metricRow(label: "Captura", value: Self.timestampFormatter.string(from: item.capturedAt))
        }
    }

    private var exposureGridSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("PARÁMETROS DE DISPARO (EXIF)")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textTertiary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: AppSpacing.xs), GridItem(.flexible(), spacing: AppSpacing.xs)],
                spacing: AppSpacing.xs
            ) {
                exifTile(title: "ISO", value: item.exif.formattedISO ?? "—")
                exifTile(title: "Apertura", value: item.exif.formattedAperture ?? "—")
                exifTile(title: "Obturación", value: item.exif.formattedShutter ?? "—")
                exifTile(title: "Focal", value: item.exif.formattedFocalLength ?? "—")
            }
        }
    }

    private var cameraAndLensSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("EQUIPO FOTOGRÁFICO")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textTertiary)

            let cameraText: String = {
                switch (item.exif.cameraMake, item.exif.cameraModel) {
                case (let make?, let model?):
                    return model.localizedCaseInsensitiveContains(make) ? model : "\(make) \(model)"
                case (_, let model?):
                    return model
                case (let make?, nil):
                    return make
                case (nil, nil):
                    return item.sourceDeviceAlias ?? "USB / Disco"
                }
            }()
            metricRow(label: "Cámara", value: cameraText)
            if let lens = item.exif.lensModel, !lens.isEmpty {
                metricRow(label: "Lente", value: lens)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("ETIQUETAS IA Y .XMP")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
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
                    .padding(.vertical, 3)
                    .background(AppColors.elevatedSurface)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isPresentingAddTag, arrowEdge: .leading) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Agregar etiqueta manual (.XMP)")
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

            if let visionTags = item.visionTags, !visionTags.allTags.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 102), spacing: AppSpacing.xxs)],
                    alignment: .leading,
                    spacing: AppSpacing.xxs
                ) {
                    ForEach(visionTags.autoTags, id: \.self) { tag in
                        let isWarning = tag == "Ojos cerrados"
                        Text(tag)
                            .font(AppTypography.monoMicro)
                            .foregroundStyle(isWarning ? AppColors.warningAmber : AppColors.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 3)
                            .background(isWarning ? AppColors.warningAmberTint : AppColors.elevatedSurface)
                            .clipShape(Capsule())
                    }

                    ForEach(visionTags.customTags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(AppTypography.monoMicro)
                                .lineLimit(1)
                            Button {
                                onRemoveCustomTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(AppColors.infoBlue)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 3)
                        .background(AppColors.infoBlueTint)
                        .clipShape(Capsule())
                    }
                }
            } else {
                Text("Sin etiquetas detectadas aún.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private var resolutionSummary: String {
        if let dims = item.exif.formattedDimensions {
            let w = item.exif.pixelWidth ?? Int(nativeSize.width)
            let h = item.exif.pixelHeight ?? Int(nativeSize.height)
            let mp = Double(max(0, w * h)) / 1_000_000.0
            return mp >= 0.1 ? String(format: "%@ · %.1f MP", dims, mp) : dims
        }
        if nativeSize.width > 0 && nativeSize.height > 0 {
            let mp = (nativeSize.width * nativeSize.height) / 1_000_000.0
            return String(format: "%d×%d px · %.1f MP", Int(nativeSize.width), Int(nativeSize.height), mp)
        }
        return "—"
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(AppTypography.monoCaption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func exifTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.monoCaption)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.stageBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
    }

    private func submitTag() {
        let trimmed = draftTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddCustomTag(trimmed)
        draftTag = ""
        isPresentingAddTag = false
    }
}
