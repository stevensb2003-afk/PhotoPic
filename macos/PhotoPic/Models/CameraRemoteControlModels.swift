import Foundation

package enum CameraPropertyDataType: String, Sendable, Hashable, CaseIterable {
    case uint8
    case uint16
    case uint32
    case string
}

package enum CameraPropertyID: UInt32, Sendable, Hashable, CaseIterable, Identifiable {
    case aperture = 0xD101
    case shutterSpeed = 0xD102
    case iso = 0xD103
    case exposureCompensation = 0xD104
    case aeMode = 0xD105
    case driveMode = 0xD106
    case meteringMode = 0xD107
    case focusMode = 0xD108
    case whiteBalance = 0xD109
    case colorTemperature = 0xD10A
    case pictureStyle = 0xD110
    case batteryPower = 0xD111
    case availableShots = 0xD11B
    case captureDestination = 0xD11C
    case silentShutter = 0xD129
    case stroboDispState = 0xD1C7
    case lensName = 0xD1D8
    case stroboFiring = 0xD1DC

    package var id: UInt32 { rawValue }

    package var dataType: CameraPropertyDataType {
        switch self {
        case .exposureCompensation, .meteringMode, .whiteBalance, .pictureStyle:
            return .uint8
        case .aperture, .shutterSpeed, .iso, .aeMode, .driveMode, .batteryPower:
            return .uint16
        case .focusMode, .colorTemperature, .availableShots, .captureDestination,
             .silentShutter, .stroboDispState, .stroboFiring:
            return .uint32
        case .lensName:
            return .string
        }
    }

    package var displayName: String {
        switch self {
        case .aperture: return "Apertura (f/)"
        case .shutterSpeed: return "Velocidad de Obturación"
        case .iso: return "Sensibilidad ISO"
        case .exposureCompensation: return "Compensación EV"
        case .aeMode: return "Modo de Exposición (Dial)"
        case .driveMode: return "Modo de Disparo"
        case .meteringMode: return "Medición de Luz"
        case .focusMode: return "Modo de Enfoque"
        case .whiteBalance: return "Balance de Blancos"
        case .colorTemperature: return "Temperatura Kelvin"
        case .pictureStyle: return "Estilo de Imagen"
        case .batteryPower: return "Batería"
        case .availableShots: return "Disparos Disponibles"
        case .captureDestination: return "Destino de Captura"
        case .silentShutter: return "Disparo Silencioso LV"
        case .stroboDispState: return "Estado Flash / Zapata"
        case .lensName: return "Lente Montado"
        case .stroboFiring: return "Disparo de Flash"
        }
    }

    package var shortLabel: String {
        switch self {
        case .aperture: return "Apertura"
        case .shutterSpeed: return "Velocidad"
        case .iso: return "ISO"
        case .exposureCompensation: return "Comp. EV"
        case .aeMode: return "Dial"
        case .driveMode: return "Disparo"
        case .meteringMode: return "Medición"
        case .focusMode: return "Enfoque"
        case .whiteBalance: return "WB"
        case .colorTemperature: return "Kelvin"
        case .pictureStyle: return "Estilo"
        case .batteryPower: return "Batería"
        case .availableShots: return "Restantes"
        case .captureDestination: return "Destino"
        case .silentShutter: return "Silenc. LV"
        case .stroboDispState: return "Zapata"
        case .lensName: return "Lente"
        case .stroboFiring: return "Flash"
        }
    }

    package var symbolName: String {
        switch self {
        case .aperture: return "camera.aperture"
        case .shutterSpeed: return "timer"
        case .iso: return "dial.medium"
        case .exposureCompensation: return "plusminus"
        case .aeMode: return "dial.low"
        case .driveMode: return "square.stack"
        case .meteringMode: return "viewfinder.circle"
        case .focusMode: return "scope"
        case .whiteBalance: return "sun.max"
        case .colorTemperature: return "thermometer.medium"
        case .pictureStyle: return "swatchpalette"
        case .batteryPower: return "battery.75percent"
        case .availableShots: return "photo.stack"
        case .captureDestination: return "internaldrive"
        case .silentShutter: return "speaker.slash"
        case .stroboDispState, .stroboFiring: return "bolt.circle"
        case .lensName: return "camera.metering.center.weighted"
        }
    }

    package var isPrimaryExposure: Bool {
        switch self {
        case .aperture, .shutterSpeed, .iso, .exposureCompensation:
            return true
        default:
            return false
        }
    }

    package static var primaryExposureOrder: [CameraPropertyID] {
        [.shutterSpeed, .aperture, .iso, .exposureCompensation]
    }

    package static var creativeControlOrder: [CameraPropertyID] {
        [.whiteBalance, .colorTemperature, .meteringMode, .focusMode, .driveMode, .pictureStyle]
    }
}

