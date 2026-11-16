import Foundation
@preconcurrency import ImageCaptureCore

private struct ICCallbackTransfer<Value>: @unchecked Sendable {
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
            if let nsErr = error as NSError? {
                if nsErr.code == ICCReturnCodeValue.passcodeLocked
                    || nsErr.code == ICCReturnCodeValue.notAuthorized {
                    self.onStatusChanged?(fp, .accessRestrictedLocked, nil)
                } else if nsErr.code == ICCReturnCodeValue.failedToOpenSession
                    || nsErr.code == ICCReturnCodeValue.sessionAlreadyOpen
                    || nsErr.code == ICCReturnCodeValue.legacyAlreadyOpen {
                    self.onStatusChanged?(fp, .busyByMacOS, nil)
                } else {
                    self.onStatusChanged?(fp, .error(message: nsErr.localizedDescription), nil)
                }
                self.contexts[fp]?.deltaTask?.cancel()
                self.contexts.removeValue(forKey: fp)
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
            self.contexts.removeValue(forKey: fp)?.deltaTask?.cancel()
            self.onStatusChanged?(fp, .disconnected(lastSeen: Date()), nil)
        }
    }

    nonisolated package func didRemove(_ device: ICDevice) {
        Task { @MainActor [weak self] in
            guard let self, let fp = self.cameraToFingerprint.removeValue(forKey: ObjectIdentifier(device)) else { return }
            self.contexts.removeValue(forKey: fp)?.deltaTask?.cancel()
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
}
