import AppKit
import CoreGraphics
import SwiftUI

/// Transparent macOS AppKit gesture bridge capturing native trackpad pinch (`magnify`),
/// `Ctrl`/`⌘ + Scroll Wheel` zoom, and two-finger scroll panning inside its own bounds
/// without blocking SwiftUI `DragGesture` swipes or buttons.
package struct PhotoZoomGestureOverlay: NSViewRepresentable {
    let isZoomed: () -> Bool
    let onMagnify: (CGFloat) -> Void
    let onScrollZoom: (CGFloat, Bool) -> Void
    let onScrollPan: (CGSize) -> Void

    package init(
        isZoomed: @escaping () -> Bool,
        onMagnify: @escaping (CGFloat) -> Void,
        onScrollZoom: @escaping (CGFloat, Bool) -> Void,
        onScrollPan: @escaping (CGSize) -> Void
    ) {
        self.isZoomed = isZoomed
        self.onMagnify = onMagnify
        self.onScrollZoom = onScrollZoom
        self.onScrollPan = onScrollPan
    }

    package func makeNSView(context: Context) -> ZoomEventMonitorNSView {
        let view = ZoomEventMonitorNSView()
        view.isZoomed = isZoomed
        view.onMagnify = onMagnify
        view.onScrollZoom = onScrollZoom
        view.onScrollPan = onScrollPan
        return view
    }

    package func updateNSView(_ nsView: ZoomEventMonitorNSView, context: Context) {
        nsView.isZoomed = isZoomed
        nsView.onMagnify = onMagnify
        nsView.onScrollZoom = onScrollZoom
        nsView.onScrollPan = onScrollPan
    }
}

package final class ZoomEventMonitorNSView: NSView {
    var isZoomed: () -> Bool = { false }
    var onMagnify: (CGFloat) -> Void = { _ in }
    var onScrollZoom: (CGFloat, Bool) -> Void = { _, _ in }
    var onScrollPan: (CGSize) -> Void = { _ in }

    private nonisolated(unsafe) var monitor: Any?

    override package func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override package func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitorIfNeeded()
        } else {
            removeMonitor()
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
            guard let self,
                  let win = self.window,
                  event.window === win,
                  win.sheets.isEmpty,
                  !self.isHiddenOrHasHiddenAncestor else {
                return event
            }
            let localPoint = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(localPoint) else {
                return event
            }

            if event.type == .magnify {
                let delta = event.magnification
                MainActor.assumeIsolated {
                    self.onMagnify(delta)
                }
                return nil
            }

            if event.type == .scrollWheel {
                let mods = event.modifierFlags.intersection([.control, .command])
                if !mods.isEmpty {
                    let dy = event.scrollingDeltaY
                    let precise = event.hasPreciseScrollingDeltas
                    MainActor.assumeIsolated {
                        self.onScrollZoom(dy, precise)
                    }
                    return nil
                }

                let currentlyZoomed = MainActor.assumeIsolated { self.isZoomed() }
                if currentlyZoomed {
                    let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 14
                    let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 14
                    MainActor.assumeIsolated {
                        self.onScrollPan(CGSize(width: dx, height: dy))
                    }
                    return nil
                }
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

/// Reusable interactive zoom + pan photo canvas for `Seleccionadas` and `Archivadas` inspectors
/// (supports trackpad pinch, Ctrl/⌘ + scroll wheel, drag pan, double-click zoom, and +/- buttons).
package struct InteractiveZoomPhotoCanvas: View {
    let image: CGImage?
    let itemID: String
    let isLoading: Bool
    let emptyLabel: String

    @State private var zoomScale: CGFloat = 1.0
    @State private var committedPan: CGSize = .zero
    @State private var activePanDelta: CGSize = .zero

    package init(
        image: CGImage?,
        itemID: String,
        isLoading: Bool,
        emptyLabel: String
    ) {
        self.image = image
        self.itemID = itemID
        self.isLoading = isLoading
        self.emptyLabel = emptyLabel
    }

    package var body: some View {
        let totalPan = CGSize(
            width: committedPan.width + activePanDelta.width,
            height: committedPan.height + activePanDelta.height
        )

        ZStack {
            RawZoomableImageView(
                viewportImage: image,
                fullSensorImage: nil,
                nativeSize: image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero,
                isZoomedOneToOne: false,
                zoomScale: zoomScale,
                isLoadingViewport: isLoading,
                isLoadingFullSensor: false,
                panOffset: totalPan,
                normalizedAnchor: CGPoint(x: 0.5, y: 0.5),
                emptyLabel: emptyLabel,
                onResetZoom: { resetZoom() }
            )

            PhotoZoomGestureOverlay(
                isZoomed: { zoomScale > 1.01 },
                onMagnify: { delta in
                    applyScale(zoomScale * (1.0 + delta))
                },
                onScrollZoom: { dy, precise in
                    let factor = precise ? (1.0 + dy * 0.012) : (1.0 + dy * 0.08)
                    applyScale(zoomScale * max(0.5, min(2.0, factor)))
                },
                onScrollPan: { delta in
                    committedPan = CGSize(
                        width: committedPan.width + delta.width,
                        height: committedPan.height + delta.height
                    )
                }
            )

            if image != nil {
                floatingZoomControls
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard zoomScale > 1.01 else { return }
                    activePanDelta = value.translation
                }
                .onEnded { value in
                    guard zoomScale > 1.01 else {
                        activePanDelta = .zero
                        return
                    }
                    committedPan = CGSize(
                        width: committedPan.width + value.translation.width,
                        height: committedPan.height + value.translation.height
                    )
                    activePanDelta = .zero
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(AppMotion.quickEaseOut) {
                if zoomScale > 1.01 {
                    resetZoom()
                } else {
                    zoomScale = 2.5
                }
            }
        }
        .onChange(of: itemID) { _, _ in
            resetZoom()
        }
    }

    private var floatingZoomControls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: AppSpacing.xxs) {
                    Button {
                        withAnimation(AppMotion.quickEaseOut) {
                            applyScale(zoomScale / 1.35)
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .disabled(zoomScale <= 1.01)
                    .help("Alejar zoom (Ctrl + rueda abajo)")

                    Text("\(Int(round(zoomScale * 100)))%")
                        .font(AppTypography.monoMicro)
                        .foregroundStyle(zoomScale > 1.01 ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(minWidth: 38)

                    Button {
                        withAnimation(AppMotion.quickEaseOut) {
                            applyScale(zoomScale * 1.35)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .disabled(zoomScale >= 7.95)
                    .help("Acercar zoom (pellizco trackpad o Ctrl + rueda arriba)")

                    if zoomScale > 1.01 {
                        Divider().frame(height: 12)
                        Button {
                            withAnimation(AppMotion.quickEaseOut) { resetZoom() }
                        } label: {
                            Text("Ajustar")
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColors.infoBlue)
                        }
                        .buttonStyle(.plain)
                        .help("Restablecer vista completa (doble clic)")
                    }
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 5)
                .background(AppColors.hudBackdrop)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
                )
            }
            .padding(AppSpacing.md)
        }
    }

    private func applyScale(_ proposed: CGFloat) {
        let clamped = min(max(1.0, proposed), 8.0)
        zoomScale = clamped
        if clamped <= 1.01 {
            zoomScale = 1.0
            committedPan = .zero
            activePanDelta = .zero
        }
    }

    private func resetZoom() {
        zoomScale = 1.0
        committedPan = .zero
        activePanDelta = .zero
    }
}