package struct CameraPropertyOption: Identifiable, Sendable, Hashable {
    package let rawValue: UInt32
    package let label: String

    package var id: UInt32 { rawValue }

    package init(rawValue: UInt32, label: String) {
        self.rawValue = rawValue
        self.label = label
    }
}

package struct CameraPropertyControl: Identifiable, Sendable, Hashable {
    package let property: CameraPropertyID
    package var currentValue: UInt32
    package var currentLabel: String
    package var availableOptions: [CameraPropertyOption]
    package var isWritable: Bool
    package var lockExplanation: String?

    package var id: UInt32 { property.rawValue }

    package init(
        property: CameraPropertyID,
        currentValue: UInt32,
        currentLabel: String? = nil,
        availableOptions: [CameraPropertyOption] = [],
        isWritable: Bool = false,
        lockExplanation: String? = nil
    ) {
        self.property = property
        self.currentValue = currentValue
        self.currentLabel = currentLabel ?? CanonEOSLookupTables.label(for: property, rawValue: currentValue)
        self.availableOptions = availableOptions
        self.isWritable = isWritable
        self.lockExplanation = lockExplanation
    }

    package func adjacentOption(step delta: Int) -> CameraPropertyOption? {
        guard !availableOptions.isEmpty else { return nil }
        guard let currentIndex = availableOptions.firstIndex(where: { $0.rawValue == currentValue }) else {
            return delta >= 0 ? availableOptions.first : availableOptions.last
        }
        let targetIndex = currentIndex + delta
        guard availableOptions.indices.contains(targetIndex) else { return nil }
        return availableOptions[targetIndex]
    }

    package var canStepBackward: Bool {
        guard isWritable, let idx = availableOptions.firstIndex(where: { $0.rawValue == currentValue }) else {
            return false
        }
        return idx > 0
    }

    package var canStepForward: Bool {
        guard isWritable, let idx = availableOptions.firstIndex(where: { $0.rawValue == currentValue }) else {
            return false
        }
        return idx + 1 < availableOptions.count
    }
}

package enum FlashAccessorySelection: String, Sendable, Hashable, CaseIterable, Identifiable {
    case externalHotShoe
    case disabled
    case builtinPopup

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .externalHotShoe:
            return "Flash Externo (Zapata)"
        case .disabled:
            return "Sin Flash"
        case .builtinPopup:
            return "Flash Interno"
        }
    }

    package var badgeLabel: String {
        switch self {
        case .externalHotShoe:
            return "Zapata Segura"
        case .disabled:
            return "Apagado"
        case .builtinPopup:
            return "Pop-up"
        }
    }

    package var statusSummary: String {
        switch self {
        case .externalHotShoe:
            return "Nunca levanta el flash interno de la cámara. Protege el motorcito y dispara por la zapata superior."
        case .disabled:
            return "Desactiva el disparo de flash en la cámara (0xD1DC = 1) y no mueve el mecanismo interno."
        case .builtinPopup:
            return "Solo usalo si no tenés absolutamente nada montado en la zapata superior."
        }
    }
}

