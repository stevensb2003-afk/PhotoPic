import SwiftUI

/// Central RAW culling stage combining unobstructed GPU image display,
/// horizontal swipe gestures, spring-loaded 1:1 hold-and-drag loupe,
/// and an isolated right-side floating PhotoInspectorCardView.
package struct TinderCardStackView: View {
    @Bindable var viewModel: CullingSessionViewModel
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var swipeOffsetX: CGFloat = 0
    @State private var swipeOpacity: Double = 1.0
    @State private var cardEntranceScale: CGFloat = 1.0
    @State private var committedPanOffset: CGSize = .zero
    @State private var activePanDelta: CGSize = .zero
    @State private var holdZoomTask: Task<Void, Never>?
    @State private var swipeCommitTask: Task<Void, Never>?
    @State private var inFlightDirection: Int?
    @State private var isDraggingHorizontally = false

    package init(viewModel: CullingSessionViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        ZStack {
            AppColors.stageBackground

            if let item = viewModel.currentPendingItem {
                HStack(spacing: AppSpacing.md) {
                    GeometryReader { stageProxy in
                        cardStage(for: item, size: stageProxy.size)
                            .frame(width: stageProxy.size.width, height: stageProxy.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    PhotoInspectorCardView(
                        item: item,
                        currentIndex: viewModel.currentIndex,
                        totalCount: viewModel.visiblePendingItems.count,
                        nativeSize: viewModel.activeNativeSize,
                        onAddCustomTag: { tag in viewModel.addCustomTag(tag, to: item) },
                        onRemoveCustomTag: { tag in viewModel.removeCustomTag(tag, from: item) }
                    )
                    .padding(.vertical, AppSpacing.md)
                    .padding(.trailing, AppSpacing.lg)
                }
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
        .onChange(of: viewModel.currentIndex) { _, _ in
            committedPanOffset = .zero
            activePanDelta = .zero
            if inFlightDirection == nil {
                swipeOffsetX = 0
                swipeOpacity = 1.0
            }
        }
        .onChange(of: viewModel.pendingSwipeAnimation) { _, cmd in
            guard let cmd else { return }
            runAnimatedSwipeThrow(direction: cmd.direction)
        }
        .onDisappear {
            if let dir = inFlightDirection {
                swipeCommitTask?.cancel()
                swipeCommitTask = nil
                inFlightDirection = nil
                commitImmediateWithoutAnimation(direction: dir)
            }
        }
        .onChange(of: viewModel.isAnyZoomActive) { _, active in
            if !active {
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

        return ZStack {
            RawZoomableImageView(
                viewportImage: viewModel.activeViewportImage,
                fullSensorImage: viewModel.activeFullSensorImage,
                nativeSize: viewModel.activeNativeSize,
                isZoomedOneToOne: viewModel.isLockedOneToOneZoom || viewModel.isSpringLoadedZoom,
                zoomScale: viewModel.customZoomScale,
                isLoadingViewport: viewModel.isRenderingViewport,
                isLoadingFullSensor: viewModel.isRenderingFullSensor,
                panOffset: totalPan,
                normalizedAnchor: viewModel.zoomNormalizedAnchor,
                onResetZoom: { viewModel.resetZoomState() }
            )

            PhotoZoomGestureOverlay(
                isZoomed: { viewModel.isAnyZoomActive },
                onMagnify: { delta in
                    viewModel.applyInteractiveZoom(scaleMultiplier: 1.0 + delta)
                },
                onScrollZoom: { dy, precise in
                    let factor = precise ? (1.0 + dy * 0.012) : (1.0 + dy * 0.08)
                    viewModel.applyInteractiveZoom(scaleMultiplier: max(0.5, min(2.0, factor)))
                },
                onScrollPan: { delta in
                    committedPanOffset = CGSize(
                        width: committedPanOffset.width + delta.width,
                        height: committedPanOffset.height + delta.height
                    )
                }
            )

            swipeIntentStamp
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(cardBorderColor, lineWidth: AppSpacing.hairline)
        )
        .padding([.vertical, .leading], AppSpacing.md)
        .scaleEffect(cardEntranceScale)
        .opacity(swipeOpacity)
        .offset(x: viewModel.isAnyZoomActive ? 0 : swipeOffsetX)
        .rotationEffect(.degrees(rotationDegrees))
        .contentShape(Rectangle())
        .gesture(stageInteractionGesture(stageSize: size))
    }

    private func runAnimatedSwipeThrow(direction: Int) {
        // Rapid-fire support: if user taps ←/→ again mid-animation, commit the previous card immediately.
        if let prevDir = inFlightDirection {
            swipeCommitTask?.cancel()
            swipeCommitTask = nil
            inFlightDirection = nil
            commitImmediateWithoutAnimation(direction: prevDir)
        }

        guard viewModel.currentPendingItem != nil else { return }
        if viewModel.isAnyZoomActive {
            viewModel.resetZoomState()
        }

        inFlightDirection = direction
        let throwDistance: CGFloat = reduceMotion ? 0 : CGFloat(direction) * 440

        withAnimation(AppMotion.resolve(AppMotion.cardCommitThrow, reduceMotion: reduceMotion)) {
            swipeOffsetX = throwDistance
            swipeOpacity = 0.0
        }

        swipeCommitTask = Task { @MainActor in
            let delayMs = reduceMotion ? 90 : 175
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            let dir = inFlightDirection ?? direction
            inFlightDirection = nil
            swipeCommitTask = nil
            commitImmediateWithoutAnimation(direction: dir)
        }
    }

    private func commitImmediateWithoutAnimation(direction: Int) {
        var noAnim = Transaction()
        noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            swipeOffsetX = 0
            swipeOpacity = 0.0
            cardEntranceScale = reduceMotion ? 1.0 : 0.965
        }
        if direction > 0 {
            viewModel.approveCurrentToEditing()
        } else {
            viewModel.archiveCurrent()
        }
        withAnimation(AppMotion.resolve(AppMotion.quickEaseOut, reduceMotion: reduceMotion)) {
            swipeOpacity = 1.0
            cardEntranceScale = 1.0
        }
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
                    runAnimatedSwipeThrow(direction: 1)
                } else if projected < -AppMotion.swipeDistanceThreshold {
                    runAnimatedSwipeThrow(direction: -1)
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

    private var emptyQueueState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "camera.viewfinder")
                .font(AppTypography.displayTitle)
                .foregroundStyle(AppColors.textTertiary)

            Text("Cola de pendientes vacía")
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("Dispará con tu cámara o celular conectado por USB, o importá una carpeta de tu Mac para segregar RAW/JPG y detectar rostros con IA.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            if let appState {
                Button {
                    appState.importPhotosIntoActiveSessionFromPicker()
                } label: {
                    Label("Importar carpeta a esta sesión", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(StudioButtonStyle(.secondaryDark))
                .help("Seleccionar una carpeta de tu Mac y organizar sus RAW/JPG en esta sesión (⌘I)")
                .padding(.top, AppSpacing.xs)
            }
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
