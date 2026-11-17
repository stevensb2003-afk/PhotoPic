import Foundation
@preconcurrency import ImageCaptureCore
import os

/// Handles live PTP sessions, real-time `cameraDevice(_:didAdd:)` callbacks,
/// Smart Delta Watcher polling (1.5s), and atomic staging downloads.
@MainActor
package final class TetherCaptureService: NSObject {
    struct ActiveCameraContext {
        let camera: ICCameraDevice
        var profile: KnownDevice
        var gate: TetherBaselineGate
        var openTimeoutTask: Task<Void, Never>?
        var deltaTask: Task<Void, Never>?
        var activeDownloads: Int = 0
    }

    let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "TetherCapture")
    var contexts: [String: ActiveCameraContext] = [:]
    var cameraToFingerprint: [ObjectIdentifier: String] = [:]

    package var onStatusChanged: ((String, DeviceConnectionStatus, Int?) -> Void)?
    package var onFileStaged: ((URL, String, KnownDevice) -> Void)?
    package var onCaptureError: ((String, String) -> Void)?

    package func openSession(for camera: ICCameraDevice, profile: KnownDevice) {
        let fingerprint = profile.fingerprint
        if let previous = contexts[fingerprint] {
            previous.openTimeoutTask?.cancel()
            previous.deltaTask?.cancel()
        }

        let gate = TetherBaselineGate(connectedAtTimestamp: Date())
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(4500))
            guard !Task.isCancelled else { return }
            self?.handleOpenSessionTimeout(for: fingerprint, category: profile.category)
        }
        contexts[fingerprint] = ActiveCameraContext(
            camera: camera, profile: profile, gate: gate, openTimeoutTask: timeoutTask
        )
        cameraToFingerprint[ObjectIdentifier(camera)] = fingerprint

        camera.delegate = self
        if camera.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue) {
            camera.mediaPresentation = .originalAssets
        }

        onStatusChanged?(fingerprint, .connecting, batteryValue(for: camera))
        camera.requestOpenSession()
    }

    package func closeSession(for fingerprint: String) {
        guard let ctx = contexts.removeValue(forKey: fingerprint) else { return }
        ctx.openTimeoutTask?.cancel()
        ctx.deltaTask?.cancel()
        cameraToFingerprint.removeValue(forKey: ObjectIdentifier(ctx.camera))
        if ctx.camera.hasOpenSession {
            ctx.camera.requestCloseSession()
        }
    }

    package func updateProfile(_ profile: KnownDevice) {
        contexts[profile.fingerprint]?.profile = profile
    }

    package func canTriggerRemoteShutter(for fingerprint: String) -> Bool {
        guard let camera = contexts[fingerprint]?.camera, camera.hasOpenSession else { return false }
        return camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanTakePicture.rawValue)
    }

    package func triggerRemoteShutter(for fingerprint: String) -> Bool {
        guard let camera = contexts[fingerprint]?.camera,
              camera.hasOpenSession,
              camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanTakePicture.rawValue) else {
            return false
        }
        camera.requestTakePicture()
        return true
    }

    // MARK: - Baseline Indexing & Smart Delta Watcher

    func indexExistingCatalog(for fingerprint: String, camera: ICCameraDevice) {
        guard var ctx = contexts[fingerprint] else { return }
        let items = (camera.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        for file in items {
            ctx.gate.recordPreCatalogItem(key: keyForFile(file), itemDate: dateForFile(file))
        }
        contexts[fingerprint] = ctx
    }

    func finalizeCatalogAndStartWatcher(for fingerprint: String, camera: ICCameraDevice) {
        contexts[fingerprint]?.openTimeoutTask?.cancel()
        contexts[fingerprint]?.openTimeoutTask = nil

        if let ctx = contexts[fingerprint],
           ctx.profile.category == .androidPTP,
           (camera.mediaFiles ?? []).isEmpty,
           (camera.contents ?? []).isEmpty {
            logger.warning("Android PTP ready with empty catalog; likely Charging-only or access denied")
            contexts.removeValue(forKey: fingerprint)
            cameraToFingerprint.removeValue(forKey: ObjectIdentifier(camera))
            if camera.hasOpenSession { camera.requestCloseSession() }
            onStatusChanged?(fingerprint, .androidPermissionRequired, batteryValue(for: camera))
            return
        }

        indexExistingCatalog(for: fingerprint, camera: camera)
        guard var ctx = contexts[fingerprint] else { return }
        ctx.gate.markCatalogComplete()
        ctx.deltaTask?.cancel()
        ctx.deltaTask = Task { [weak self, weak camera] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled, let self, let camera else { break }
                self.scanMediaFilesDelta(for: fingerprint, camera: camera)
            }
        }
        contexts[fingerprint] = ctx
        onStatusChanged?(fingerprint, .connectedReady, batteryValue(for: camera))
    }

    private func scanMediaFilesDelta(for fingerprint: String, camera: ICCameraDevice) {
        guard contexts[fingerprint]?.gate.isCatalogComplete == true else { return }
        let files = (camera.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        evaluateIncomingFiles(files, for: fingerprint, camera: camera, fromLiveCallback: false)
    }

    func evaluateIncomingFiles(
        _ files: [ICCameraFile],
        for fingerprint: String,
        camera: ICCameraDevice,
        fromLiveCallback: Bool
    ) {
        guard var ctx = contexts[fingerprint] else { return }
        var approved: [ICCameraFile] = []

        for file in files {
            let filename = effectiveFilename(for: file)
            guard MediaFormatClassifier.classify(filename: filename) != nil else { continue }
            let key = keyForFile(file)
            let date = dateForFile(file)

            if !ctx.gate.isCatalogComplete {
                ctx.gate.recordPreCatalogItem(key: key, itemDate: date)
            } else if ctx.gate.shouldDownloadLiveItem(
                key: key,
                itemDate: date,
                wasAddedAfterCatalog: fromLiveCallback && file.wasAddedAfterContentCatalogCompleted
            ) {
                approved.append(file)
            }
        }
        contexts[fingerprint] = ctx

        for file in approved {
            downloadFileToStaging(file, from: camera, fingerprint: fingerprint)
        }
    }

    // MARK: - Staging Download & ReadData Fallback

    private func downloadFileToStaging(_ file: ICCameraFile, from camera: ICCameraDevice, fingerprint: String) {
        guard var ctx = contexts[fingerprint] else { return }
        ctx.activeDownloads += 1
        let activeCount = ctx.activeDownloads
        let deleteFromDevice = !ctx.profile.keepOriginalsOnDevice
        contexts[fingerprint] = ctx

        onStatusChanged?(fingerprint, .capturing(activeDownloads: activeCount), batteryValue(for: camera))

        let filename = effectiveFilename(for: file)
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicStaging/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let fileBox = ICCallbackTransfer(value: file)
        Self.startNonisolatedDownload(
            file: file,
            stagingDir: stagingDir,
            filename: filename,
            deleteAfter: deleteFromDevice
        ) { [weak self, fileBox] savedFilename, errorMessage in
            Task { @MainActor [weak self, fileBox] in
                guard let self else { return }
                let activeCamera = self.contexts[fingerprint]?.camera
                let stagedURL = stagingDir.appendingPathComponent(savedFilename ?? filename)
                if errorMessage == nil, FileManager.default.fileExists(atPath: stagedURL.path) {
                    self.completeDownload(stagedURL: stagedURL, filename: filename, stagingDir: stagingDir, fingerprint: fingerprint, camera: activeCamera)
                } else {
                    self.logger.warning("requestDownload fallback to requestReadData for \(filename, privacy: .public)")
                    self.fallbackReadDataDownload(fileBox.value, filename: filename, stagingDir: stagingDir, deleteAfter: deleteFromDevice, fingerprint: fingerprint, camera: activeCamera)
                }
            }
        }
    }

    private func fallbackReadDataDownload(
        _ file: ICCameraFile,
        filename: String,
        stagingDir: URL,
        deleteAfter: Bool,
        fingerprint: String,
        camera: ICCameraDevice?
    ) {
        let targetLength = file.fileSize
        guard targetLength > 0 else {
            finishDownloadState(fingerprint: fingerprint, camera: camera, stagingDir: stagingDir)
            return
        }

        let handle = file.ptpObjectHandle
        Self.startNonisolatedReadData(file: file, length: targetLength) { [weak self] data, errorMessage in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let activeCamera = self.contexts[fingerprint]?.camera
                if let data, !data.isEmpty, errorMessage == nil {
                    let stagedURL = stagingDir.appendingPathComponent(filename)
                    do {
                        try data.write(to: stagedURL, options: .atomic)
                        if deleteAfter, let activeCamera,
                           activeCamera.capabilities.contains(ICDeviceCapability.cameraDeviceCanDeleteOneFile.rawValue),
                           let targetFile = (activeCamera.mediaFiles ?? [])
                            .compactMap({ $0 as? ICCameraFile })
                            .first(where: { $0.ptpObjectHandle == handle && self.effectiveFilename(for: $0) == filename }) {
                            activeCamera.requestDeleteFiles([targetFile])
                        }
                        self.completeDownload(stagedURL: stagedURL, filename: filename, stagingDir: stagingDir, fingerprint: fingerprint, camera: activeCamera)
                        return
                    } catch {
                        self.onCaptureError?(fingerprint, error.localizedDescription)
                    }
                } else if let errorMessage {
                    self.onCaptureError?(fingerprint, errorMessage)
                }
                self.finishDownloadState(fingerprint: fingerprint, camera: activeCamera, stagingDir: stagingDir)
            }
        }
    }

    private func handleOpenSessionTimeout(for fingerprint: String, category: DeviceCategory) {
        guard let ctx = contexts[fingerprint], !ctx.gate.isCatalogComplete else { return }
        contexts.removeValue(forKey: fingerprint)
        cameraToFingerprint.removeValue(forKey: ObjectIdentifier(ctx.camera))
        if ctx.camera.hasOpenSession {
            ctx.camera.requestCloseSession()
        }
        let nextStatus: DeviceConnectionStatus = category == .androidPTP
            ? .androidPermissionRequired
            : .error(message: "Tiempo de espera agotado al abrir sesión PTP.")
        onStatusChanged?(fingerprint, nextStatus, batteryValue(for: ctx.camera))
    }

    private func completeDownload(stagedURL: URL, filename: String, stagingDir: URL, fingerprint: String, camera: ICCameraDevice?) {
        if let profile = contexts[fingerprint]?.profile {
            onFileStaged?(stagedURL, filename, profile)
        }
        finishDownloadState(fingerprint: fingerprint, camera: camera, stagingDir: stagingDir)
    }

    private func finishDownloadState(fingerprint: String, camera: ICCameraDevice?, stagingDir: URL) {
        try? FileManager.default.removeItem(at: stagingDir)
        guard var ctx = contexts[fingerprint] else { return }
        ctx.activeDownloads = max(0, ctx.activeDownloads - 1)
        let remaining = ctx.activeDownloads
        contexts[fingerprint] = ctx
        let status: DeviceConnectionStatus = remaining > 0 ? .capturing(activeDownloads: remaining) : .connectedReady
        onStatusChanged?(fingerprint, status, camera.flatMap { batteryValue(for: $0) })
    }

    private func keyForFile(_ file: ICCameraFile) -> String {
        TetherBaselineGate.itemKey(ptpHandle: file.ptpObjectHandle, filename: effectiveFilename(for: file), fileSize: Int64(file.fileSize))
    }

    private func effectiveFilename(for file: ICCameraFile) -> String {
        file.originalFilename ?? file.name ?? "IMG_\(file.ptpObjectHandle).JPG"
    }

    private func dateForFile(_ file: ICCameraFile) -> Date? {
        file.exifCreationDate ?? file.creationDate ?? file.fileCreationDate ?? file.modificationDate
    }

    private func batteryValue(for camera: ICCameraDevice) -> Int? {
        camera.batteryLevelAvailable ? Int(camera.batteryLevel) : nil
    }
}