package enum CanonEOSLookupTables {
    private static let apertureMap: [UInt32: String] = [
        0x0000: "Auto", 0x00B0: "Auto", 0xFFFF: "Auto",
        0x08: "f/1.0", 0x0B: "f/1.1", 0x0C: "f/1.2", 0x0D: "f/1.2",
        0x10: "f/1.4", 0x13: "f/1.6", 0x14: "f/1.8", 0x15: "f/1.8",
        0x18: "f/2.0", 0x1B: "f/2.2", 0x1C: "f/2.5", 0x1D: "f/2.5",
        0x20: "f/2.8", 0x23: "f/3.2", 0x24: "f/3.5", 0x25: "f/3.5",
        0x28: "f/4.0", 0x2B: "f/4.5", 0x2C: "f/4.5", 0x2D: "f/5.0",
        0x30: "f/5.6", 0x33: "f/6.3", 0x34: "f/6.7", 0x35: "f/7.1",
        0x38: "f/8.0", 0x3B: "f/9.0", 0x3C: "f/9.5", 0x3D: "f/10",
        0x40: "f/11", 0x43: "f/13", 0x44: "f/13", 0x45: "f/14",
        0x48: "f/16", 0x4B: "f/18", 0x4C: "f/19", 0x4D: "f/20",
        0x50: "f/22", 0x53: "f/25", 0x54: "f/27", 0x55: "f/29",
        0x58: "f/32", 0x5B: "f/36", 0x5C: "f/38", 0x5D: "f/40",
        0x60: "f/45", 0x63: "f/51", 0x64: "f/54", 0x65: "f/57",
        0x68: "f/64", 0x6B: "f/72", 0x6C: "f/76", 0x6D: "f/81",
        0x70: "f/91"
    ]

    private static let shutterSpeedMap: [UInt32: String] = [
        0x0000: "Auto", 0x0004: "Bulb", 0x000C: "Bulb",
        0x10: "30\"", 0x13: "25\"", 0x14: "20\"", 0x15: "20\"",
        0x18: "15\"", 0x1B: "13\"", 0x1C: "10\"", 0x1D: "10\"",
        0x20: "8\"", 0x23: "6.3\"", 0x24: "6\"", 0x25: "5\"",
        0x28: "4\"", 0x2B: "3.2\"", 0x2C: "3\"", 0x2D: "2.5\"",
        0x30: "2\"", 0x33: "1.6\"", 0x34: "1.5\"", 0x35: "1.3\"",
        0x38: "1\"", 0x3B: "0.8\"", 0x3C: "0.7\"", 0x3D: "0.6\"",
        0x40: "0.5\"", 0x43: "0.4\"", 0x44: "0.3\"", 0x45: "0.3\"",
        0x48: "1/4", 0x4B: "1/5", 0x4C: "1/6", 0x4D: "1/6",
        0x50: "1/8", 0x53: "1/10", 0x54: "1/10", 0x55: "1/13",
        0x58: "1/15", 0x5B: "1/20", 0x5C: "1/20", 0x5D: "1/25",
        0x60: "1/30", 0x63: "1/40", 0x64: "1/45", 0x65: "1/50",
        0x68: "1/60", 0x6B: "1/80", 0x6C: "1/90", 0x6D: "1/100",
        0x70: "1/125", 0x73: "1/160", 0x74: "1/180", 0x75: "1/200",
        0x78: "1/250", 0x7B: "1/320", 0x7C: "1/350", 0x7D: "1/400",
        0x80: "1/500", 0x83: "1/640", 0x84: "1/750", 0x85: "1/800",
        0x88: "1/1000", 0x8B: "1/1250", 0x8C: "1/1500", 0x8D: "1/1600",
        0x90: "1/2000", 0x93: "1/2500", 0x94: "1/3000", 0x95: "1/3200",
        0x98: "1/4000", 0x9B: "1/5000", 0x9C: "1/6000", 0x9D: "1/6400",
        0xA0: "1/8000", 0xA8: "1/16000"
    ]

    private static let isoMap: [UInt32: String] = [
        0x0000: "Auto", 0x0001: "Auto",
        0x0040: "50", 0x0043: "64", 0x0045: "80",
        0x0048: "100", 0x004B: "125", 0x004D: "160",
        0x0050: "200", 0x0053: "250", 0x0055: "320",
        0x0058: "400", 0x005B: "500", 0x005D: "640",
        0x0060: "800", 0x0063: "1000", 0x0065: "1250",
        0x0068: "1600", 0x006B: "2000", 0x006D: "2500",
        0x0070: "3200", 0x0073: "4000", 0x0075: "5000",
        0x0078: "6400", 0x007B: "8000", 0x007D: "10000",
        0x0080: "12800", 0x0083: "16000", 0x0085: "20000",
        0x0088: "25600", 0x008B: "32000", 0x008D: "40000",
        0x0090: "51200", 0x0093: "64000", 0x0098: "102400"
    ]

    private static let expCompensationMap: [UInt32: String] = [
        0x28: "+5.0", 0x23: "+4.3", 0x20: "+4.0", 0x18: "+3.0",
        0x15: "+2.6", 0x14: "+2.5", 0x13: "+2.3", 0x10: "+2.0",
        0x0D: "+1.6", 0x0C: "+1.5", 0x0B: "+1.3", 0x08: "+1.0",
        0x05: "+0.6", 0x04: "+0.5", 0x03: "+0.3", 0x00: "0 EV",
        0xFD: "-0.3", 0xFC: "-0.5", 0xFB: "-0.6", 0xF8: "-1.0",
        0xF5: "-1.3", 0xF4: "-1.5", 0xF3: "-1.6", 0xF0: "-2.0",
        0xED: "-2.3", 0xEC: "-2.5", 0xEB: "-2.6", 0xE8: "-3.0",
        0xE0: "-4.0", 0xD8: "-5.0"
    ]

    private static let aeModeMap: [UInt32: String] = [
        0x00: "P (Programa)", 0x01: "Tv (Prioridad Velocidad)", 0x02: "Av (Prioridad Apertura)",
        0x03: "M (Manual)", 0x04: "Bulb", 0x07: "Custom (C)",
        0x09: "Auto+ (Escena)", 0x0F: "Sin Flash", 0x13: "CA (Auto Creativo)",
        0x14: "Video", 0x19: "SCN", 0x37: "Fv"
    ]

    private static let driveModeMap: [UInt32: String] = [
        0x00: "Único", 0x01: "Ráfaga", 0x04: "Ráfaga Alta",
        0x05: "Ráfaga Baja", 0x06: "Silencioso", 0x10: "Temporizador 10s",
        0x11: "Temporizador 2s", 0x13: "Silencioso Único", 0x14: "Silencioso Continuo"
    ]

    private static let meteringModeMap: [UInt32: String] = [
        0: "Ponderada al centro", 1: "Puntual", 2: "Promedio",
        3: "Evaluativa", 4: "Parcial", 5: "Promedio ponderado"
    ]

    private static let focusModeMap: [UInt32: String] = [
        0: "One Shot AF", 1: "AI Servo", 2: "AI Focus", 3: "Manual (MF)"
    ]

    private static let whiteBalanceMap: [UInt32: String] = [
        0: "Auto", 1: "Luz de día", 2: "Nublado", 3: "Tungsteno",
        4: "Fluorescente", 5: "Flash", 6: "Personalizado",
        8: "Sombra", 9: "Kelvin (K)", 23: "AWB Blanco"
    ]

    private static let pictureStyleMap: [UInt32: String] = [
        0x81: "Estándar", 0x82: "Retrato", 0x83: "Paisaje", 0x84: "Neutro",
        0x85: "Fiel", 0x86: "Monocromo", 0x87: "Auto", 0x88: "Detalle fino",
        0x21: "Usuario 1", 0x22: "Usuario 2", 0x23: "Usuario 3"
    ]

    package static func label(for property: CameraPropertyID, rawValue: UInt32) -> String {
        switch property {
        case .aperture:
            return apertureMap[rawValue] ?? String(format: "0x%02X", rawValue)
        case .shutterSpeed:
            return shutterSpeedMap[rawValue] ?? String(format: "0x%02X", rawValue)
        case .iso:
            return isoMap[rawValue] ?? String(format: "0x%04X", rawValue)
        case .exposureCompensation:
            return expCompensationMap[rawValue & 0xFF] ?? String(format: "0x%02X", rawValue & 0xFF)
        case .aeMode:
            return aeModeMap[rawValue] ?? String(format: "Modo 0x%02X", rawValue)
        case .driveMode:
            return driveModeMap[rawValue] ?? String(format: "Modo 0x%02X", rawValue)
        case .meteringMode:
            return meteringModeMap[rawValue] ?? String(format: "Med. %u", rawValue)
        case .focusMode:
            return focusModeMap[rawValue] ?? String(format: "AF %u", rawValue)
        case .whiteBalance:
            return whiteBalanceMap[rawValue] ?? String(format: "WB %u", rawValue)
        case .colorTemperature:
            return "\(rawValue) K"
        case .pictureStyle:
            return pictureStyleMap[rawValue] ?? String(format: "Estilo 0x%02X", rawValue)
        case .batteryPower:
            switch rawValue {
            case 4: return "100% (Llena)"
            case 3: return "75%"
            case 2: return "50%"
            case 1: return "25% (Baja)"
            case 0: return "Crítica (≤10%)"
            default:
                if rawValue <= 100 { return "\(rawValue)%" }
                return "CA / Externa"
            }
        case .availableShots:
            return "\(rawValue)"
        case .captureDestination:
            return (rawValue & 0x04) != 0 ? "Directo al Mac" : "Tarjeta SD"
        case .silentShutter:
            switch rawValue {
            case 0: return "Desactivado (Sync Zapata OK)"
            case 1: return "Modo 1 (Bloquea Flash Zapata)"
            case 2: return "Modo 2 (Bloquea Flash Zapata)"
            default: return "Modo \(rawValue)"
            }
        case .stroboFiring:
            return rawValue == 0 ? "Habilitado" : "Deshabilitado"
        case .stroboDispState:
            return rawValue == 0 ? "Cerrado / Zapata" : "Activo (0x\(String(rawValue, radix: 16)))"
        case .lensName:
            return "—"
        }
    }

    package static func batteryPercent(for rawValue: UInt32) -> Int? {
        switch rawValue {
        case 4: return 100
        case 3: return 75
        case 2: return 50
        case 1: return 25
        case 0: return 5
        case 5...100: return Int(rawValue)
        default: return nil // AC / external power supply
        }
    }

    package static func buildOptions(for property: CameraPropertyID, rawValues: [UInt32]) -> [CameraPropertyOption] {
        var seen = Set<UInt32>()
        var options: [CameraPropertyOption] = []
        options.reserveCapacity(rawValues.count)
        for val in rawValues {
            guard seen.insert(val).inserted else { continue }
            options.append(CameraPropertyOption(rawValue: val, label: label(for: property, rawValue: val)))
        }
        return options
    }
}

