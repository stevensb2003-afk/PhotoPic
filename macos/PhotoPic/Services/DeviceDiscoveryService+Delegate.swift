import Foundation
@preconcurrency import ImageCaptureCore

extension DeviceDiscoveryService: ICDeviceBrowserDelegate {
    nonisolated package func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        Task { @MainActor [weak self] in
            self?.handleAddedCamera(camera)
        }
    }

    nonisolated package func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        Task { @MainActor [weak self] in
            self?.handleRemovedDevice(device)
        }
    }

    nonisolated package func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeName device: ICDevice) {
        Task { @MainActor [weak self] in
            guard let self,
                  let fp = self.deviceObjectToFingerprint[ObjectIdentifier(device)],
                  let idx = self.connectedDevices.firstIndex(where: { $0.fingerprint == fp }) else { return }
            let newName = device.name ?? self.connectedDevices[idx].deviceName
            self.connectedDevices[idx].deviceName = newName
            if !self.connectedDevices[idx].isKnownDevice {
                self.connectedDevices[idx].alias = newName
            }
        }
    }
}
