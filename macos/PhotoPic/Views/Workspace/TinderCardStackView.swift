import SwiftUI

/// Central RAW culling stage combining GPU image display, minimalist EXIF HUD,
/// horizontal swipe gestures, and spring-loaded 1:1 hold-and-drag loupe.
package struct TinderCardStackView: View {
    @Bindable var viewModel: CullingSessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var swipeOffsetX: CGFloat = 0
    @State private var committedPanOffset: CGSize = .zero
    @State private var activePanDelta: CGSize = .zero
    @State private var holdZoomTask: Task<Void, Never>?
    @State private var isDraggingHorizontally = false

    package init(viewModel: CullingSessionViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppColors.stageBackground

                if let item = viewModel.currentPendingItem {
                    cardStage(for: item, size: proxy.size)
                } else {
                    emptyQueueState
                }

                if let pill = viewModel.feedbackPill {
                    VStack {
                        feedbackPillView(pill)
                            .padding(.top, AppSpacing.lg)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onChange(of: viewModel.currentIndex) { _, _ in
            committedPanOffset = .zero
            activePanDelta = .zero
            swipeOffsetX = 0
        }
        .onChange(of: viewModel.isLockedOneToOneZoom) { _, isLocked in
            if !isLocked {
                committedPanOffset = .zero
                activePanDelta = .zero
            }
        }
    }

    private func cardStage(for item: PhotoItem, size: CGSize) -> some View {
        let totalPan = CGSize(
            width: committedPanOffset.width + activePanDelta.width,
            height: committedPanOffset.height + activePanDelta.height
        )
        let rotationDegrees = viewModel.isAnyZoomActive ? 0.0 : Double(max(-6, min(6, swipeOffsetX / 48)))

        return ZStack(alignment: .bottomLeading) {
            RawZoomableImageView(
                viewportImage: viewModel.activeViewportImage,
                fullSensorImage: viewModel.activeFullSensorImage,
                nativeSize: viewModel.activeNativeSize,
                isZoomedOneToOne: viewModel.isAnyZoomActive,
                isLoadingViewport: viewModel.isRenderingViewport,
                isLoadingFullSensor: viewModel.isRenderingFullSensor,
                panOffset: totalPan,
                normalizedAnchor: viewModel.zoomNormalizedAnchor
            )

            swipeIntentStamp
            minimalistHudOverlay(for: item)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(cardBorderColor, lineWidth: AppSpacing.hairline)
        )
        .padding(AppSpacing.md)
        .offset(x: viewModel.isAnyZoomActive ? 0 : swipeOffsetX)
        .rotationEffect(.degrees(rotationDegrees))
        .contentShape(Rectangle())
        .gesture(stageInteractionGesture(stageSize: size))
    }

    private func stageInteractionGesture(stageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if viewModel.isAnyZoomActive {
                    activePanDelta = value.translation
                    return
                }

                let distance = hypot(value.translation.width, value.translation.height)
                if !isDraggingHorizontally && distance < 6 {
                    if holdZoomTask == nil {
                        let normX = max(0, min(1, value.location.x / max(1, stageSize.width)))
                        let normY = max(0, min(1, value.location.y / max(1, stageSize.height)))
                        holdZoomTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(165))
                            guard !Task.isCancelled else { return }
                            viewModel.engageSpringLoadedZoom(normalizedAnchor: CGPoint(x: normX, y: normY))
                        }
                    }
                    return
                }

                holdZoomTask?.cancel()
                holdZoomTask = nil
                isDraggingHorizontally = true
                swipeOffsetX = AppMotion.rubberBand(value.translation.width, limit: 280)
            }
            .onEnded { value in
                holdZoomTask?.cancel()
                holdZoomTask = nil

                if viewModel.isSpringLoadedZoom {
                    viewModel.releaseSpringLoadedZoom()
                    committedPanOffset = .zero
                    activePanDelta = .zero
                    isDraggingHorizontally = false
                    return
                }

                if viewModel.isLockedOneToOneZoom {
                    committedPanOffset = CGSize(
                        width: committedPanOffset.width + activePanDelta.width,
                        height: committedPanOffset.height + activePanDelta.height
                    )
                    activePanDelta = .zero
                    isDraggingHorizontally = false
                    return
                }

                isDraggingHorizontally = false
                let projected = AppMotion.projectedOffsetX(
                    current: swipeOffsetX,
                    velocityX: value.velocity.width
                )

                if projected > AppMotion.swipeDistanceThreshold {
                    swipeOffsetX = 0
                    viewModel.approveCurrentToEditing()
                } else if projected < -AppMotion.swipeDistanceThreshold {
                    swipeOffsetX = 0
                    viewModel.archiveCurrent()
                } else {
                    withAnimation(AppMotion.resolve(AppMotion.cardSnapBack, reduceMotion: reduceMotion)) {
                        swipeOffsetX = 0
                    }
                }
            }
    }

    @ViewBuilder
    private var swipeIntentStamp: some View {
        if !viewModel.isAnyZoomActive, abs(swipeOffsetX) > 28 {
            let isRight = swipeOffsetX > 0
            let progress = min(1.0, (abs(swipeOffsetX) - 28) / 80.0)
            VStack {
                HStack {
                    if !isRight { Spacer() }
                    Text(isRight ? "PARA EDICIÓN" : "ARCHIVAR")
                        .font(AppTypography.monoCounter)
                        .foregroundStyle(isRight ? AppColors.approveGreen : AppColors.archiveRed)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.hudBackdrop)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .stroke(isRight ? AppColors.approveGreen : AppColors.archiveRed, lineWidth: AppSpacing.hairline)
                        )
                        .opacity(progress)
                    if isRight { Spacer() }
                }
                .padding(AppSpacing.xl)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    private func minimalistHudOverlay(for item: PhotoItem) -> some View {
        HStack(alignment: .bottom, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    Text(item.filename)
                        .font(AppTypography.monoCounter)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(item.formatExtension)
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(item.formatKind == .raw ? AppColors.warningAmber : AppColors.infoBlue)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(item.formatKind == .raw ? AppColors.warningAmberTint : AppColors.infoBlueTint)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))

                    if let alias = item.sourceDeviceAlias, !alias.isEmpty {
                        Text(alias)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                HStack(spacing: AppSpacing.sm) {
                    Text(item.exif.compactHudSummary)
                        .font(AppTypography.monoCaption)
                        .foregroundStyle(AppColors.textSecondary)

                    if let dimensions = item.exif.formattedDimensions {
                        Text("· \(dimensions)")
                            .font(AppTypography.monoCaption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                VisionHudTagChips(tags: item.visionTags) { customTag in
                    viewModel.addCustomTag(customTag, to: item)
                }
            }

            Spacer()

            Text("Foto \(viewModel.currentIndex + 1) de \(viewModel.visiblePendingItems.count) pendientes")
                .font(AppTypography.monoCaption)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.elevatedSurface)
                .clipShape(Capsule())
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(AppColors.hudBackdrop)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
        .padding(AppSpacing.lg)
    }

    private var emptyQueueState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "camera.viewfinder")
                .font(AppTypography.displayTitle)
                .foregroundStyle(AppColors.textTertiary)

            Text("Cola de pendientes vacía")
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("Dispará con tu cámara o celular conectado por USB. Cada RAW (.CR2, .CR3, .DNG, .ARW, .NEF, .RAF) aparecerá aquí al instante.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(AppSpacing.xxl)
    }

    private func feedbackPillView(_ pill: CullingFeedbackPill) -> some View {
        let tint: Color = switch pill.kind {
        case .approved, .recovered: AppColors.approveGreen
        case .archived, .deletedPermanently: AppColors.archiveRed
        case .undone: AppColors.warningAmber
        case .liveCaptured: AppColors.infoBlue
        }

        return FloatingToastBanner(message: pill.text, iconName: "bolt.fill", tint: tint)
    }

    private var cardBorderColor: Color {
        if swipeOffsetX > 36 { return AppColors.approveGreen.opacity(0.6) }
        if swipeOffsetX < -36 { return AppColors.archiveRed.opacity(0.6) }
        return AppColors.borderSubtle
    }
}
