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
            self.contexts[fp]?.openTimeoutTask?.cancel()
            self.contexts[fp]?.openTimeoutTask = nil
            let category = self.contexts[fp]?.profile.category

            if let nsErr = error as NSError? {
                if nsErr.code == ICCReturnCodeValue.sessionAlreadyOpen
                    || nsErr.code == ICCReturnCodeValue.legacyAlreadyOpen {
                    self.removeContextCompletely(for: device, fingerprint: fp)
                    self.onStatusChanged?(fp, .busyByMacOS, nil)
                } else if (nsErr.code == ICCReturnCodeValue.passcodeLocked
                    || nsErr.code == ICCReturnCodeValue.notAuthorized) && category != .androidPTP {
                    // Keep context/mapping alive so `cameraDeviceDidRemoveAccessRestriction` recovers on iPhone unlock.
                    self.contexts[fp]?.lastStatus = .accessRestrictedLocked
                    self.onStatusChanged?(fp, .accessRestrictedLocked, nil)
                } else if category == .androidPTP {
                    self.removeContextCompletely(for: device, fingerprint: fp)
                    self.onStatusChanged?(fp, .androidPermissionRequired, nil)
                } else if nsErr.code == ICCReturnCodeValue.failedToOpenSession {
                    self.removeContextCompletely(for: device, fingerprint: fp)
                    self.onStatusChanged?(fp, .busyByMacOS, nil)
                } else {
                    self.removeContextCompletely(for: device, fingerprint: fp)
                    self.onStatusChanged?(fp, .error(message: nsErr.localizedDescription), nil)
                }
            } else if let cam = device as? ICCameraDevice {
                if cam.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue),
                   cam.mediaPresentation != .originalAssets {
                    cam.mediaPresentation = .originalAssets
                }
                self.indexExistingCatalog(for: fp, camera: cam)
                if cam.contentCatalogPercentCompleted >= 100 {
                    self.finalizeCatalogAndStartWatcher(for: fp, camera: cam)
                } else {
                    self.startCatalogWatchdog(for: fp, category: category ?? .dslrMirrorless)
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
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)] else { return }
            if let ctx = self.contexts[fp],
               ctx.profile.category == .iPhoneIOS && ctx.lastStatus == .accessRestrictedLocked {
                self.cancelWatchdogs(for: fp)
                self.onStatusChanged?(fp, .accessRestrictedLocked, nil)
                return
            }
            let removed = self.removeContextCompletely(for: device, fingerprint: fp)
            let nextStatus: DeviceConnectionStatus = (removed?.profile.category == .androidPTP && error != nil)
                ? .androidPermissionRequired
                : .detectedNotConnected
            self.onStatusChanged?(fp, nextStatus, nil)
        }
    }

    nonisolated package func didRemove(_ device: ICDevice) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)] else { return }
            _ = self.removeContextCompletely(for: device, fingerprint: fp)
            self.onStatusChanged?(fp, .disconnected(lastSeen: Date()), nil)
        }
    }

    nonisolated package func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)] else { return }
            self.cancelWatchdogs(for: fp)
            self.contexts[fp]?.lastStatus = .accessRestrictedLocked
            self.onStatusChanged?(fp, .accessRestrictedLocked, nil)
        }
    }

    nonisolated package func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint[ObjectIdentifier(device)],
                  let cam = device as? ICCameraDevice else { return }
            let category = self.contexts[fp]?.profile.category ?? .iPhoneIOS
            self.contexts[fp]?.lastStatus = .connecting
            self.onStatusChanged?(fp, .connecting, self.batteryValue(for: cam))
            if cam.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue) {
                cam.mediaPresentation = .originalAssets
            }
            if !cam.hasOpenSession {
                self.startOpenWatchdog(for: fp, category: category)
                cam.requestOpenSession()
            } else if cam.contentCatalogPercentCompleted >= 100 {
                self.finalizeCatalogAndStartWatcher(for: fp, camera: cam)
            } else {
                self.indexExistingCatalog(for: fp, camera: cam)
                self.startCatalogWatchdog(for: fp, category: category)
            }
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
    nonisolated package func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        let camBox = ICCallbackTransfer(value: camera)
        Task { @MainActor in
            let cam = camBox.value
            if cam.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue),
               cam.mediaPresentation != .originalAssets {
                cam.mediaPresentation = .originalAssets
            }
        }
    }
    nonisolated package func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    @discardableResult
    private func removeContextCompletely(for device: ICDevice, fingerprint: String) -> ActiveCameraContext? {
        cameraToFingerprint.removeValue(forKey: ObjectIdentifier(device))
        let removed = contexts.removeValue(forKey: fingerprint)
        removed?.openTimeoutTask?.cancel()
        removed?.catalogTimeoutTask?.cancel()
        removed?.deltaTask?.cancel()
        return removed
    }

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

    func startOpenWatchdog(for fingerprint: String, category: DeviceCategory) {
        contexts[fingerprint]?.openTimeoutTask?.cancel()
        contexts[fingerprint]?.openTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(10000))
            guard !Task.isCancelled else { return }
            self?.handleSessionTimeout(for: fingerprint, category: category, isCatalogPhase: false)
        }
    }

    func startCatalogWatchdog(for fingerprint: String, category: DeviceCategory) {
        contexts[fingerprint]?.catalogTimeoutTask?.cancel()
        contexts[fingerprint]?.catalogTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(3500))
            guard !Task.isCancelled, let self else { return }
            if category == .androidPTP {
                self.handleSessionTimeout(for: fingerprint, category: category, isCatalogPhase: true)
            } else if let ctx = self.contexts[fingerprint], ctx.camera.hasOpenSession, !ctx.gate.isCatalogComplete {
                self.finalizeCatalogAndStartWatcher(for: fingerprint, camera: ctx.camera, bypassedCatalog: true)
            }
        }
    }

    func cancelWatchdogs(for fingerprint: String) {
        contexts[fingerprint]?.openTimeoutTask?.cancel()
        contexts[fingerprint]?.openTimeoutTask = nil
        contexts[fingerprint]?.catalogTimeoutTask?.cancel()
        contexts[fingerprint]?.catalogTimeoutTask = nil
    }

    private func handleSessionTimeout(for fingerprint: String, category: DeviceCategory, isCatalogPhase: Bool) {
        guard let ctx = contexts[fingerprint], !ctx.gate.isCatalogComplete else { return }
        if !isCatalogPhase && ctx.camera.hasOpenSession {
            return
        }
        contexts.removeValue(forKey: fingerprint)
        cameraToFingerprint.removeValue(forKey: ObjectIdentifier(ctx.camera))
        if ctx.camera.hasOpenSession {
            ctx.camera.requestCloseSession()
        }
        let nextStatus: DeviceConnectionStatus = category == .androidPTP
            ? .androidPermissionRequired
            : .error(message: isCatalogPhase
                ? "Tiempo de espera agotado al indexar catálogo de cámara."
                : "Tiempo de espera agotado al abrir sesión PTP.")
        onStatusChanged?(fingerprint, nextStatus, batteryValue(for: ctx.camera))
    }

    func batteryValue(for camera: ICCameraDevice) -> Int? {
        camera.batteryLevelAvailable ? Int(camera.batteryLevel) : nil
    }
}
