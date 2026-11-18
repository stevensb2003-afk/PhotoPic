import SwiftUI

/// Context-aware empty/setup stage inside Live View explaining exact requirements
/// for Android, iPhone Continuity Camera, and DSLR/Mirrorless cameras.
package struct LiveViewCompatibilityCard: View {
    let connectedDevice: ConnectedDeviceState?
    let modeTitle: String
    let explanation: String
    let feedbackMessage: String?
    let isActive: Bool
    let isOpticalHotShoeFlashMode: Bool
    let onToggle: () -> Void
    let onActivateDemo: (() -> Void)?

    package init(
        connectedDevice: ConnectedDeviceState?,
        modeTitle: String,
        explanation: String,
        feedbackMessage: String?,
        isActive: Bool,
        isOpticalHotShoeFlashMode: Bool = false,
        onToggle: @escaping () -> Void,
        onActivateDemo: (() -> Void)? = nil
    ) {
        self.connectedDevice = connectedDevice
        self.modeTitle = modeTitle
        self.explanation = explanation
        self.feedbackMessage = feedbackMessage
        self.isActive = isActive
        self.isOpticalHotShoeFlashMode = isOpticalHotShoeFlashMode
        self.onToggle = onToggle
        self.onActivateDemo = onActivateDemo
    }

    package var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                if isOpticalHotShoeFlashMode {
                    opticalHotShoeStageCard
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(AppTypography.displayTitle)
                        .foregroundStyle(AppColors.textTertiary)

                    Text(modeTitle)
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(explanation)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)

                    if connectedDevice?.category == .androidPTP {
                        androidPtpWarningBanner
                    }

                    if let feedbackMessage {
                        Text(feedbackMessage)
                            .font(AppTypography.monoCaption)
                            .foregroundStyle(AppColors.infoBlue)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: AppSpacing.sm) {
                        Button(isActive ? "Detener" : "Iniciar Vista en Vivo", action: onToggle)
                            .buttonStyle(StudioButtonStyle(.primaryLight))
                            .help(isActive ? "Detener Vista en Vivo" : "Iniciar transmisión en vivo del dispositivo conectado")

                        if connectedDevice == nil, let onActivateDemo {
                            Button(action: onActivateDemo) {
                                Label("Ver demo interactiva", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(StudioButtonStyle(.secondaryDark))
                            .help("Explorar controles simulando una Canon EOS 70D")
                        }
                    }
                    .padding(.top, AppSpacing.xs)

                    if connectedDevice != nil {
                        compatibilityColumns
                            .padding(.top, AppSpacing.sm)
                    } else {
                        DisclosureGroup("Ver guía de conexión por tipo de dispositivo") {
                            compatibilityColumns
                                .padding(.top, AppSpacing.sm)
                        }
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: 780)
                        .padding(.top, AppSpacing.md)
                    }
                }
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: .infinity)
        }
    }

    private var opticalHotShoeStageCard: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(AppColors.approveGreenTint)
                    .frame(width: 64, height: 64)
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppColors.approveGreen)
            }

            Text("Modo Flash Externo de Zapata Activo")
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("El espejo está abajo para que tu flash externo en la zapata superior sincronice en cada disparo. La conexión USB sigue activa y cada foto capturada aparece automáticamente en PhotoPic.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            HStack(spacing: AppSpacing.sm) {
                Label("Flash interno bloqueado (Seguro)", systemImage: "checkmark.shield.fill")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.approveGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.approveGreenTint)
                    .clipShape(Capsule())

                Label("USB Canon conectado", systemImage: "cable.connector")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.infoBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.infoBlueTint)
                    .clipShape(Capsule())
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(AppTypography.monoCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Volver a Vista en Vivo", action: onToggle)
                .buttonStyle(StudioButtonStyle(.primaryLight))
                .padding(.top, AppSpacing.xs)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: 640)
        .background(AppColors.panelSurface)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.borderStrong, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var androidPtpWarningBanner: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.warningAmber)
            Text("Tu Android está en modo PTP de transferencia de fotos — no envía video por PTP; usá 'Android / IP Wi-Fi' arriba en paralelo mientras el cable sigue pasando tus fotos RAW/JPG, o activá Camo / DroidCam / 'Webcam USB' en Pixel o Moto.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: 680, alignment: .leading)
        .background(AppColors.warningAmberTint)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.warningAmber.opacity(0.45), lineWidth: AppSpacing.hairline)
        )
    }

    private var compatibilityColumns: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            guideColumn(
                icon: "smartphone",
                title: "Android",
                points: [
                    "PTP/MTP USB solo transfiere fotos, NO video.",
                    "Usá el selector 'Android / IP Wi-Fi' (IP Webcam :8080/video o DroidCam :4747/video) en paralelo.",
                    "Samsung bloquea 'Webcam USB' nativo; Pixel/Moto Android 14+ sí aparecen en UVC."
                ]
            )
            guideColumn(
                icon: "iphone",
                title: "iPhone (iOS)",
                points: [
                    "Sí aparece automático en UVC/HDMI con Cámara de Continuidad de macOS.",
                    "Mismo Apple ID, Bluetooth y Wi-Fi activos cerca del Mac (o por USB).",
                    "Compatible en paralelo mientras usás tus sesiones."
                ]
            )
            guideColumn(
                icon: "camera.fill",
                title: "Cámaras DSLR / Mirrorless",
                points: [
                    "Canon EOS por cable USB directo (Live View, controles y zapata segura).",
                    "DJI Osmo, GoPro o cámaras con USB Streaming salen directo en 'UVC / HDMI'.",
                    "Capturadora HDMI→USB: 30–60 fps sin cortar la descarga RAW por PTP."
                ]
            )
        }
        .frame(maxWidth: 780)
    }

    private func guideColumn(icon: String, title: String, points: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.infoBlue)
                Text(title)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPrimary)
            }
            ForEach(points, id: \.self) { point in
                Text("• \(point)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }
}

package struct LiveThirdsGridOverlay: View {
    package init() {}
    package var body: some View {
        GeometryReader { g in
            Path { path in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3.0
                    let y = g.size.height * CGFloat(i) / 3.0
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: g.size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }
            .stroke(AppColors.borderStrong, lineWidth: AppSpacing.hairline)
        }
        .allowsHitTesting(false)
    }
}

package struct LiveAspectMaskOverlay: View {
    let containerSize: CGSize
    let targetRatio: CGFloat
    package init(containerSize: CGSize, targetRatio: CGFloat) {
        self.containerSize = containerSize
        self.targetRatio = targetRatio
    }
    package var body: some View {
        let currentRatio = containerSize.width / max(1, containerSize.height)
        let boxW = currentRatio > targetRatio ? containerSize.height * targetRatio : containerSize.width * 0.92
        let boxH = boxW / targetRatio
        RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
            .stroke(AppColors.warningAmber, lineWidth: 1.5)
            .frame(width: boxW, height: boxH)
            .allowsHitTesting(false)
    }
}
