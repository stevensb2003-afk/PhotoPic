import AppKit
import CoreGraphics
import SwiftUI

/// Renders a GPU-decoded `CGImage` in fit-to-stage, continuous zoom+pan (`1.0x...8.0x`),
/// or true 1:1 pixel-for-pixel sensor inspection mode.
package struct RawZoomableImageView: View {
    let viewportImage: CGImage?
    let fullSensorImage: CGImage?
    let nativeSize: CGSize
    let isZoomedOneToOne: Bool
    let zoomScale: CGFloat
    let isLoadingViewport: Bool
    let isLoadingFullSensor: Bool
    let panOffset: CGSize
    let normalizedAnchor: CGPoint
    let emptyLabel: String
    let onResetZoom: (() -> Void)?

    package init(
        viewportImage: CGImage?,
        fullSensorImage: CGImage?,
        nativeSize: CGSize,
        isZoomedOneToOne: Bool,
        zoomScale: CGFloat = 1.0,
        isLoadingViewport: Bool,
        isLoadingFullSensor: Bool,
        panOffset: CGSize,
        normalizedAnchor: CGPoint,
        emptyLabel: String = "Sin vista previa disponible",
        onResetZoom: (() -> Void)? = nil
    ) {
        self.viewportImage = viewportImage
        self.fullSensorImage = fullSensorImage
        self.nativeSize = nativeSize
        self.isZoomedOneToOne = isZoomedOneToOne
        self.zoomScale = zoomScale
        self.isLoadingViewport = isLoadingViewport
        self.isLoadingFullSensor = isLoadingFullSensor
        self.panOffset = panOffset
        self.normalizedAnchor = normalizedAnchor
        self.emptyLabel = emptyLabel
        self.onResetZoom = onResetZoom
    }

    private var isContinuouslyZoomed: Bool {
        !isZoomedOneToOne && zoomScale > 1.01
    }

    package var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppColors.stageBackground

                if isZoomedOneToOne, let sensorImage = fullSensorImage ?? viewportImage {
                    oneToOneLayer(image: sensorImage, containerSize: proxy.size)
                } else if isContinuouslyZoomed, let zoomImage = fullSensorImage ?? viewportImage {
                    continuousZoomLayer(image: zoomImage, containerSize: proxy.size)
                } else if let fitImage = viewportImage {
                    Image(decorative: fitImage, scale: 1.0, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                } else if isLoadingViewport {
                    loadingPlaceholder(label: "Revelando sensor RAW en GPU...")
                } else {
                    loadingPlaceholder(label: emptyLabel)
                }

                if isZoomedOneToOne || isContinuouslyZoomed {
                    zoomOverlayBadge(containerSize: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func continuousZoomLayer(image: CGImage, containerSize: CGSize) -> some View {
        let imgW = max(1, CGFloat(image.width))
        let imgH = max(1, CGFloat(image.height))
        let fitScale = min(containerSize.width / imgW, containerSize.height / imgH)
        let scaledW = imgW * fitScale * zoomScale
        let scaledH = imgH * fitScale * zoomScale

        let maxPanX = max(0, (scaledW - containerSize.width) / 2.0)
        let maxPanY = max(0, (scaledH - containerSize.height) / 2.0)
        let clampedX = min(max(panOffset.width, -maxPanX), maxPanX)
        let clampedY = min(max(panOffset.height, -maxPanY), maxPanY)

        Image(decorative: image, scale: 1.0, orientation: .up)
            .resizable()
            .interpolation(.high)
            .frame(width: scaledW, height: scaledH)
            .offset(x: clampedX, y: clampedY)
    }

    @ViewBuilder
    private func oneToOneLayer(image: CGImage, containerSize: CGSize) -> some View {
        let backingScale = max(1.0, NSScreen.main?.backingScaleFactor ?? 2.0)
        // Map 1 real sensor pixel to 1 physical display pixel (or crisp 1pt scale on standard displays)
        let pixelWidth = CGFloat(image.width) / backingScale
        let pixelHeight = CGFloat(image.height) / backingScale

        let anchorShiftX = (0.5 - normalizedAnchor.x) * max(0, pixelWidth - containerSize.width)
        let anchorShiftY = (0.5 - normalizedAnchor.y) * max(0, pixelHeight - containerSize.height)
        let maxPanX = max(0, (pixelWidth - containerSize.width) / 2.0)
        let maxPanY = max(0, (pixelHeight - containerSize.height) / 2.0)

        let clampedX = min(max(anchorShiftX + panOffset.width, -maxPanX), maxPanX)
        let clampedY = min(max(anchorShiftY + panOffset.height, -maxPanY), maxPanY)

        Image(decorative: image, scale: backingScale, orientation: .up)
            .interpolation(.none)
            .frame(width: pixelWidth, height: pixelHeight)
            .offset(x: clampedX, y: clampedY)
    }

    private func zoomOverlayBadge(containerSize: CGSize) -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: AppSpacing.xs) {
                    if isLoadingFullSensor && fullSensorImage == nil {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Circle()
                            .fill(AppColors.infoBlue)
                            .frame(width: 6, height: 6)
                    }
                    Text(isZoomedOneToOne
                        ? "ZOOM 1:1 PÍXEL REAL"
                        : "ZOOM \(Int(round(zoomScale * 100)))% · ARRASTRÁ PARA MOVER")
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(AppColors.textPrimary)
                    if isZoomedOneToOne, nativeSize.width > 0 {
                        Text("\(Int(nativeSize.width))×\(Int(nativeSize.height))")
                            .font(AppTypography.monoMicro)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    if let onResetZoom {
                        Button("Esc", action: onResetZoom)
                            .buttonStyle(.plain)
                            .font(AppTypography.monoMicro)
                            .foregroundStyle(AppColors.infoBlue)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.hudBackdrop)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.infoBlue.opacity(0.45), lineWidth: AppSpacing.hairline)
                )
            }
            .padding(AppSpacing.md)
            Spacer()
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private func loadingPlaceholder(label: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            if isLoadingViewport {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: "photo")
                    .font(AppTypography.displayTitle)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
