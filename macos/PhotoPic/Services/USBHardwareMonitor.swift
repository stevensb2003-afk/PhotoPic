import Foundation
import IOKit
import Observation

/// Physical camera or smartphone detected at the macOS USB hardware layer (`IOKit`),
/// even when in Charging-only, MTP, Mass Storage, or locked mode before `ImageCaptureCore` sees it.
package struct PhysicalUSBDevice: Identifiable, Sendable, Equatable, Hashable {
    package let id: String
    package let vendorID: Int
    package let productID: Int
    package let vendorName: String
    package let productName: String
    package let serialNumber: String?
    package let category: DeviceCategory

    package init(
        id: String,
        vendorID: Int,
        productID: Int,
        vendorName: String,
        productName: String,
        serialNumber: String?,
        category: DeviceCategory
    ) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.vendorName = vendorName
        self.productName = productName
        self.serialNumber = serialNumber
        self.category = category
    }

    package var displayName: String {
        let trimmedProduct = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProduct.isEmpty { return trimmedProduct }
        let trimmedVendor = vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedVendor.isEmpty ? "Dispositivo USB (\(String(format: "0x%04X", vendorID)))" : trimmedVendor
    }
}

/// Polls physical USB imaging hardware via `IOKit` and flags competing host capture daemons.
@MainActor
@Observable
package final class USBHardwareMonitor {
    package private(set) var physicalImagingDevices: [PhysicalUSBDevice] = []
    package private(set) var conflictingProcesses: [String] = []
    package var onPhysicalDevicesUpdated: (([PhysicalUSBDevice]) -> Void)?

    private var pollTask: Task<Void, Never>?

    package init() {}

    package func startMonitoring() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: .milliseconds(1200))
            }
        }
    }

    package func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    package func refreshNow() async {
        let (devices, conflicts) = await Task.detached(priority: .utility) {
            (Self.scanIOKitImagingDevices(), Self.detectConflictingProcesses())
        }.value
        physicalImagingDevices = devices
        conflictingProcesses = conflicts
        onPhysicalDevicesUpdated?(devices)
    }

    nonisolated package static func scanIOKitImagingDevices() -> [PhysicalUSBDevice] {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var found: [PhysicalUSBDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = propsRef?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            let vendorID = dict["idVendor"] as? Int ?? 0
            let productID = dict["idProduct"] as? Int ?? 0
            let productName = (dict["USB Product Name"] as? String)
                ?? (dict["kUSBProductString"] as? String)
                ?? ""
            let vendorName = (dict["USB Vendor Name"] as? String)
                ?? (dict["kUSBVendorString"] as? String)
                ?? ""
            let serial = (dict["USB Serial Number"] as? String)
                ?? (dict["kUSBSerialNumberString"] as? String)

            guard let category = DeviceFingerprintMatcher.detectImagingHardware(
                vendorID: vendorID,
                productName: productName,
                vendorName: vendorName
            ) else {
                continue
            }

            let serialPart = (serial?.isEmpty == false ? serial! : "nosn")
            let id = String(format: "iokit:%04x:%04x:%@", vendorID, productID, serialPart)
            if !found.contains(where: { $0.id == id }) {
                found.append(PhysicalUSBDevice(
                    id: id,
                    vendorID: vendorID,
                    productID: productID,
                    vendorName: vendorName,
                    productName: productName,
                    serialNumber: serial,
                    category: category
                ))
            }
        }
        return found
    }

    nonisolated package static func detectConflictingProcesses() -> [String] {
        let targets = ["EOS Utility", "Android File Transfer Agent", "Capture One"]
        var active: [String] = []
        for appName in targets {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-x", appName]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    active.append(appName)
                }
            } catch {
                continue
            }
        }
        return active
    }
}
