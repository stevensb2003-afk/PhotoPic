import Foundation
import ImageCaptureCore

/// Derives deterministic hardware fingerprints and classifies USB/PTP device types.
package enum DeviceFingerprintMatcher {
    private static let appleVendorID = 0x05AC
    private static let dslrVendorIDs: Set<Int> = [
        0x04A9, // Canon
        0x04B0, // Nikon
        0x054C, // Sony
        0x04CB, // Fujifilm
        0x07B4, // Olympus / OM System
        0x04DA, // Panasonic Lumix
        0x0A17, // Pentax / Ricoh
        0x16B4, // Leica
        0x2201, // Hasselblad
        0x093B  // Sigma
    ]
    private static let androidVendorIDs: Set<Int> = [
        0x04E8, // Samsung
        0x18D1, // Google Pixel
        0x2717, // Xiaomi
        0x2A70, // OnePlus
        0x22D9, // OPPO / Realme
        0x1004, // LG
        0x22B8, // Motorola
        0x0FCE, // Sony Mobile
        0x12D1, // Huawei
        0x0B05, // ASUS
        0x2D95, // Vivo
        0x2BDE, // Nothing
        0x3426, // Honor
        0x19D2  // ZTE / Nubia
    ]
    private static let actionVendorIDs: Set<Int> = [
        0x2672, // GoPro
        0x2CA3, // DJI
        0x2E1A  // Insta360
    ]

    package static func fingerprint(for device: ICDevice) -> String {
        return fingerprint(
            serialNumber: device.serialNumberString,
            persistentID: device.persistentIDString,
            uuid: device.uuidString,
            vendorID: Int(device.usbVendorID),
            productID: Int(device.usbProductID),
            name: device.name
        )
    }

    package static func fingerprint(
        serialNumber: String?,
        persistentID: String?,
        uuid: String?,
        vendorID: Int,
        productID: Int,
        name: String?
    ) -> String {
        if let serial = serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !serial.isEmpty {
            return "sn:\(vendorID):\(productID):\(serial)"
        }
        if let persistent = persistentID?.trimmingCharacters(in: .whitespacesAndNewlines), !persistent.isEmpty {
            return "pid:\(persistent)"
        }
        if let uuid = uuid?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
            return "uuid:\(uuid)"
        }
        let cleanName = (name ?? "USBDevice")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "usb:\(vendorID):\(productID):\(cleanName)"
    }

    package static func classify(device: ICDevice) -> DeviceCategory {
        classify(
            name: device.name ?? "",
            productKind: device.productKind ?? "",
            vendorID: Int(device.usbVendorID)
        )
    }

    package static func classify(name: String, productKind: String, vendorID: Int) -> DeviceCategory {
        let combined = "\(name) \(productKind)".lowercased()

        if vendorID == appleVendorID || combined.contains("iphone") || combined.contains("ipad") {
            return .iPhoneIOS
        }

        if actionVendorIDs.contains(vendorID)
            || combined.contains("gopro")
            || combined.contains("osmo")
            || combined.contains("insta360")
            || combined.contains("hero") {
            return .compactAction
        }

        if dslrVendorIDs.contains(vendorID)
            || combined.contains("canon")
            || combined.contains("eos")
            || combined.contains("nikon")
            || combined.contains("alpha")
            || combined.contains("ilce-")
            || combined.contains("fujifilm")
            || combined.contains("lumix")
            || combined.contains("leica") {
            return .dslrMirrorless
        }

        if androidVendorIDs.contains(vendorID)
            || combined.contains("android")
            || combined.contains("galaxy")
            || combined.contains("pixel")
            || combined.contains("xiaomi")
            || combined.contains("oneplus")
            || combined.contains("ptp") {
            return .androidPTP
        }

        return .dslrMirrorless
    }

    /// Strict USB hardware filter for `IOKit` physical enumeration (excludes hubs, SSDs, mice, audio, keyboards).
    package static func detectImagingHardware(
        vendorID: Int,
        productName: String,
        vendorName: String
    ) -> DeviceCategory? {
        guard vendorID != 0 else { return nil }
        let combined = "\(vendorName) \(productName)".lowercased()

        let excludedKeywords = [
            "ssd", "t7", "t9", "flash", "hub", "controller", "dualsense",
            "headset", "audio", "mouse", "keyboard", "receiver", "lan", "ethernet"
        ]
        if excludedKeywords.contains(where: { combined.contains($0) }) {
            return nil
        }

        if vendorID == appleVendorID {
            let lowerProduct = productName.lowercased()
            return (lowerProduct.contains("iphone") || lowerProduct.contains("ipad")) ? .iPhoneIOS : nil
        }

        if actionVendorIDs.contains(vendorID) {
            return .compactAction
        }
        if dslrVendorIDs.contains(vendorID) {
            return .dslrMirrorless
        }
        if androidVendorIDs.contains(vendorID)
            || combined.contains("android")
            || combined.contains("pixel")
            || combined.contains("galaxy")
            || combined.contains("xiaomi") {
            return .androidPTP
        }
        return nil
    }
}
