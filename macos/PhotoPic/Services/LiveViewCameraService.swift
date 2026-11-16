import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Observation
import os
import UniformTypeIdentifiers

/// Discovered macOS UVC / HDMI-USB / Continuity / built-in video input source.
package struct LiveVideoSource: Identifiable, Sendable, Equatable, Hashable {
    package let id: String
    package let localizedName: String
    package let transportNote: String
    package let isExternal: Bool

    package init(id: String, localizedName: String, transportNote: String, isExternal: Bool) {
        self.id = id
        self.localizedName = localizedName
        self.transportNote = transportNote
        self.isExternal = isExternal
    }
}

/// Framing aspect guide overlay options on top of Live View.
package enum LiveAspectGuide: String, CaseIterable, Sendable, Identifiable {
    case none = "Sin recorte"
    case threeTwo = "3:2 Full Frame"
    case fourFive = "4:5 Retrato"
    case sixteenNine = "16:9 Cine"
    case oneOne = "1:1 Cuadrado"

    package var id: String { rawValue }

    package var aspectRatio: CGFloat? {
        switch self {
        case .none: return nil
        case .threeTwo: return 3.0 / 2.0
        case .fourFive: return 4.0 / 5.0
        case .sixteenNine: return 16.0 / 9.0
        case .oneOne: return 1.0
        }
    }
}

/// Native macOS AVFoundation UVC / HDMI-to-USB / Continuity Live View camera streamer.
@MainActor
@Observable
package final class LiveViewCameraService {
    private let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "LiveView")
    private let sessionWorker = CaptureSessionWorker()

    package private(set) var availableDevices: [LiveVideoSource] = []
    package var selectedDeviceID: String?
    package private(set) var isRunning = false
    package private(set) var currentFrame: CGImage?
    package private(set) var permissionDenied = false
    package var statusMessage: String?

    package var showThirdsGrid = true
    package var aspectGuide: LiveAspectGuide = .threeTwo
    package var mirrorHorizontally = false

    package init() {
        refreshDevices()
    }

    package func refreshDevices() {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.external, .builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.continuityCamera)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        let mapped = discovery.devices.map { device in
            let external = device.deviceType == .external || device.deviceType == .continuityCamera
            let note = device.deviceType == .continuityCamera
                ? "Continuity Wi-Fi/USB"
                : (device.deviceType == .external ? "UVC / Capturadora HDMI-USB" : "Cámara Mac")
            return LiveVideoSource(
                id: device.uniqueID,
                localizedName: device.localizedName,
                transportNote: note,
                isExternal: external
            )
        }
        .sorted { lhs, rhs in
            if lhs.isExternal != rhs.isExternal { return lhs.isExternal }
            return lhs.localizedName < rhs.localizedName
        }

        availableDevices = mapped
        if selectedDeviceID == nil || !mapped.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = mapped.first?.id
        }
    }

    package func start() async {
        refreshDevices()
        guard let deviceID = selectedDeviceID else {
            statusMessage = "No se detectó ninguna cámara UVC ni capturadora HDMI-USB conectada."
            return
        }

        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        if auth == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                permissionDenied = true
                statusMessage = "Permiso de cámara denegado en Ajustes del Sistema → Privacidad."
                return
            }
        } else if auth == .denied || auth == .restricted {
            permissionDenied = true
            statusMessage = "Permiso de cámara restringido en Ajustes del Sistema → Privacidad."
            return
        }

        permissionDenied = false
        statusMessage = nil
        isRunning = true

        let errorText = await sessionWorker.start(deviceID: deviceID) { [weak self] frame in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.currentFrame = frame
            }
        }
        if let errorText {
            isRunning = false
            statusMessage = errorText
            logger.error("Live view start failed: \(errorText, privacy: .public)")
        }
    }

    package func stop() {
        isRunning = false
        sessionWorker.stop()
    }

    package func captureReferenceJPEG(toStagingDirectory dir: URL? = nil) -> (url: URL, filename: String)? {
        guard let frame = currentFrame else { return nil }
        let targetDir = dir ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicLiveRefs", isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let stamp = Int(Date().timeIntervalSince1970)
        let filename = "LIVE_REF_\(stamp).JPG"
        let outURL = targetDir.appendingPathComponent(filename, isDirectory: false)
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.94]
        CGImageDestinationAddImage(dest, frame, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (outURL, filename)
    }

    package func injectExternalPreviewFrame(_ frame: CGImage) {
        currentFrame = frame
    }
}

private final class CaptureSessionWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.kairosvisuals.photopic.liveview", qos: .userInteractive)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var session: AVCaptureSession?
    private var onFrame: (@Sendable (CGImage) -> Void)?

    func start(deviceID: String, onFrame: @escaping @Sendable (CGImage) -> Void) async -> String? {
        self.onFrame = onFrame
        return await withCheckedContinuation { continuation in
            queue.async {
                self.stopInternal()
                guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                    continuation.resume(returning: "La cámara seleccionada ya no está disponible.")
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    let captureSession = AVCaptureSession()
                    captureSession.beginConfiguration()
                    if captureSession.canSetSessionPreset(.hd1280x720) {
                        captureSession.sessionPreset = .hd1280x720
                    }
                    guard captureSession.canAddInput(input) else {
                        continuation.resume(returning: "No se pudo conectar la entrada de video UVC/HDMI.")
                        return
                    }
                    captureSession.addInput(input)

                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                    ]
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard captureSession.canAddOutput(output) else {
                        continuation.resume(returning: "No se pudo iniciar la salida de video.")
                        return
                    }
                    captureSession.addOutput(output)
                    captureSession.commitConfiguration()
                    captureSession.startRunning()
                    self.session = captureSession
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.stopInternal()
        }
    }

    private func stopInternal() {
        if let active = session, active.isRunning {
            active.stopRunning()
        }
        session = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrame?(cgImage)
    }
}
