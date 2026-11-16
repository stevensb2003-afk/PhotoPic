import CoreGraphics
import Foundation
import ImageIO
import Observation

/// Optional single-USB bridge to system `gphoto2` (Homebrew) for classic DSLRs such as
/// Canon EOS 70D that lack UVC USB Streaming, cleanly isolated without bundling external binaries.
@MainActor
@Observable
package final class GPhoto2LiveBridge {
    private static let candidatePaths = [
        "/opt/homebrew/bin/gphoto2",
        "/usr/local/bin/gphoto2",
    ]

    package private(set) var executablePath: String?
    package private(set) var isStreaming = false
    package private(set) var statusNote: String?

    private var streamTask: Task<Void, Never>?

    package var isAvailable: Bool {
        executablePath != nil
    }

    package init() {
        refreshAvailability()
    }

    package func refreshAvailability() {
        let fm = FileManager.default
        executablePath = Self.candidatePaths.first { fm.isExecutableFile(atPath: $0) }
    }

    package func startPreviewStream(
        onFrame: @escaping @MainActor (CGImage) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        refreshAvailability()
        guard let bin = executablePath else {
            onError("gphoto2 no está instalado en este Mac. Usá Live View UVC/HDMI o instalalo con Homebrew: brew install gphoto2")
            return
        }
        stopPreviewStream()
        isStreaming = true
        statusNote = "Transmitiendo visor USB vía gphoto2..."

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicGPhotoPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        streamTask = Task { [weak self] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                if let frame = await Self.captureSinglePreviewFrame(executable: bin, workDir: workDir) {
                    consecutiveFailures = 0
                    onFrame(frame)
                } else {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 4 {
                        onError("gphoto2 no pudo leer el visor Live View USB de la cámara. Verificá que la cámara soporte Live View USB y no esté bloqueada por otro proceso.")
                        break
                    }
                }
                try? await Task.sleep(for: .milliseconds(90))
            }
            self?.isStreaming = false
        }
    }

    package func stopPreviewStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        statusNote = nil
    }

    package func triggerCaptureAndDownload() async -> [URL] {
        refreshAvailability()
        guard let bin = executablePath else { return [] }
        let wasStreaming = isStreaming
        if wasStreaming {
            streamTask?.cancel()
            streamTask = nil
        }

        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicGPhotoShots_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let success = await Self.runCommand(
            executable: bin,
            arguments: ["--capture-image-and-download", "--filename", "%f.%C"],
            workingDirectory: outDir
        )
        guard success else { return [] }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: outDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { MediaFormatClassifier.isSupportedImage(url: $0) }
    }

    private static func captureSinglePreviewFrame(executable: String, workDir: URL) async -> CGImage? {
        let targetFile = workDir.appendingPathComponent("capture_preview.jpg", isDirectory: false)
        try? FileManager.default.removeItem(at: targetFile)
        let ok = await runCommand(
            executable: executable,
            arguments: ["--capture-preview", "--force-overwrite"],
            workingDirectory: workDir
        )
        guard ok,
              let data = try? Data(contentsOf: targetFile),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func runCommand(executable: String, arguments: [String], workingDirectory: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = arguments
            proc.currentDirectoryURL = workingDirectory
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }
}
