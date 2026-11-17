import Foundation
@preconcurrency import ImageCaptureCore

struct ICCallbackTransfer<Value>: @unchecked Sendable {
    let value: Value
}

extension TetherCaptureService: ICCameraDeviceDelegate {
    private enum ICCReturnCodeValue {
        static let passcodeLocked = -9943              // ICReturnDeviceIsPasscodeLocked
        static let notAuthorized = -21343              // ICReturnConnectionNotAuthorizedToOpenDevice
        static let failedToOpenSession = -9927         // ICReturnDeviceFailedToOpenSession
        static let sessionAlreadyOpen = -21347         // ICReturnConnectionSessionAlreadyOpen
        static let legacyAlreadyOpen = -9914           // ICLegacyReturnCodeDeviceAlreadyOpenErr
    }

    nonisolated package func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)] else { return }
            let category = self.contexts[fp]?.profile.category
            if let nsErr = error as NSError? {
                if nsErr.code == ICCReturnCodeValue.sessionAlreadyOpen
                    || nsErr.code == ICCReturnCodeValue.legacyAlreadyOpen {
                    self.onStatusChanged?(fp, .busyByMacOS, nil)
                } else if category == .androidPTP {
                    self.onStatusChanged?(fp, .androidPermissionRequired, nil)
                } else if nsErr.code == ICCReturnCodeValue.passcodeLocked
                    || nsErr.code == ICCReturnCodeValue.notAuthorized {
                    self.onStatusChanged?(fp, .accessRestrictedLocked, nil)
                } else if nsErr.code == ICCReturnCodeValue.failedToOpenSession {
                    self.onStatusChanged?(fp, .busyByMacOS, nil)
                } else {
                    self.onStatusChanged?(fp, .error(message: nsErr.localizedDescription), nil)
                }
                let removed = self.contexts.removeValue(forKey: fp)
                removed?.openTimeoutTask?.cancel()
                removed?.deltaTask?.cancel()
                self.cameraToFingerprint.removeValue(forKey: ObjectIdentifier(device))
            } else if let cam = device as? ICCameraDevice {
                self.indexExistingCatalog(for: fp, camera: cam)
                if cam.contentCatalogPercentCompleted >= 100 {
                    self.finalizeCatalogAndStartWatcher(for: fp, camera: cam)
                }
            }
        }
    }

    nonisolated package func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)] else { return }
            self.finalizeCatalogAndStartWatcher(for: fp, camera: device)
        }
    }

    nonisolated package func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        let transfer = ICCallbackTransfer(value: items.compactMap { $0 as? ICCameraFile })
        let camTransfer = ICCallbackTransfer(value: camera)
        Task { @MainActor [weak self] in
            guard let self,
                  let fp = self.cameraToFingerprint[ObjectIdentifier(camTransfer.value)] else { return }
            self.evaluateIncomingFiles(transfer.value, for: fp, camera: camTransfer.value, fromLiveCallback: true)
        }
    }

    nonisolated package func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint.removeValue(forKey: ObjectIdentifier(device)) else { return }
            let ctx = self.contexts.removeValue(forKey: fp)
            ctx?.openTimeoutTask?.cancel()
            ctx?.deltaTask?.cancel()
            let nextStatus: DeviceConnectionStatus = (ctx?.profile.category == .androidPTP && error != nil)
                ? .androidPermissionRequired
                : .detectedNotConnected
            self.onStatusChanged?(fp, nextStatus, nil)
        }
    }

    nonisolated package func didRemove(_ device: ICDevice) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint.removeValue(forKey: ObjectIdentifier(device)) else { return }
            let ctx = self.contexts.removeValue(forKey: fp)
            ctx?.openTimeoutTask?.cancel()
            ctx?.deltaTask?.cancel()
            self.onStatusChanged?(fp, .disconnected(lastSeen: Date()), nil)
        }
    }

    nonisolated package func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)] else { return }
            self.onStatusChanged?(fp, .accessRestrictedLocked, nil)
        }
    }

    nonisolated package func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)],
                  let cam = device as? ICCameraDevice else { return }
            self.onStatusChanged?(fp, .connecting, nil)
            self.indexExistingCatalog(for: fp, camera: cam)
        }
    }

    nonisolated package func device(_ device: ICDevice, didEncounterError error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)], let error else { return }
            self.onCaptureError?(fp, error.localizedDescription)
        }
    }

    nonisolated package func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated package func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {}
    nonisolated package func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: (any Error)?) {}
    nonisolated package func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated package func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated package func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    // Constructed in `nonisolated` scope so Swift 6 does not assert `@MainActor` on `ICDeviceWriteQueue`.
    nonisolated static func startNonisolatedDownload(
        file: ICCameraFile,
        stagingDir: URL,
        filename: String,
        deleteAfter: Bool,
        completion: @escaping @Sendable (String?, String?) -> Void
    ) {
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: stagingDir,
            .saveAsFilename: filename,
            .overwrite: true,
            .deleteAfterSuccessfulDownload: deleteAfter,
            .sidecarFiles: false
        ]
        file.requestDownload(options: options) { savedFilename, error in
            completion(savedFilename, error?.localizedDescription)
        }
    }

    nonisolated static func startNonisolatedReadData(
        file: ICCameraFile,
        length: Int64,
        completion: @escaping @Sendable (Data?, String?) -> Void
    ) {
        file.requestReadData(atOffset: 0, length: length) { data, error in
            completion(data, error?.localizedDescription)
        }
    }

    nonisolated package static func dispatchWriteQueueCallbackForVerification(
        _ completion: @escaping @Sendable (String?, String?) -> Void
    ) {
        let queue = DispatchQueue(label: "ICDeviceWriteQueue")
        queue.async {
            completion("verified_off_main.jpg", nil)
        }
    }

    func keyForFile(_ file: ICCameraFile) -> String {
        TetherBaselineGate.itemKey(ptpHandle: file.ptpObjectHandle, filename: effectiveFilename(for: file), fileSize: Int64(file.fileSize))
    }

    func effectiveFilename(for file: ICCameraFile) -> String {
        file.originalFilename ?? file.name ?? "IMG_\(file.ptpObjectHandle).JPG"
    }

    func dateForFile(_ file: ICCameraFile) -> Date? {
        file.exifCreationDate ?? file.creationDate ?? file.fileCreationDate ?? file.modificationDate
    }

    func isHiddenDeviceFolder(_ file: ICCameraFile) -> Bool {
        var folder = file.parentFolder
        while let current = folder {
            if let name = current.name?.lowercased(),
               name.hasPrefix(".") || name == "thumbnails" {
                return true
            }
            folder = current.parentFolder
        }
        return false
    }

    func batteryValue(for camera: ICCameraDevice) -> Int? {
        camera.batteryLevelAvailable ? Int(camera.batteryLevel) : nil
    }
}
