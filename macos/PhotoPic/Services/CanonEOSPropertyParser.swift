import Foundation

package enum CanonEOSPropertyParser {
    private static let eventPropValueChanged: UInt32 = 0xC189
    private static let eventAvailListChanged: UInt32 = 0xC18A

    @discardableResult
    package static func applyEvents(from payload: Data, into snapshot: inout CameraControlSnapshot) -> Bool {
        guard payload.count >= 8 else { return false }

        var changed = false
        var offset = 0

        while offset + 8 <= payload.count {
            let entrySize = readUInt32LE(payload, at: offset)
            let eventCode = readUInt32LE(payload, at: offset + 4)

            if entrySize < 8 { break }
            let intSize = Int(entrySize)
            if offset + intSize > payload.count { break }
            if eventCode == 0 { break }

            let entryEnd = offset + intSize

            switch eventCode {
            case eventPropValueChanged:
                if parsePropValueChanged(payload, offset: offset, entryEnd: entryEnd, into: &snapshot) {
                    changed = true
                }
            case eventAvailListChanged:
                if parseAvailListChanged(payload, offset: offset, entryEnd: entryEnd, into: &snapshot) {
                    changed = true
                }
            default:
                break
            }

            offset = entryEnd
        }

        if changed {
            snapshot.refreshContextualLockExplanations()
            snapshot.lastUpdated = .now
        }

        return changed
    }

    package static func buildSetPropertyPayload(property: CameraPropertyID, rawValue: UInt32) -> Data {
        var data = Data(count: 12)
        writeUInt32LE(12, into: &data, at: 0)
        writeUInt32LE(property.rawValue, into: &data, at: 4)

        switch property.dataType {
        case .uint8:
            data[8] = UInt8(rawValue & 0xFF)
        case .uint16:
            writeUInt16LE(UInt16(rawValue & 0xFFFF), into: &data, at: 8)
        case .uint32, .string:
            writeUInt32LE(rawValue, into: &data, at: 8)
        }

        return data
    }

    private static func parsePropValueChanged(
        _ data: Data,
        offset: Int,
        entryEnd: Int,
        into snapshot: inout CameraControlSnapshot
    ) -> Bool {
        guard offset + 12 <= entryEnd else { return false }
        let propCode = readUInt32LE(data, at: offset + 8)
        guard let prop = CameraPropertyID(rawValue: propCode) else { return false }

        let valOffset = offset + 12
        let valLength = entryEnd - valOffset
        guard valLength >= 1 else { return false }

        if prop == .lensName {
            let lens = readCString(data, start: valOffset, end: entryEnd)
            snapshot.lensName = lens.isEmpty ? nil : lens
            return true
        }

        let rawVal: UInt32
        switch prop.dataType {
        case .uint8:
            rawVal = UInt32(data[valOffset])
        case .uint16:
            guard valLength >= 2 else { return false }
            rawVal = UInt32(readUInt16LE(data, at: valOffset))
        case .uint32:
            guard valLength >= 4 else { return false }
            rawVal = readUInt32LE(data, at: valOffset)
        case .string:
            return false
        }

        let label = CanonEOSLookupTables.label(for: prop, rawValue: rawVal)

        switch prop {
        case .aeMode:
            snapshot.aeModeValue = rawVal
            snapshot.aeModeLabel = label
        case .batteryPower:
            snapshot.batteryPercent = CanonEOSLookupTables.batteryPercent(for: rawVal)
            snapshot.batteryPercentLabel = label
        case .availableShots:
            snapshot.availableShots = rawVal
        case .captureDestination:
            snapshot.currentCaptureDestRaw = rawVal
            snapshot.keepOriginalsOnSD = (rawVal & 0x03) != 0
            if (rawVal & 0x03) != 0 && (rawVal & 0x04) != 0 {
                snapshot.detectedCardCaptureDest = rawVal
            } else if snapshot.detectedCardCaptureDest == nil, (rawVal & 0x03) != 0 {
                snapshot.detectedCardCaptureDest = rawVal | 0x04
            }
        case .silentShutter:
            snapshot.silentShutterValue = rawVal
            upsertControlValue(prop: prop, rawValue: rawVal, label: label, into: &snapshot)
        case .stroboFiring:
            snapshot.stroboFiringValue = rawVal
            upsertControlValue(prop: prop, rawValue: rawVal, label: label, into: &snapshot)
        case .stroboDispState:
            snapshot.stroboDispState = rawVal
        case .aperture, .shutterSpeed, .iso, .exposureCompensation,
             .driveMode, .meteringMode, .focusMode, .whiteBalance,
             .colorTemperature, .pictureStyle:
            upsertControlValue(prop: prop, rawValue: rawVal, label: label, into: &snapshot)
        case .lensName:
            break
        }

        return true
    }

    private static func parseAvailListChanged(
        _ data: Data,
        offset: Int,
        entryEnd: Int,
        into snapshot: inout CameraControlSnapshot
    ) -> Bool {
        guard offset + 20 <= entryEnd else { return false }
        let propCode = readUInt32LE(data, at: offset + 8)
        let dpdType = readUInt32LE(data, at: offset + 12)
        let count = readUInt32LE(data, at: offset + 16)

        guard let prop = CameraPropertyID(rawValue: propCode) else { return false }
        if prop == .captureDestination {
            guard dpdType == 3 && count > 0 else { return false }
            let maxCount = min(Int(count), 64)
            let listStart = offset + 20
            guard listStart + maxCount * 4 <= entryEnd else { return false }
            var candidates: [UInt32] = []
            candidates.reserveCapacity(maxCount)
            for index in 0..<maxCount {
                candidates.append(readUInt32LE(data, at: listStart + index * 4))
            }
            // Prefer simultaneous Card + Host PC (e.g. 6 = SD+Mac on Canon 70D, 5 = CF+Mac) so photos transfer to Mac AND save to SD!
            if let bothDest = candidates.first(where: { ($0 & 0x04) != 0 && ($0 & 0x03) != 0 }) {
                snapshot.detectedCardCaptureDest = bothDest
                return true
            }
            if let cardOnly = candidates.first(where: { ($0 & 0x03) != 0 }) {
                snapshot.detectedCardCaptureDest = cardOnly
                return true
            }
            return false
        }
        // Ignore telemetry-only properties in interactive option lists
        guard prop != .batteryPower, prop != .availableShots, prop != .lensName else {
            return false
        }

        var options: [CameraPropertyOption] = []
        if dpdType == 3 && count > 0 {
            let maxCount = min(Int(count), 1024)
            let listStart = offset + 20
            guard listStart + maxCount * 4 <= entryEnd else { return false }

            var rawValues: [UInt32] = []
            rawValues.reserveCapacity(maxCount)

            for index in 0..<maxCount {
                let elemOffset = listStart + index * 4
                let element: UInt32
                switch prop.dataType {
                case .uint8:
                    element = UInt32(data[elemOffset])
                case .uint16:
                    element = UInt32(readUInt16LE(data, at: elemOffset))
                case .uint32, .string:
                    element = readUInt32LE(data, at: elemOffset)
                }
                rawValues.append(element)
            }

            options = CanonEOSLookupTables.buildOptions(for: prop, rawValues: rawValues)
        } else if count == 0 {
            options = []
        } else {
            return false
        }

        let writable = !options.isEmpty && prop != .aeMode
        if var existing = snapshot.controls[prop] {
            existing.availableOptions = options
            existing.isWritable = writable
            snapshot.controls[prop] = existing
        } else {
            let fallbackVal = options.first?.rawValue ?? 0
            snapshot.controls[prop] = CameraPropertyControl(
                property: prop,
                currentValue: fallbackVal,
                currentLabel: CanonEOSLookupTables.label(for: prop, rawValue: fallbackVal),
                availableOptions: options,
                isWritable: writable
            )
        }

        return true
    }

    private static func upsertControlValue(
        prop: CameraPropertyID,
        rawValue: UInt32,
        label: String,
        into snapshot: inout CameraControlSnapshot
    ) {
        if var existing = snapshot.controls[prop] {
            existing.currentValue = rawValue
            existing.currentLabel = label
            snapshot.controls[prop] = existing
        } else {
            snapshot.controls[prop] = CameraPropertyControl(
                property: prop,
                currentValue: rawValue,
                currentLabel: label,
                availableOptions: [],
                isWritable: false
            )
        }
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        return b0 | b1
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private static func writeUInt16LE(_ value: UInt16, into data: inout Data, at offset: Int) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeUInt32LE(_ value: UInt32, into data: inout Data, at offset: Int) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func readCString(_ data: Data, start: Int, end: Int) -> String {
        guard start < end else { return "" }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(end - start, 128))
        for idx in start..<end {
            let byte = data[idx]
            if byte == 0 { break }
            bytes.append(byte)
        }
        return (String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .ascii) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
