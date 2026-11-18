import Foundation

/// Brand-specific USB mode, trust prompt, and RAW capture configuration guides.
package enum DeviceBrandGuide: String, CaseIterable, Identifiable, Sendable {
    case samsungAndroid
    case pixelMotorolaAndroid
    case xiaomiChineseAndroid
    case iPhoneIOS
    case canonNikon
    case sonyFujifilm

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .samsungAndroid: return "Samsung Galaxy"
        case .pixelMotorolaAndroid: return "Pixel / Moto / Nothing"
        case .xiaomiChineseAndroid: return "Xiaomi / OnePlus / OPPO"
        case .iPhoneIOS: return "iPhone / iPad (iOS)"
        case .canonNikon: return "Canon EOS / Nikon"
        case .sonyFujifilm: return "Sony Alpha / Fujifilm"
        }
    }

    package var menuPathSummary: String {
        switch self {
        case .samsungAndroid:
            return "Notificación USB → 'Transferir imágenes (PTP)' + 'Permitir acceso'"
        case .pixelMotorolaAndroid:
            return "Tocar 2 veces 'Cargando este dispositivo por USB' → 'PTP'"
        case .xiaomiChineseAndroid:
            return "Notificación USB → 'Transferir fotos (PTP)' + mantener pantalla activa"
        case .iPhoneIOS:
            return "Desbloquear pantalla → Tocar 'Confiar' → Ingresar código del iPhone"
        case .canonNikon:
            return "Apagar Wi-Fi/NFC interno en el menú de la cámara → Modo PTP/Auto"
        case .sonyFujifilm:
            return "Menú → Conexión USB → Elegir 'MTP' o 'PTP' (evitar 'PC Remote' / Mass Storage)"
        }
    }

    package var modesToAvoid: String {
        switch self {
        case .samsungAndroid: return "Evitar: 'Solo carga', 'USB Tethering' y 'MIDI'"
        case .pixelMotorolaAndroid: return "Evitar: 'Sin transferencia de datos' y 'Solo carga'"
        case .xiaomiChineseAndroid: return "Evitar: 'Solo cargar' y bloqueo de pantalla prolongado"
        case .iPhoneIOS: return "Evitar: dejar el iPhone bloqueado o tocar 'No confiar'"
        case .canonNikon: return "Evitar: Wi-Fi activo en cámara (desactiva USB en Canon) y EOS Utility abierto"
        case .sonyFujifilm: return "Evitar: 'Almacenamiento masivo' y 'PC Remote' sin driver"
        }
    }

    package var checklistSteps: [String] {
        switch self {
        case .samsungAndroid:
            return [
                "1. Desbloqueá tu Samsung y bajá la cortina de notificaciones.",
                "2. Tocá la notificación USB y elegí 'Transferir imágenes (PTP)'.",
                "3. Si aparece '¿Permitir acceso a los datos del teléfono?', tocá 'Permitir'.",
                "4. Pulsá 'Probar / Despertar Permiso en Móvil' si aún no monta."
            ]
        case .pixelMotorolaAndroid:
            return [
                "1. Desbloqueá el teléfono y tocá 'Cargando este dispositivo por USB'.",
                "2. Volvé a tocar para expandir 'Usar USB para' y seleccioná 'PTP'.",
                "3. En Ajustes → Cámara habilitá RAW+JPEG (.DNG) para máxima calidad."
            ]
        case .xiaomiChineseAndroid:
            return [
                "1. Elegí 'Transferir fotos (PTP)' en el diálogo emergente de HyperOS/MIUI/ColorOS.",
                "2. Subí el tiempo de espera de pantalla: algunos Xiaomi cierran el USB tras 10 min bloqueados."
            ]
        case .iPhoneIOS:
            return [
                "1. Conectá el cable USB-C o Lightning con el iPhone desbloqueado.",
                "2. Pulsá 'Probar / Despertar Permiso en Móvil' para disparar el aviso '¿Confiar en esta computadora?'.",
                "3. Tocá 'Confiar' e ingresá tu código: PhotoPic reabrirá el enlace automáticamente."
            ]
        case .canonNikon:
            return [
                "1. En cámaras Canon EOS, desactivá el Wi-Fi / NFC interno (bloquea el puerto USB por firmware).",
                "2. Cerrá 'EOS Utility', 'NX Tether' o 'Fotos de Apple' si capturaron la cámara.",
                "3. Si aparece 'Ocupado por macOS', tocá 'Liberar macOS'."
            ]
        case .sonyFujifilm:
            return [
                "1. En Sony Alpha: Menú Red/Configuración → Conexión USB → seleccioná 'MTP' o 'PTP' (no Mass Storage).",
                "2. En Fujifilm X/GFX: Configuración de conexión → MODO CONEXIÓN USB → 'AUTO' o 'USB CARD READER'."
            ]
        }
    }

    package var rawTip: String {
        switch self {
        case .samsungAndroid:
            return "Usá Cámara nativa → Modo Pro (RAW/DNG) para recibir tomas en ~1s; Expert RAW procesa HDR ~40s y a veces cachea el DNG en 0 bytes por PTP."
        case .pixelMotorolaAndroid:
            return "Activá el formato RAW+JPEG en tu app de cámara para recibir DNG de 12/14 bits."
        case .xiaomiChineseAndroid:
            return "El modo Pro con DNG activa captura rápida por PTP sin comprimir en JPG."
        case .iPhoneIOS:
            return "Con Apple ProRAW activado (Ajustes → Cámara → Formatos), PhotoPic solicita activos originales sin recodificar (.DNG / .HEIC)."
        case .canonNikon:
            return "Disparando RAW + JPG, PhotoPic separa JPG/ y envía solo el RAW puro a tu cola de revisión."
        case .sonyFujifilm:
            return "Para Live View fluido a 60 fps sin cortar PTP, usá HDMI→USB en la pestaña 'Vista en Vivo'."
        }
    }
}

