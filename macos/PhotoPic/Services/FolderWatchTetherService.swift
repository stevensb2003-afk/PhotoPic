import AppKit
import Foundation
import os

/// Monitors any user-selected folder (Wi-Fi transmitter output, FTP server dropbox,
/// EOS Utility / NX Tether, or USB-C SD/CFexpress card) using `TetherBaselineGate`
/// so pre-existing files are never ingested and newly arriving shots enter live.
@MainActor
@Observable
package final class FolderWatchTetherService {
    private let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "FolderWatch")
    private var watchTask: Task<Void, Never>?
    private var gate: TetherBaselineGate?
    private var pendingSizes: [String: Int64] = [:]
    private var ingestedKeys: Set<String> = []

    package private(set) var watchedFolderURL: URL?
    package var onFileReady: ((URL, String, KnownDevice) -> Void)?

    package init() {}

    package func presentFolderPickerAndAttach(
        blockingSubtreeOf forbiddenRoot: URL? = nil,
        onRejected: ((String) -> Void)? = nil
    ) {
        let panel = NSOpenPanel()
        panel.title = "Vincular Carpeta / Transmisor Wi-Fi"
        panel.message = "Elegí la carpeta donde tu transmisor Wi-Fi, FTP o lector SD/USB deposita las fotos nuevas."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let forbiddenRoot {
            let chosenPath = url.standardizedFileURL.path
            let rootPath = forbiddenRoot.standardizedFileURL.path
            if chosenPath == rootPath || chosenPath.hasPrefix(rootPath + "/") {
                onRejected?("Elegí una carpeta externa (no dentro de tu Carpeta Raíz de sesiones) para evitar bucles.")
                return
            }
        }
        attach(folderURL: url)
    }

    package func attach(folderURL: URL) {
        detach()
        watchedFolderURL = folderURL
        pendingSizes.removeAll()
        ingestedKeys.removeAll()

        var newGate = TetherBaselineGate(connectedAtTimestamp: Date())
        for fileURL in listSupportedFiles(in: folderURL) {
            let size = fileSize(of: fileURL)
            let key = TetherBaselineGate.itemKey(
                ptpHandle: 0,
                filename: fileURL.lastPathComponent,
                fileSize: size
            )
            newGate.recordPreCatalogItem(key: key, itemDate: Date.distantPast)
        }
        newGate.markCatalogComplete()
        self.gate = newGate

        let deviceProfile = KnownDevice(
            id: "watch:\(folderURL.standardizedFileURL.path)",
            displayName: folderURL.lastPathComponent,
            alias: "Watch · \(folderURL.lastPathComponent)",
            category: .dslrMirrorless,
            autoConnectOnPlug: true,
            keepOriginalsOnDevice: true,
            allowJpgWhenNoRaw: true
        )

        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled else { break }
                await self.pollOnce(folderURL: folderURL, profile: deviceProfile)
            }
        }
        logger.info("Watchfolder attached: \(folderURL.path, privacy: .public)")
    }

    package func detach() {
        watchTask?.cancel()
        watchTask = nil
        watchedFolderURL = nil
        gate = nil
        pendingSizes.removeAll()
        ingestedKeys.removeAll()
    }

    private func pollOnce(folderURL: URL, profile: KnownDevice) async {
        guard var currentGate = gate else { return }
        let fm = FileManager.default
        let stagingDir = fm.temporaryDirectory.appendingPathComponent("PhotoPicWatchStage", isDirectory: true)
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        for fileURL in listSupportedFiles(in: folderURL) {
            let size = fileSize(of: fileURL)
            guard size > 0 else { continue }
            let key = TetherBaselineGate.itemKey(
                ptpHandle: 0,
                filename: fileURL.lastPathComponent,
                fileSize: size
            )
            if ingestedKeys.contains(key) { continue }
            if currentGate.baselineKeys.contains(key) { continue }

            // Wait one poll cycle for file size stability so partial Wi-Fi writes aren't read early.
            if pendingSizes[fileURL.path] != size {
                pendingSizes[fileURL.path] = size
                continue
            }

            guard currentGate.shouldDownloadLiveItem(
                key: key,
                itemDate: Date(),
                wasAddedAfterCatalog: true
            ) else {
                continue
            }

            pendingSizes.removeValue(forKey: fileURL.path)
            ingestedKeys.insert(key)
            let stagedURL = stagingDir.appendingPathComponent("\(UUID().uuidString)_\(fileURL.lastPathComponent)")
            do {
                try fm.copyItem(at: fileURL, to: stagedURL)
                onFileReady?(stagedURL, fileURL.lastPathComponent, profile)
            } catch {
                logger.warning("Watchfolder copy skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
        self.gate = currentGate
    }

    private func listSupportedFiles(in folderURL: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter { MediaFormatClassifier.isSupportedImage(url: $0) }
    }

    private func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
