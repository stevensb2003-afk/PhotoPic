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
    package let directCanonService: DirectCanonUSBPTPService

    private var liveCameraByFingerprint: [String: ICCameraDevice] = [:]
    var deviceObjectToFingerprint: [ObjectIdentifier: String] = [:]

    package var connectedDevices: [ConnectedDeviceState] = []
    package private(set) var savedDevices: [KnownDevice] = []
    package let usbMonitor = USBHardwareMonitor()
    package var unknownDeviceBanner: ConnectedDeviceState?
    package var statusToastMessage: String?

    package var onCapturedFileReady: ((URL, String, KnownDevice) -> Void)?

    package init(
        knownStore: KnownDevicesStore,
        captureService: TetherCaptureService = TetherCaptureService(),
        directCanonService: DirectCanonUSBPTPService = DirectCanonUSBPTPService()
    ) {
        self.knownStore = knownStore
        self.captureService = captureService
        self.directCanonService = directCanonService
        self.savedDevices = knownStore.devices
        super.init()
        configureCaptureCallbacks()
    }

    package func startBrowsing() {
        usbMonitor.startMonitoring()
        guard !browser.isBrowsing else { return }
        browser.delegate = self
        let maskValue =
            ICDeviceTypeMask.camera.rawValue |
            ICDeviceLocationTypeMask.local.rawValue |
            ICDeviceLocationTypeMask.bonjour.rawValue
        if let mask = ICDeviceTypeMask(rawValue: maskValue) {
            browser.browsedDeviceTypeMask = mask
        }
        browser.start()
    }

    package func stopBrowsing() {
        usbMonitor.stopMonitoring()
        browser.stop()
    }

    package var primaryLiveDevice: ConnectedDeviceState? {
        connectedDevices.first { $0.status.isLiveSessionOpen }
            ?? connectedDevices.first {
                $0.status.isConnectingOrIndexing
                    || $0.status == .busyByMacOS
                    || $0.status == .androidPermissionRequired
                    || $0.status == .accessRestrictedLocked
            }
            ?? connectedDevices.first
    }

    package var activePrimaryICCamera: ICCameraDevice? {
        if let fp = primaryLiveDevice?.fingerprint, let cam = captureService.activeCamera(for: fp) {
            return cam
        }
        for dev in connectedDevices {
            if let cam = captureService.activeCamera(for: dev.fingerprint) {
                return cam
            }
        }
        return nil
    }

    package func connectAndSaveDevice(fingerprint: String, customAlias: String? = nil) {
        guard let liveIndex = connectedDevices.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }

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

        if state.usbVendorID == CanonPTPCode.canonVendorID {
            directCanonService.openSession(profile: profile)
        } else if let camera = liveCameraByFingerprint[fingerprint] {
            captureService.openSession(for: camera, profile: profile)
        }
    }

    package func connectDevice(fingerprint: String) {
        let state = connectedDevices.first(where: { $0.fingerprint == fingerprint })
        let profile = knownStore.device(for: fingerprint) ?? buildTransientProfile(for: fingerprint)
        guard let profile else { return }
        if knownStore.device(for: fingerprint) != nil {
            knownStore.recordConnection(fingerprint: fingerprint)
            refreshSavedDevices()
        }
        if (state?.usbVendorID ?? profile.usbVendorID) == CanonPTPCode.canonVendorID {
            directCanonService.openSession(profile: profile)
        } else if let camera = liveCameraByFingerprint[fingerprint] {
            captureService.openSession(for: camera, profile: profile)
        }
    }

    package func disconnectDevice(fingerprint: String) {
        if directCanonService.hasSession(for: fingerprint) {
            directCanonService.closeSession(for: fingerprint)
        }
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
            directCanonService.updateProfile(updated)
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
            directCanonService.updateProfile(updated)
        }
    }

    package func setAllowJpgWhenNoRaw(fingerprint: String, enabled: Bool) {
        knownStore.setAllowJpgWhenNoRaw(fingerprint: fingerprint, enabled: enabled)
        refreshSavedDevices()
        if let updated = knownStore.device(for: fingerprint) {
            captureService.updateProfile(updated)
            directCanonService.updateProfile(updated)
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

    package private(set) var isPausedForExternalBridge = false
    var pausedFingerprints: [String] = []

    package var canTriggerPrimaryShutter: Bool {
        guard let fp = primaryLiveDevice?.fingerprint else { return false }
        if directCanonService.hasSession(for: fp) {
            return true
        }
        return captureService.canTriggerRemoteShutter(for: fp)
    }

    @discardableResult
    package func triggerPrimaryRemoteShutter() -> Bool {
        guard let fp = primaryLiveDevice?.fingerprint else { return false }
        if directCanonService.hasSession(for: fp) {
            Task { @MainActor in
                _ = await self.directCanonService.triggerRemoteShutter(for: fp)
            }
            return true
        }
        return captureService.triggerRemoteShutter(for: fp)
    }

    package func setExternalBridgePaused(_ paused: Bool) {
        isPausedForExternalBridge = paused
    }

    package func dismissToast() { statusToastMessage = nil }
    package func dismissUnknownBanner() { unknownDeviceBanner = nil }

    func handleAddedCamera(_ camera: ICCameraDevice) {
        let vendorID = Int(camera.usbVendorID)
        let productID = Int(camera.usbProductID)
        let fp = DeviceFingerprintMatcher.fingerprint(for: camera)
        let category = DeviceFingerprintMatcher.classify(device: camera)
        let rawName = camera.name ?? "Cámara USB"
        let saved = knownStore.device(for: fp)
            ?? (vendorID == CanonPTPCode.canonVendorID
                ? knownStore.devices.first(where: { $0.usbVendorID == vendorID && $0.usbProductID == productID })
                : nil)
        let resolvedFP = saved?.fingerprint ?? fp

        liveCameraByFingerprint[resolvedFP] = camera
        deviceObjectToFingerprint[ObjectIdentifier(camera)] = resolvedFP

        // Route Canon EOS through DirectCanonUSBPTPService so macOS ptpcamerad never scans 4,000+ SD photos.
        if vendorID == CanonPTPCode.canonVendorID {
            let resolvedState = ConnectedDeviceState(
                fingerprint: resolvedFP,
                deviceName: rawName,
                alias: saved?.alias ?? rawName,
                category: saved?.category ?? .dslrMirrorless,
                status: connectedDevices.first(where: { $0.fingerprint == resolvedFP })?.status ?? .detectedNotConnected,
                batteryLevel: camera.batteryLevelAvailable ? Int(camera.batteryLevel) : nil,
                isKnownDevice: saved != nil,
                usbVendorID: vendorID,
                usbProductID: productID,
                serialNumber: camera.serialNumberString,
                transportType: "USB PTP Directo"
            )
            if let idx = connectedDevices.firstIndex(where: { $0.fingerprint == resolvedFP }) {
                connectedDevices[idx].deviceName = rawName
                if let battery = resolvedState.batteryLevel {
                    connectedDevices[idx].batteryLevel = battery
                }
            } else {
                connectedDevices.append(resolvedState)
            }
            if let saved, saved.autoConnectOnPlug, !directCanonService.hasSession(for: resolvedFP) {
                knownStore.recordConnection(fingerprint: resolvedFP)
                refreshSavedDevices()
                directCanonService.openSession(profile: saved)
            } else if saved == nil && unknownDeviceBanner == nil {
                unknownDeviceBanner = resolvedState
            }
            return
        }

        let resolvedCategory = saved?.category ?? category
        let initialStatus: DeviceConnectionStatus
        if camera.isAccessRestrictedAppleDevice {
            initialStatus = .accessRestrictedLocked
        } else if resolvedCategory == .androidPTP {
            initialStatus = .androidPermissionRequired
        } else {
            initialStatus = .detectedNotConnected
        }

        let initialState = ConnectedDeviceState(
            fingerprint: resolvedFP,
            deviceName: rawName,
            alias: saved?.alias ?? rawName,
            category: resolvedCategory,
            status: initialStatus,
            batteryLevel: camera.batteryLevelAvailable ? Int(camera.batteryLevel) : nil,
            isKnownDevice: saved != nil,
            usbVendorID: vendorID,
            usbProductID: productID,
            serialNumber: camera.serialNumberString,
            transportType: camera.transportType ?? "USB"
        )

        if let idx = connectedDevices.firstIndex(where: { $0.fingerprint == resolvedFP }) {
            connectedDevices[idx] = initialState
        } else {
            connectedDevices.append(initialState)
        }

        if let saved, saved.autoConnectOnPlug {
            knownStore.recordConnection(fingerprint: resolvedFP)
            refreshSavedDevices()
            captureService.openSession(for: camera, profile: saved)
        } else if saved == nil {
            unknownDeviceBanner = initialState
        }
    }

    func handleRemovedDevice(_ device: ICDevice) {
        let key = ObjectIdentifier(device)
        let fp = deviceObjectToFingerprint.removeValue(forKey: key)
            ?? DeviceFingerprintMatcher.fingerprint(for: device)
        // Seizing IOUSBHostInterface causes ICDeviceBrowser to fire didRemove; ignore if Canon is still physically plugged in.
        if directCanonService.hasSession(for: fp) ||
            connectedDevices.first(where: { $0.fingerprint == fp })?.usbVendorID == CanonPTPCode.canonVendorID {
            liveCameraByFingerprint.removeValue(forKey: fp)
            return
        }
        captureService.closeSession(for: fp)
        liveCameraByFingerprint.removeValue(forKey: fp)
        connectedDevices.removeAll { $0.fingerprint == fp }
        if unknownDeviceBanner?.fingerprint == fp {
            unknownDeviceBanner = nil
        }
    }

    private func reconcilePhysicalCanonUSBDevices(_ physical: [PhysicalUSBDevice]) {
        let physicalCanons = physical.filter { $0.vendorID == CanonPTPCode.canonVendorID }

        for phys in physicalCanons {
            let matchedSaved = knownStore.devices.first {
                $0.usbVendorID == phys.vendorID && $0.usbProductID == phys.productID
            }
            let existingIdx = connectedDevices.firstIndex {
                $0.usbVendorID == phys.vendorID && $0.usbProductID == phys.productID
            }
            let fp = existingIdx.map { connectedDevices[$0].fingerprint } ?? matchedSaved?.fingerprint ?? phys.id

            if existingIdx == nil {
                let state = ConnectedDeviceState(
                    fingerprint: fp,
                    deviceName: phys.displayName,
                    alias: matchedSaved?.alias ?? phys.displayName,
                    category: matchedSaved?.category ?? .dslrMirrorless,
                    status: .detectedNotConnected,
                    batteryLevel: nil,
                    isKnownDevice: matchedSaved != nil,
                    usbVendorID: phys.vendorID,
                    usbProductID: phys.productID,
                    serialNumber: phys.serialNumber,
                    transportType: "USB PTP Directo"
                )
                connectedDevices.append(state)
                if let matchedSaved, matchedSaved.autoConnectOnPlug {
                    knownStore.recordConnection(fingerprint: fp)
                    refreshSavedDevices()
                    directCanonService.openSession(profile: matchedSaved)
                } else if matchedSaved == nil {
                    unknownDeviceBanner = state
                }
            } else if let matchedSaved, matchedSaved.autoConnectOnPlug,
                      connectedDevices[existingIdx!].status == .detectedNotConnected,
                      !directCanonService.hasSession(for: fp) {
                directCanonService.openSession(profile: matchedSaved)
            }
        }

        // Clean up Canon entries when physically unplugged or turned off
        let disconnectedCanonFPs = connectedDevices
            .filter { dev in
                dev.usbVendorID == CanonPTPCode.canonVendorID &&
                !physicalCanons.contains(where: { $0.vendorID == dev.usbVendorID && $0.productID == dev.usbProductID })
            }
            .map(\.fingerprint)
        for fp in disconnectedCanonFPs {
            directCanonService.closeSession(for: fp, emitStatus: false)
            liveCameraByFingerprint.removeValue(forKey: fp)
            connectedDevices.removeAll { $0.fingerprint == fp }
            if unknownDeviceBanner?.fingerprint == fp {
                unknownDeviceBanner = nil
            }
        }
    }

    private func configureCaptureCallbacks() {
        let onStatus: @MainActor (String, DeviceConnectionStatus, Int?) -> Void = { [weak self] fingerprint, status, battery in
            guard let self, let idx = self.connectedDevices.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
            let previousStatus = self.connectedDevices[idx].status
            self.connectedDevices[idx].status = status
            if let battery { self.connectedDevices[idx].batteryLevel = battery }
            if self.unknownDeviceBanner?.fingerprint == fingerprint {
                self.unknownDeviceBanner = self.connectedDevices[idx]
            }
            if status == .connectedReady && previousStatus != .connectedReady && !previousStatus.isLiveSessionOpen {
                let alias = self.connectedDevices[idx].alias
                self.statusToastMessage = "Conectado y listo: \(alias) — tethering activo en tiempo real"
            } else if status == .androidPermissionRequired && previousStatus.isConnectingOrIndexing {
                self.statusToastMessage = "Android sin permiso PTP: cambiá 'Solo carga' a 'Transferir imágenes (PTP)' y tocá Permitir."
            } else if status == .accessRestrictedLocked && previousStatus != .accessRestrictedLocked {
                self.statusToastMessage = "Dispositivo bloqueado: desbloqueá tu iPhone y tocá 'Confiar' para conectar."
            } else if case .error(let msg) = status {
                let alias = self.connectedDevices[idx].alias
                self.statusToastMessage = "Alerta USB (\(alias)): \(msg)"
            }
        }
        let onStaged: @MainActor (URL, String, KnownDevice) -> Void = { [weak self] stagedURL, filename, profile in
            self?.onCapturedFileReady?(stagedURL, filename, profile)
        }
        let onError: @MainActor (String, String) -> Void = { [weak self] fingerprint, message in
            self?.logger.error("Capture error for \(fingerprint, privacy: .public): \(message, privacy: .public)")
            self?.statusToastMessage = "Error de captura USB: \(message)"
        }

        captureService.onStatusChanged = onStatus
        captureService.onFileStaged = onStaged
        captureService.onCaptureError = onError

        directCanonService.onStatusChanged = onStatus
        directCanonService.onFileStaged = onStaged
        directCanonService.onCaptureError = onError

        usbMonitor.onPhysicalDevicesUpdated = { [weak self] physical in
            self?.reconcilePhysicalCanonUSBDevices(physical)
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
