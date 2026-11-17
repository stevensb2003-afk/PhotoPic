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

    /// Terminates macOS background `PTPCamera` / `ptpcamerad` daemon when Photos or Image Capture locks a USB camera.
    package func releaseMacOSPTPCameraLock(for fingerprint: String) {
        Task { @MainActor [weak self] in
            await Task.detached(priority: .userInitiated) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                task.arguments = ["-9", "PTPCamera", "ptpcamerad"]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
                task.waitUntilExit()
            }.value
            try? await Task.sleep(for: .milliseconds(350))
            self?.connectDevice(fingerprint: fingerprint)
        }
    }

    /// Temporarily releases `ImageCaptureCore` USB sessions when external `gphoto2` Live View runs.
    package func pauseSessionsForExternalBridge() {
        pausedFingerprints = connectedDevices
            .filter { $0.status.isLiveSessionOpen }
            .map(\.fingerprint)
        for fp in pausedFingerprints {
            disconnectDevice(fingerprint: fp)
        }
        setExternalBridgePaused(true)
    }

    package var unmountedPhysicalDevices: [PhysicalUSBDevice] {
        usbMonitor.physicalImagingDevices.filter { phys in
            !connectedDevices.contains { $0.usbVendorID == phys.vendorID }
        }
    }

    package var validationReport: ConnectionValidationReport {
        DeviceConnectionDiagnostics.evaluate(
            physical: usbMonitor.physicalImagingDevices,
            connected: connectedDevices,
            conflictingApps: usbMonitor.conflictingProcesses
        )
    }

    package func runConnectionProbeAndWakePrompts() async {
        await usbMonitor.refreshNow()
        let retryTargets = connectedDevices.filter {
            switch $0.status {
            case .accessRestrictedLocked, .androidPermissionRequired, .detectedNotConnected, .error:
                return true
            default:
                return false
            }
        }
        for device in retryTargets {
            connectDevice(fingerprint: device.fingerprint)
        }
        if retryTargets.isEmpty, let unmounted = unmountedPhysicalDevices.first {
            statusToastMessage = "\(unmounted.displayName) detectado por USB pero bloqueado por su modo USB actual. Cambiá a PTP / Confiar."
        }
    }

    package func resumeSessionsAfterExternalBridge() {
        setExternalBridgePaused(false)
        let toRestore = pausedFingerprints
        pausedFingerprints.removeAll()
        for fp in toRestore {
            connectDevice(fingerprint: fp)
        }
    }
}
