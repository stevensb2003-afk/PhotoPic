import Foundation
import Observation

/// Coordinates connected USB cameras/phones and saved device profiles inside Settings.
@MainActor
@Observable
package final class DeviceManagerViewModel {
    private let discoveryService: DeviceDiscoveryService
    package var aliasDrafts: [String: String] = [:]

    package init(discoveryService: DeviceDiscoveryService) {
        self.discoveryService = discoveryService
        syncAliasDrafts()
    }

    package var connectedDevices: [ConnectedDeviceState] {
        discoveryService.connectedDevices
    }

    package var savedDevices: [KnownDevice] {
        discoveryService.savedDevices
    }

    package func syncAliasDrafts() {
        for device in discoveryService.savedDevices where aliasDrafts[device.fingerprint] == nil {
            aliasDrafts[device.fingerprint] = device.alias
        }
    }

    package func aliasBinding(for device: KnownDevice) -> String {
        aliasDrafts[device.fingerprint] ?? device.alias
    }

    package func setAliasDraft(_ value: String, for fingerprint: String) {
        aliasDrafts[fingerprint] = value
    }

    package func commitAlias(for fingerprint: String) {
        guard let draft = aliasDrafts[fingerprint] else { return }
        discoveryService.updateAlias(fingerprint: fingerprint, alias: draft)
    }

    package func connectAndSave(fingerprint: String) {
        discoveryService.connectAndSaveDevice(fingerprint: fingerprint)
        syncAliasDrafts()
    }

    package func connect(fingerprint: String) {
        discoveryService.connectDevice(fingerprint: fingerprint)
    }

    package func disconnect(fingerprint: String) {
        discoveryService.disconnectDevice(fingerprint: fingerprint)
    }

    package func setAutoConnect(fingerprint: String, enabled: Bool) {
        discoveryService.setAutoConnect(fingerprint: fingerprint, enabled: enabled)
    }

    package func setKeepOriginals(fingerprint: String, enabled: Bool) {
        discoveryService.setKeepOriginals(fingerprint: fingerprint, enabled: enabled)
    }

    package func setAllowJpgWhenNoRaw(fingerprint: String, enabled: Bool) {
        discoveryService.setAllowJpgWhenNoRaw(fingerprint: fingerprint, enabled: enabled)
    }

    package func forget(fingerprint: String) {
        aliasDrafts.removeValue(forKey: fingerprint)
        discoveryService.forgetDevice(fingerprint: fingerprint)
    }

    package func releaseMacOSLock(for fingerprint: String) {
        discoveryService.releaseMacOSPTPCameraLock(for: fingerprint)
    }

    package func liveState(for savedDevice: KnownDevice) -> ConnectedDeviceState? {
        discoveryService.connectedDevices.first { $0.fingerprint == savedDevice.fingerprint }
    }

    package var validationReport: ConnectionValidationReport {
        discoveryService.validationReport
    }

    package func runDiagnosticProbe() async {
        await discoveryService.runConnectionProbeAndWakePrompts()
    }
}
