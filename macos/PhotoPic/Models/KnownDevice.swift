import Foundation

/// Persistent profile stored in JSON for each remembered camera or smartphone.
package struct KnownDevice: Identifiable, Sendable, Equatable, Hashable, Codable {
    package let id: String
    package var displayName: String
    package var alias: String
    package var category: DeviceCategory
    package var usbVendorID: Int
    package var usbProductID: Int
    package var serialNumber: String?
    package var autoConnectOnPlug: Bool
    package var keepOriginalsOnDevice: Bool
    package var allowJpgWhenNoRaw: Bool
    package var lastConnectedAt: Date

    package init(
        id: String,
        displayName: String,
        alias: String,
        category: DeviceCategory,
        usbVendorID: Int = 0,
        usbProductID: Int = 0,
        serialNumber: String? = nil,
        autoConnectOnPlug: Bool = true,
        keepOriginalsOnDevice: Bool = true,
        allowJpgWhenNoRaw: Bool? = nil,
        lastConnectedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.alias = alias.isEmpty ? displayName : alias
        self.category = category
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.serialNumber = serialNumber
        self.autoConnectOnPlug = autoConnectOnPlug
        self.keepOriginalsOnDevice = keepOriginalsOnDevice
        self.allowJpgWhenNoRaw = allowJpgWhenNoRaw ?? category.defaultAllowsJpgFallback
        self.lastConnectedAt = lastConnectedAt
    }

    package var fingerprint: String { id }
}
