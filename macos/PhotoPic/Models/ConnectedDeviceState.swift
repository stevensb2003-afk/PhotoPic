import Foundation

/// Automatic visual & protocol classification for USB/PTP connected hardware.
package enum DeviceCategory: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case dslrMirrorless
    case androidPTP
    case iPhoneIOS
    case compactAction

    package var displayTitle: String {
        switch self {
        case .dslrMirrorless: return "Cámara DSLR / Mirrorless"
        case .androidPTP: return "Smartphone Android (PTP)"
        case .iPhoneIOS: return "iPhone / iPad (iOS)"
        case .compactAction: return "Cámara Compacta / Acción"
        }
    }

    package var sfSymbolName: String {
        switch self {
        case .dslrMirrorless: return "camera.fill"
        case .androidPTP: return "smartphone"
        case .iPhoneIOS: return "iphone"
        case .compactAction: return "camera.aperture"
        }
    }

    package var defaultAllowsJpgFallback: Bool {
        switch self {
        case .androidPTP, .iPhoneIOS: return true
        case .dslrMirrorless, .compactAction: return false
        }
    }
}

/// Real-time connection & PTP session state for a physical camera or phone.
package enum DeviceConnectionStatus: Sendable, Equatable, Hashable {
    case waiting
    case detectedNotConnected
    case connecting
    case connectedReady
    case capturing(activeDownloads: Int)
    case busyByMacOS
    case accessRestrictedLocked
    case androidPermissionRequired
    case disconnected(lastSeen: Date?)
    case error(message: String)

    package var label: String {
        switch self {
        case .waiting:
            return "Esperando cámara o celular USB..."
        case .detectedNotConnected:
            return "Detectado por USB (sin vincular)"
        case .connecting:
            return "Abriendo sesión PTP..."
        case .connectedReady:
            return "Conectado y listo"
        case .capturing(let activeDownloads):
            return activeDownloads > 1
                ? "Capturando (\(activeDownloads) archivos)"
                : "Capturando en vivo"
        case .busyByMacOS:
            return "Ocupado por macOS (Fotos / PTPCamera)"
        case .accessRestrictedLocked:
            return "Dispositivo bloqueado (desbloqueá y confiá en este Mac)"
        case .androidPermissionRequired:
            return "Falta permiso en Android (cambiá 'Solo carga' a PTP / Permitir acceso)"
        case .disconnected(let lastSeen):
            if let lastSeen {
                let formatted = Self.relativeFormatter.string(from: lastSeen)
                return "Desconectado — Última conexión: \(formatted)"
            }
            return "Desconectado"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    package var isLiveSessionOpen: Bool {
        switch self {
        case .connectedReady, .capturing:
            return true
        default:
            return false
        }
    }

    private static let relativeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Live UI-facing state snapshot for a USB device currently attached to the Mac.
package struct ConnectedDeviceState: Identifiable, Sendable, Equatable, Hashable {
    package let id: String
    package var deviceName: String
    package var alias: String
    package var category: DeviceCategory
    package var status: DeviceConnectionStatus
    package var batteryLevel: Int?
    package var isKnownDevice: Bool
    package var usbVendorID: Int
    package var usbProductID: Int
    package var serialNumber: String?
    package var transportType: String

    package init(
        fingerprint: String,
        deviceName: String,
        alias: String,
        category: DeviceCategory,
        status: DeviceConnectionStatus,
        batteryLevel: Int? = nil,
        isKnownDevice: Bool = false,
        usbVendorID: Int = 0,
        usbProductID: Int = 0,
        serialNumber: String? = nil,
        transportType: String = "USB"
    ) {
        self.id = fingerprint
        self.deviceName = deviceName
        self.alias = alias.isEmpty ? deviceName : alias
        self.category = category
        self.status = status
        self.batteryLevel = batteryLevel
        self.isKnownDevice = isKnownDevice
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.serialNumber = serialNumber
        self.transportType = transportType
    }

    package var fingerprint: String { id }
}