package struct CameraControlSnapshot: Sendable, Hashable {
    package var deviceName: String
    package var isDemoMode: Bool
    package var lensName: String?
    package var aeModeValue: UInt32?
    package var aeModeLabel: String?
    package var batteryPercent: Int?
    package var batteryPercentLabel: String?
    package var availableShots: UInt32?
    package var silentShutterValue: UInt32?
    package var stroboFiringValue: UInt32?
    package var stroboDispState: UInt32?
    package var liveViewZoom: UInt32
    package var isDOFPreviewActive: Bool
    package var isMirrorDownOpticalFlashMode: Bool
    package var flashAccessory: FlashAccessorySelection
    package var keepOriginalsOnSD: Bool
    package var currentCaptureDestRaw: UInt32?
    package var detectedCardCaptureDest: UInt32?
    package var deviceCapabilityNotice: String?
    package var controls: [CameraPropertyID: CameraPropertyControl]
    package var lastUpdated: Date

    package init(
        deviceName: String,
        isDemoMode: Bool = false,
        lensName: String? = nil,
        aeModeValue: UInt32? = nil,
        aeModeLabel: String? = nil,
        batteryPercent: Int? = nil,
        batteryPercentLabel: String? = nil,
        availableShots: UInt32? = nil,
        silentShutterValue: UInt32? = nil,
        stroboFiringValue: UInt32? = nil,
        stroboDispState: UInt32? = nil,
        liveViewZoom: UInt32 = 1,
        isDOFPreviewActive: Bool = false,
        isMirrorDownOpticalFlashMode: Bool = false,
        flashAccessory: FlashAccessorySelection = .externalHotShoe,
        keepOriginalsOnSD: Bool = false,
        currentCaptureDestRaw: UInt32? = nil,
        detectedCardCaptureDest: UInt32? = nil,
        deviceCapabilityNotice: String? = nil,
        controls: [CameraPropertyID: CameraPropertyControl] = [:],
        lastUpdated: Date = .now
    ) {
        self.deviceName = deviceName
        self.isDemoMode = isDemoMode
        self.lensName = lensName
        self.aeModeValue = aeModeValue
        self.aeModeLabel = aeModeLabel
        self.batteryPercent = batteryPercent
        self.batteryPercentLabel = batteryPercentLabel
        self.availableShots = availableShots
        self.silentShutterValue = silentShutterValue
        self.stroboFiringValue = stroboFiringValue
        self.stroboDispState = stroboDispState
        self.liveViewZoom = liveViewZoom
        self.isDOFPreviewActive = isDOFPreviewActive
        self.isMirrorDownOpticalFlashMode = isMirrorDownOpticalFlashMode
        self.flashAccessory = flashAccessory
        self.keepOriginalsOnSD = keepOriginalsOnSD
        self.currentCaptureDestRaw = currentCaptureDestRaw
        self.detectedCardCaptureDest = detectedCardCaptureDest
        self.deviceCapabilityNotice = deviceCapabilityNotice
        self.controls = controls
        self.lastUpdated = lastUpdated
    }

    package var orderedPrimaryExposureControls: [CameraPropertyControl] {
        CameraPropertyID.primaryExposureOrder.compactMap { controls[$0] }
    }

    package var orderedCreativeControls: [CameraPropertyControl] {
        CameraPropertyID.creativeControlOrder.compactMap { controls[$0] }
    }

    package var isSilentLVBlockingFlash: Bool {
        silentShutterValue == 1 || silentShutterValue == 2
    }

    package var isFlashFiringDisabled: Bool {
        stroboFiringValue == 1
    }

    package var isAEModeBlockingFlash: Bool {
        // 0x0F: Flash Off, 0x09: Auto+, 0x14: Video
        aeModeValue == 0x0F || aeModeValue == 0x14
    }

    package mutating func refreshContextualLockExplanations() {
        let modeText = aeModeLabel ?? "este modo"
        if var exp = controls[.exposureCompensation] {
            if aeModeValue == 0x03 || aeModeValue == 0x04 {
                exp.isWritable = false
                exp.lockExplanation = "En modo \(modeText), la cámara no usa compensación EV: controlás la exposición directo con Velocidad, Apertura e ISO."
            } else if exp.availableOptions.isEmpty {
                exp.isWritable = false
                exp.lockExplanation = "Bloqueado por la cámara en modo \(modeText)."
            } else {
                exp.isWritable = true
                exp.lockExplanation = nil
            }
            controls[.exposureCompensation] = exp
        }

        if var aperture = controls[.aperture], aperture.availableOptions.isEmpty {
            aperture.isWritable = false
            if lensName?.isEmpty != false {
                aperture.lockExplanation = "Sin lente electrónico detectado o bloqueado por el modo \(modeText)."
            } else {
                aperture.lockExplanation = "En modo \(modeText), la cámara decide la apertura automáticamente."
            }
            controls[.aperture] = aperture
        }

        if var shutter = controls[.shutterSpeed], shutter.availableOptions.isEmpty {
            shutter.isWritable = false
            shutter.lockExplanation = "En modo \(modeText), la cámara calcula la velocidad automáticamente."
            controls[.shutterSpeed] = shutter
        }

        if var iso = controls[.iso], iso.availableOptions.isEmpty {
            iso.isWritable = false
            iso.lockExplanation = "El dial actual (\(modeText)) fija ISO en Auto."
            controls[.iso] = iso
        }

        let wbValue = controls[.whiteBalance]?.currentValue
        if var kelvin = controls[.colorTemperature] {
            if wbValue == 9 && !kelvin.availableOptions.isEmpty {
                kelvin.isWritable = true
                kelvin.lockExplanation = nil
            } else if wbValue != 9 {
                kelvin.isWritable = false
                kelvin.lockExplanation = "Cambiá Balance de Blancos a \"Kelvin (K)\" para ajustar los grados Kelvin manualmente."
            } else if kelvin.availableOptions.isEmpty {
                kelvin.isWritable = false
                kelvin.lockExplanation = "Seleccioná Balance de Blancos \"Kelvin (K)\" en la cámara."
            }
            controls[.colorTemperature] = kelvin
        }

        if var focus = controls[.focusMode], focus.availableOptions.isEmpty {
            focus.isWritable = false
            focus.lockExplanation = "El interruptor físico AF/MF del lente controla este ajuste."
            controls[.focusMode] = focus
        }
    }

    package mutating func applyDemoChange(property: CameraPropertyID, rawValue: UInt32) {
        if var existing = controls[property] {
            existing.currentValue = rawValue
            existing.currentLabel = CanonEOSLookupTables.label(for: property, rawValue: rawValue)
            controls[property] = existing
        }
        switch property {
        case .silentShutter:
            silentShutterValue = rawValue
        case .stroboFiring:
            stroboFiringValue = rawValue
        case .aeMode:
            aeModeValue = rawValue
            aeModeLabel = CanonEOSLookupTables.label(for: .aeMode, rawValue: rawValue)
        default:
            break
        }
        refreshContextualLockExplanations()
        lastUpdated = .now
    }

    package static func canon70DDemo() -> CameraControlSnapshot {
        let shutterOpts = CanonEOSLookupTables.buildOptions(for: .shutterSpeed, rawValues: [
            0x58, 0x60, 0x65, 0x68, 0x6D, 0x70, 0x75, 0x78, 0x80, 0x88, 0x90
        ])
        let apertureOpts = CanonEOSLookupTables.buildOptions(for: .aperture, rawValues: [
            0x20, 0x24, 0x28, 0x2D, 0x30, 0x35, 0x38, 0x40, 0x48
        ])
        let isoOpts = CanonEOSLookupTables.buildOptions(for: .iso, rawValues: [
            0x0048, 0x0050, 0x0058, 0x0060, 0x0068, 0x0070, 0x0078
        ])
        let expOpts = CanonEOSLookupTables.buildOptions(for: .exposureCompensation, rawValues: [
            0xF0, 0xF5, 0xF8, 0xFD, 0x00, 0x03, 0x08, 0x0B, 0x10
        ])
        let wbOpts = CanonEOSLookupTables.buildOptions(for: .whiteBalance, rawValues: [
            0, 1, 2, 3, 4, 5, 8, 9
        ])
        let kelvinOpts = CanonEOSLookupTables.buildOptions(for: .colorTemperature, rawValues: [
            3200, 4000, 4800, 5200, 5500, 6000, 6500, 7500
        ])
        let meteringOpts = CanonEOSLookupTables.buildOptions(for: .meteringMode, rawValues: [
            3, 4, 1, 0
        ])
        let driveOpts = CanonEOSLookupTables.buildOptions(for: .driveMode, rawValues: [
            0x00, 0x01, 0x06, 0x11, 0x10
        ])
        let pictureOpts = CanonEOSLookupTables.buildOptions(for: .pictureStyle, rawValues: [
            0x81, 0x82, 0x83, 0x84, 0x85, 0x86
        ])
        let silentOpts = CanonEOSLookupTables.buildOptions(for: .silentShutter, rawValues: [
            0, 1, 2
        ])

        let controls: [CameraPropertyID: CameraPropertyControl] = [
            .shutterSpeed: CameraPropertyControl(
                property: .shutterSpeed,
                currentValue: 0x75,
                availableOptions: shutterOpts,
                isWritable: true
            ),
            .aperture: CameraPropertyControl(
                property: .aperture,
                currentValue: 0x28,
                availableOptions: apertureOpts,
                isWritable: true
            ),
            .iso: CameraPropertyControl(
                property: .iso,
                currentValue: 0x0058,
                availableOptions: isoOpts,
                isWritable: true
            ),
            .exposureCompensation: CameraPropertyControl(
                property: .exposureCompensation,
                currentValue: 0x00,
                availableOptions: expOpts,
                isWritable: false
            ),
            .whiteBalance: CameraPropertyControl(
                property: .whiteBalance,
                currentValue: 5,
                availableOptions: wbOpts,
                isWritable: true
            ),
            .colorTemperature: CameraPropertyControl(
                property: .colorTemperature,
                currentValue: 5500,
                availableOptions: kelvinOpts,
                isWritable: false
            ),
            .meteringMode: CameraPropertyControl(
                property: .meteringMode,
                currentValue: 3,
                availableOptions: meteringOpts,
                isWritable: true
            ),
            .focusMode: CameraPropertyControl(
                property: .focusMode,
                currentValue: 0,
                availableOptions: [],
                isWritable: false
            ),
            .driveMode: CameraPropertyControl(
                property: .driveMode,
                currentValue: 0x00,
                availableOptions: driveOpts,
                isWritable: true
            ),
            .pictureStyle: CameraPropertyControl(
                property: .pictureStyle,
                currentValue: 0x82,
                availableOptions: pictureOpts,
                isWritable: true
            ),
            .silentShutter: CameraPropertyControl(
                property: .silentShutter,
                currentValue: 0,
                availableOptions: silentOpts,
                isWritable: true
            )
        ]

        var snapshot = CameraControlSnapshot(
            deviceName: "Canon EOS 70D",
            isDemoMode: true,
            lensName: "EF-S 18-55mm f/3.5-5.6 IS STM",
            aeModeValue: 0x03,
            aeModeLabel: CanonEOSLookupTables.label(for: .aeMode, rawValue: 0x03),
            batteryPercentLabel: "75%",
            availableShots: 412,
            silentShutterValue: 0,
            stroboFiringValue: 0,
            stroboDispState: 0,
            liveViewZoom: 1,
            isDOFPreviewActive: false,
            isMirrorDownOpticalFlashMode: false,
            flashAccessory: .externalHotShoe,
            keepOriginalsOnSD: false,
            controls: controls
        )
        snapshot.refreshContextualLockExplanations()
        return snapshot
    }

    package static func adaptiveFallback(for device: ConnectedDeviceState, keepOriginalsOnSD: Bool) -> CameraControlSnapshot {
        let notice: String
        switch device.category {
        case .iPhoneIOS, .androidPTP:
            notice = "Los teléfonos (iOS/Android) bloquean la modificación remota de exposición, ISO y flash por cable USB PTP. Ajustá esos parámetros desde la pantalla del teléfono mientras PhotoPic recibe tus capturas en vivo (o usá Continuidad / Wi-Fi IP para video)."
        case .compactAction:
            notice = "Las cámaras de acción (ej. DJI Osmo / GoPro / Insta360) no exponen controles remotos PTP de exposición o flash por USB. Usá el modo Webcam USB en la pestaña 'UVC / HDMI' para video en vivo, y ajustá parámetros en la pantalla de la cámara."
        case .dslrMirrorless where device.usbVendorID == 0x04A9:
            notice = "Sincronizando descriptores y opciones permitidas PTP desde tu Canon..."
        case .dslrMirrorless:
            notice = "Esta cámara usa protocolo PTP estándar para recibir capturas y disparo remoto. Los ajustes de exposición y flash se controlan directamente desde los diales físicos del cuerpo."
        }

        return CameraControlSnapshot(
            deviceName: device.alias,
            isDemoMode: false,
            batteryPercentLabel: device.batteryLevel.map { "\($0)%" },
            keepOriginalsOnSD: keepOriginalsOnSD,
            deviceCapabilityNotice: notice,
            controls: [:]
        )
    }
}
