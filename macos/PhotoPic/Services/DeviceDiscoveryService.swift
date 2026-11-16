import Foundation
@preconcurrency import ImageCaptureCore
import Observation
import os

/// Coordinates `ICDeviceBrowser` USB hot-plug detection, automatic pairing for
/// known devices (<1s), unknown-device banners, and macOS PTPCamera lock recovery.
@MainActor
@Observable
package final class DeviceDiscoveryService: NSObject {
    private let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "DeviceDiscovery")
    private let browser = ICDeviceBrowser()
    private let knownStore: KnownDevicesStore
    private let captureService: TetherCaptureService

    private var liveCameraByFingerprint: [String: ICCameraDevice] = [:]
    var deviceObjectToFingerprint: [ObjectIdentifier: String] = [:]

    package var connectedDevices: [ConnectedDeviceState] = []
    package private(set) var savedDevices: [KnownDevice] = []
    package var unknownDeviceBanner: ConnectedDeviceState?
    package var statusToastMessage: String?

    package var onCapturedFileReady: ((URL, String, KnownDevice) -> Void)?

    package init(
        knownStore: KnownDevicesStore,
        captureService: TetherCaptureService = TetherCaptureService()
    ) {
        self.knownStore = knownStore
        self.captureService = captureService
        self.savedDevices = knownStore.devices
        super.init()
        configureCaptureCallbacks()
    }

    package func startBrowsing() {
        guard !browser.isBrowsing else { return }
        browser.delegate = self
        let maskValue = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        if let mask = ICDeviceTypeMask(rawValue: maskValue) {
            browser.browsedDeviceTypeMask = mask
        }
        browser.start()
    }

    package func stopBrowsing() {
        browser.stop()
    }

    package var primaryLiveDevice: ConnectedDeviceState? {
        connectedDevices.first { $0.status.isLiveSessionOpen }
            ?? connectedDevices.first { $0.status == .connecting || $0.status == .busyByMacOS }
            ?? connectedDevices.first
    }

    package func connectAndSaveDevice(fingerprint: String, customAlias: String? = nil) {
        guard let liveIndex = connectedDevices.firstIndex(where: { $0.fingerprint == fingerprint }),
              let camera = liveCameraByFingerprint[fingerprint] else { return }

        let state = connectedDevices[liveIndex]
        let existing = knownStore.device(for: fingerprint)
        let profile = KnownDevice(
            id: fingerprint,
            displayName: state.deviceName,
            alias: customAlias ?? existing?.alias ?? state.deviceName,
            category: state.category,
            usbVendorID: state.usbVendorID,
            usbProductID: state.usbProductID,
            serialNumber: state.serialNumber,
            autoConnectOnPlug: existing?.autoConnectOnPlug ?? true,
            keepOriginalsOnDevice: existing?.keepOriginalsOnDevice ?? true,
            allowJpgWhenNoRaw: existing?.allowJpgWhenNoRaw ?? state.category.defaultAllowsJpgFallback,
            lastConnectedAt: Date()
        )
        knownStore.saveOrUpdate(profile)
        refreshSavedDevices()

        connectedDevices[liveIndex].isKnownDevice = true
        connectedDevices[liveIndex].alias = profile.alias
        if unknownDeviceBanner?.fingerprint == fingerprint {
            unknownDeviceBanner = nil
        }

        captureService.openSession(for: camera, profile: profile)
    }

    package func connectDevice(fingerprint: String) {
        guard let camera = liveCameraByFingerprint[fingerprint] else { return }
        let profile = knownStore.device(for: fingerprint) ?? buildTransientProfile(for: fingerprint)
        guard let profile else { return }
        if knownStore.device(for: fingerprint) != nil {
            knownStore.recordConnection(fingerprint: fingerprint)
            refreshSavedDevices()
        }
        captureService.openSession(for: camera, profile: profile)
    }

    package func disconnectDevice(fingerprint: String) {
        captureService.closeSession(for: fingerprint)
        if let idx = connectedDevices.firstIndex(where: { $0.fingerprint == fingerprint }) {
            connectedDevices[idx].status = .detectedNotConnected
        }
    }

    package func updateAlias(fingerprint: String, alias: String) {
        knownStore.updateAlias(fingerprint: fingerprint, alias: alias)
        refreshSavedDevices()
        if let idx = connectedDevices.firstIndex(where: { $0.fingerprint == fingerprint }),
           let updated = knownStore.device(for: fingerprint) {
            connectedDevices[idx].alias = updated.alias
            captureService.updateProfile(updated)
        }
    }

    package func setAutoConnect(fingerprint: String, enabled: Bool) {
        knownStore.setAutoConnect(fingerprint: fingerprint, enabled: enabled)
        refreshSavedDevices()
    }

    package func setKeepOriginals(fingerprint: String, enabled: Bool) {
        knownStore.setKeepOriginals(fingerprint: fingerprint, enabled: enabled)
        refreshSavedDevices()
        if let updated = knownStore.device(for: fingerprint) {
            captureService.updateProfile(updated)
        }
    }

    package func setAllowJpgWhenNoRaw(fingerprint: String, enabled: Bool) {
        knownStore.setAllowJpgWhenNoRaw(fingerprint: fingerprint, enabled: enabled)
        refreshSavedDevices()
        if let updated = knownStore.device(for: fingerprint) {
            captureService.updateProfile(updated)
        }
    }

    package func forgetDevice(fingerprint: String) {
        disconnectDevice(fingerprint: fingerprint)
        knownStore.forget(fingerprint: fingerprint)
        refreshSavedDevices()
        if let idx = connectedDevices.firstIndex(where: { $0.fingerprint == fingerprint }) {
            connectedDevices[idx].isKnownDevice = false
            connectedDevices[idx].alias = connectedDevices[idx].deviceName
        }
    }

    /// Terminates macOS background `PTPCamera` daemon when Photos or Image Capture locks a USB camera.
    package func releaseMacOSPTPCameraLock(for fingerprint: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["-9", "PTPCamera"]
        try? task.run()
        task.waitUntilExit()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.connectDevice(fingerprint: fingerprint)
        }
    }

    package func dismissToast() { statusToastMessage = nil }
    package func dismissUnknownBanner() { unknownDeviceBanner = nil }

    func handleAddedCamera(_ camera: ICCameraDevice) {
        let fp = DeviceFingerprintMatcher.fingerprint(for: camera)
        let category = DeviceFingerprintMatcher.classify(device: camera)
        let rawName = camera.name ?? "Cámara USB"
        let saved = knownStore.device(for: fp)

        liveCameraByFingerprint[fp] = camera
        deviceObjectToFingerprint[ObjectIdentifier(camera)] = fp

        let initialState = ConnectedDeviceState(
            fingerprint: fp,
            deviceName: rawName,
            alias: saved?.alias ?? rawName,
            category: saved?.category ?? category,
            status: camera.isAccessRestrictedAppleDevice ? .accessRestrictedLocked : .detectedNotConnected,
            batteryLevel: camera.batteryLevelAvailable ? Int(camera.batteryLevel) : nil,
            isKnownDevice: saved != nil,
            usbVendorID: Int(camera.usbVendorID),
            usbProductID: Int(camera.usbProductID),
            serialNumber: camera.serialNumberString,
            transportType: camera.transportType ?? "USB"
        )

        if let idx = connectedDevices.firstIndex(where: { $0.fingerprint == fp }) {
            connectedDevices[idx] = initialState
        } else {
            connectedDevices.append(initialState)
        }

        if let saved, saved.autoConnectOnPlug {
            knownStore.recordConnection(fingerprint: fp)
            refreshSavedDevices()
            captureService.openSession(for: camera, profile: saved)
            statusToastMessage = "Conectado automáticamente: \(saved.alias)"
        } else if saved == nil {
            unknownDeviceBanner = initialState
        }
    }

    func handleRemovedDevice(_ device: ICDevice) {
        let key = ObjectIdentifier(device)
        let fp = deviceObjectToFingerprint.removeValue(forKey: key)
            ?? DeviceFingerprintMatcher.fingerprint(for: device)
        captureService.closeSession(for: fp)
        liveCameraByFingerprint.removeValue(forKey: fp)
        connectedDevices.removeAll { $0.fingerprint == fp }
        if unknownDeviceBanner?.fingerprint == fp {
            unknownDeviceBanner = nil
        }
    }

    private func configureCaptureCallbacks() {
        captureService.onStatusChanged = { [weak self] fingerprint, status, battery in
            guard let self, let idx = self.connectedDevices.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
            self.connectedDevices[idx].status = status
            if let battery { self.connectedDevices[idx].batteryLevel = battery }
        }
        captureService.onFileStaged = { [weak self] stagedURL, filename, profile in
            self?.onCapturedFileReady?(stagedURL, filename, profile)
        }
        captureService.onCaptureError = { [weak self] fingerprint, message in
            self?.logger.error("Capture error for \(fingerprint, privacy: .public): \(message, privacy: .public)")
            self?.statusToastMessage = "Error de captura USB: \(message)"
        }
    }

    private func buildTransientProfile(for fingerprint: String) -> KnownDevice? {
        guard let state = connectedDevices.first(where: { $0.fingerprint == fingerprint }) else { return nil }
        return KnownDevice(
            id: state.fingerprint, displayName: state.deviceName, alias: state.alias,
            category: state.category, usbVendorID: state.usbVendorID,
            usbProductID: state.usbProductID, serialNumber: state.serialNumber
        )
    }

    private func refreshSavedDevices() {
        savedDevices = knownStore.devices
    }
}