package struct ValidationStageResult: Sendable, Equatable {
    package let title: String
    package let detail: String
    package let passed: Bool
    package let warning: Bool
}

package struct ConnectionValidationReport: Sendable, Equatable {
    package let headline: String
    package let subheadline: String
    package let stages: [ValidationStageResult]
    package let recommendedGuide: DeviceBrandGuide
    package let hasUnmountedHardware: Bool
    package let conflictingApps: [String]
    package let ptpLockedByMacOS: Bool
    package let diagnosticSummaryText: String
}

/// Evaluates USB physical link, ImageCaptureCore / Direct USB PTP visibility, and active session readiness.
package enum DeviceConnectionDiagnostics {
    package static func evaluate(
        physical: [PhysicalUSBDevice],
        connected: [ConnectedDeviceState],
        conflictingApps: [String]
    ) -> ConnectionValidationReport {
        let physicalDetected = !physical.isEmpty || !connected.isEmpty
        let mountedInPTP = !connected.isEmpty
        let hasLiveReady = connected.contains { $0.status.isLiveSessionOpen }
        let needsPermission = connected.contains {
            $0.status == .androidPermissionRequired || $0.status == .accessRestrictedLocked
        }
        let hasError = connected.contains {
            if case .error = $0.status { return true }
            return false
        }
        let unmounted = !physical.isEmpty && connected.isEmpty

        let primaryPhys = physical.first
        let primaryConn = connected.first
        let ownerString = primaryPhys?.ptpExclusiveOwner ?? ""
        let ownerLower = ownerString.lowercased()
        let lockedByDaemon = ownerLower.contains("ptpcamera") || connected.contains { $0.status == .busyByMacOS }

        let speedNote = primaryPhys?.linkSpeedMbps.map { " · \($0) Mbps" } ?? ""
        let idNote: String = if let p = primaryPhys {
            String(format: " (0x%04X:0x%04X)", p.vendorID, p.productID)
        } else {
            ""
        }

        let stage1 = ValidationStageResult(
            title: "1. Enlace Físico USB",
            detail: physicalDetected
                ? "\(primaryPhys?.displayName ?? primaryConn?.deviceName ?? "USB")\(idNote)\(speedNote)."
                : "Sin cámara detectada en el bus USB (revisá cable o Autoapagado).",
            passed: physicalDetected,
            warning: false
        )

        let stage2Detail: String
        if lockedByDaemon {
            stage2Detail = "Bloqueado por macOS (\(ownerString.isEmpty ? "ptpcamerad" : ownerString)). Pulsá 'Liberar macOS'."
        } else if mountedInPTP {
            let transport = primaryConn?.transportType ?? "PTP"
            let ownerTag = ownerString.isEmpty ? "" : " · Dueño: \(ownerString)"
            stage2Detail = "Canal \(transport) disponible\(ownerTag)."
        } else if unmounted {
            stage2Detail = "Cable detectado, pero el equipo ocultó PTP (revisá guía abajo)."
        } else {
            stage2Detail = "Esperando interfaz PTP."
        }
        let stage2 = ValidationStageResult(
            title: "2. Protocolo PTP",
            detail: stage2Detail,
            passed: mountedInPTP && !lockedByDaemon,
            warning: unmounted || lockedByDaemon
        )

        let stage3Detail: String
        if hasLiveReady {
            stage3Detail = primaryConn?.usbVendorID == 0x04A9
                ? "Sesión PTP Directa abierta (sin indexar SD, listo para disparar)."
                : "Sesión abierta y transfiriendo originales."
        } else if needsPermission {
            stage3Detail = "Aceptá 'Permitir' / 'Confiar' en la pantalla del teléfono."
        } else if let errConn = connected.first(where: { if case .error = $0.status { return true }; return false }),
                  case .error(let errMsg) = errConn.status {
            stage3Detail = "Fallo de sesión: \(errMsg)"
        } else if let idxConn = connected.first(where: { $0.status.isIndexingCatalog }),
                  case .indexingCatalog(let pct, let count) = idxConn.status {
            stage3Detail = "Indexando catálogo SD (\(pct)% · \(count) archivos)."
        } else if mountedInPTP {
            stage3Detail = "Listo para vincular o abrir sesión."
        } else {
            stage3Detail = "Pendiente de etapa 2."
        }
        let stage3 = ValidationStageResult(
            title: "3. Permiso y Sesión",
            detail: stage3Detail,
            passed: hasLiveReady,
            warning: needsPermission || hasError
        )

        let guide = pickGuide(physical: physical, connected: connected)
        let headline: String
        let subheadline: String
        if hasLiveReady {
            headline = "Conexión validada y lista"
            subheadline = "Tethering activo en tiempo real."
        } else if lockedByDaemon {
            headline = "Canal USB retenido por macOS"
            subheadline = "Usá 'Liberar macOS' para tomar control directo desde PhotoPic."
        } else if needsPermission {
            headline = "Falta confirmar permiso en el dispositivo"
            subheadline = guide.menuPathSummary
        } else if unmounted {
            headline = "Dispositivo conectado en modo incompatible"
            subheadline = "Tu Mac ve el cable de \(primaryPhys?.displayName ?? "tu equipo"), pero no expone fotos PTP todavía."
        } else if !conflictingApps.isEmpty {
            headline = "Posible conflicto detectado: \(conflictingApps.joined(separator: ", "))"
            subheadline = "Cerrá apps competidoras si reclaman el puerto USB."
        } else {
            headline = "Listo para diagnosticar USB"
            subheadline = "Conectá o despertá tu cámara y pulsá 'Probar Conexión'."
        }

        let summaryLines = [
            "PhotoPic USB Validator Report",
            "Estado: \(headline) — \(subheadline)",
            "1) \(stage1.title): \(stage1.detail)",
            "2) \(stage2.title): \(stage2.detail)",
            "3) \(stage3.title): \(stage3.detail)",
            "Conflictos: \(conflictingApps.isEmpty ? "Ninguno" : conflictingApps.joined(separator: ", "))"
        ]

        return ConnectionValidationReport(
            headline: headline,
            subheadline: subheadline,
            stages: [stage1, stage2, stage3],
            recommendedGuide: guide,
            hasUnmountedHardware: unmounted,
            conflictingApps: conflictingApps,
            ptpLockedByMacOS: lockedByDaemon,
            diagnosticSummaryText: summaryLines.joined(separator: "\n")
        )
    }

    private static func pickGuide(
        physical: [PhysicalUSBDevice],
        connected: [ConnectedDeviceState]
    ) -> DeviceBrandGuide {
        let vid = connected.first?.usbVendorID ?? physical.first?.vendorID ?? 0
        let lowerName = (connected.first?.deviceName ?? physical.first?.displayName ?? "").lowercased()
        let category = connected.first?.category ?? physical.first?.category

        if category == .iPhoneIOS || vid == 0x05AC || lowerName.contains("iphone") || lowerName.contains("ipad") {
            return .iPhoneIOS
        }
        if vid == 0x04E8 || lowerName.contains("samsung") || lowerName.contains("sm-") || lowerName.contains("galaxy") {
            return .samsungAndroid
        }
        if vid == 0x18D1 || vid == 0x22B8 || vid == 0x2BDE || lowerName.contains("pixel") || lowerName.contains("moto") {
            return .pixelMotorolaAndroid
        }
        if vid == 0x2717 || vid == 0x2A70 || vid == 0x22D9 || vid == 0x3426 || vid == 0x2D95 {
            return .xiaomiChineseAndroid
        }
        if vid == 0x054C || vid == 0x04CB || vid == 0x04DA || lowerName.contains("sony") || lowerName.contains("fuji") || lowerName.contains("lumix") {
            return .sonyFujifilm
        }
        if category == .androidPTP {
            return .samsungAndroid
        }
        return .canonNikon
    }
}
