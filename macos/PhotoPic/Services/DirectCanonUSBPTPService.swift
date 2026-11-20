import CoreGraphics
import Foundation
import IOKit
import IOKit.usb
import IOUSBHost
import ImageIO
import Observation
import os

// MARK: - Pure Canon EOS PTP Protocol Codec & Event Parser (Unit-Testable)

package enum CanonPTPCode {
    package static let canonVendorID = 0x04A9
    package static let ptpInterfaceClass = 6

    // Standard PTP Operations
    package static let getDeviceInfo: UInt16 = 0x1001
    package static let openSession: UInt16 = 0x1002
    package static let closeSession: UInt16 = 0x1003
    package static let getStorageIDs: UInt16 = 0x1004
    package static let getDevicePropDesc: UInt16 = 0x1014
    package static let getObject: UInt16 = 0x1009
    package static let getPartialObject: UInt16 = 0x101B

    // Canon EOS Operations
    package static let eosGetPartialObject: UInt16 = 0x9107
    package static let eosCapture: UInt16 = 0x910F
    package static let eosSetDevicePropValueEx: UInt16 = 0x9110
    package static let eosSetRemoteMode: UInt16 = 0x9114
    package static let eosSetEventMode: UInt16 = 0x9115
    package static let eosGetEvent: UInt16 = 0x9116
    package static let eosTransferComplete: UInt16 = 0x9117
    package static let eosCancelTransfer: UInt16 = 0x9118
    package static let eosPCHDDCapacity: UInt16 = 0x911A
    package static let eosSetUILock: UInt16 = 0x911B
    package static let eosResetUILock: UInt16 = 0x911C
    package static let eosRequestDevicePropValue: UInt16 = 0x9127
    package static let eosRemoteReleaseOn: UInt16 = 0x9128
    package static let eosRemoteReleaseOff: UInt16 = 0x9129
    package static let eosPopupBuiltinFlash: UInt16 = 0x9131
    package static let eosGetViewFinderData: UInt16 = 0x9153
    package static let eosDoAf: UInt16 = 0x9154
    package static let eosDriveLens: UInt16 = 0x9155
    package static let eosDepthOfFieldPreview: UInt16 = 0x9156
    package static let eosZoom: UInt16 = 0x9158
    package static let eosAfCancel: UInt16 = 0x9160

    // Canon EOS Device Properties
    package static let propCaptureDestination: UInt32 = 0xD11C
    package static let propSilentShutterSetting: UInt32 = 0xD129
    package static let propEVFOutputDevice: UInt32 = 0xD1B0
    package static let propEVFMode: UInt32 = 0xD1B1
    package static let propStroboFiring: UInt32 = 0xD1DC

    // CaptureDestination values
    package static let captureDestCardPrimary: UInt32 = 0x0001
    package static let captureDestCardSecondary: UInt32 = 0x0002
    package static let captureDestHostRAM: UInt32 = 0x0004

    // Standard PTP Responses
    package static let responseOK: UInt16 = 0x2001
    package static let responseOperationNotSupported: UInt16 = 0x2005
    package static let responseDeviceBusy: UInt16 = 0x2019
    package static let responseSessionAlreadyOpen: UInt16 = 0x201E
    package static let responseCanonNotReady: UInt16 = 0xA102

    // Canon EOS Events (inside 0x9116 GetEvent data block)
    package static let eventObjectAddedEx: UInt32 = 0xC181
    package static let eventRequestObjectTransfer: UInt32 = 0xC186
    package static let eventObjectAddedEx64: UInt32 = 0xC1A7
    package static let eventRequestObjectTransfer64: UInt32 = 0xC1A9
    package static let eventObjectAddedEx64LFN: UInt32 = 0xC1B6
    package static let eventRequestObjectTransfer64LFN: UInt32 = 0xC1B8

    // PTP Object Formats
    package static let formatFolderAssociation: UInt16 = 0x3001
    package static let formatCanonCRW: UInt16 = 0xB101
    package static let formatCanonCRW3: UInt16 = 0xB103
    package static let formatCanonCR3: UInt16 = 0xB108
}

package struct CanonEOSEventObject: Sendable, Equatable {
    package let handle: UInt32
    package let objectFormat: UInt16
    package let fileSize: UInt32
    package let filename: String
    package let isRAMTransfer: Bool

    package init(handle: UInt32, objectFormat: UInt16, fileSize: UInt32, filename: String, isRAMTransfer: Bool) {
        self.handle = handle
        self.objectFormat = objectFormat
        self.fileSize = fileSize
        self.filename = filename
        self.isRAMTransfer = isRAMTransfer
    }
}

package enum CanonUSBPTPCodec {
    package static func buildCommandContainer(opCode: UInt16, transactionID: UInt32, params: [UInt32] = []) -> Data {
        var data = Data(capacity: 12 + params.count * 4)
        appendUInt32LE(UInt32(12 + params.count * 4), to: &data)
        appendUInt16LE(1, to: &data) // Type 1 = Command Block
        appendUInt16LE(opCode, to: &data)
        appendUInt32LE(transactionID, to: &data)
        for p in params {
            appendUInt32LE(p, to: &data)
        }
        return data
    }

    package static func buildDataContainer(opCode: UInt16, transactionID: UInt32, payload: Data) -> Data {
        var data = Data(capacity: 12 + payload.count)
        appendUInt32LE(UInt32(12 + payload.count), to: &data)
        appendUInt16LE(2, to: &data) // Type 2 = Data Block
        appendUInt16LE(opCode, to: &data)
        appendUInt32LE(transactionID, to: &data)
        data.append(payload)
        return data
    }

    package static func buildSetPropUInt32Payload(propCode: UInt32, value: UInt32) -> Data {
        var payload = Data(capacity: 12)
        appendUInt32LE(12, to: &payload)
        appendUInt32LE(propCode, to: &payload)
        appendUInt32LE(value, to: &payload)
        return payload
    }

    package static func parseContainerHeader(_ data: Data) -> (length: UInt32, type: UInt16, code: UInt16, transactionID: UInt32)? {
        guard data.count >= 12 else { return nil }
        let length = readUInt32LE(data, at: 0)
        let type = readUInt16LE(data, at: 4)
        let code = readUInt16LE(data, at: 6)
        let txID = readUInt32LE(data, at: 8)
        return (length, type, code, txID)
    }

    /// Parses `0x9116` Canon EOS `GetEvent` payload into downloadable image events (ignoring directories).
    package static func parseEOSCaptureEvents(from data: Data, fallbackCounter: inout Int) -> [CanonEOSEventObject] {
        var results: [CanonEOSEventObject] = []
        var offset = 0

        while offset + 8 <= data.count {
            let entrySize = Int(readUInt32LE(data, at: offset))
            let eventCode = readUInt32LE(data, at: offset + 4)

            if entrySize == 8 && eventCode == 0 {
                break
            }
            guard entrySize >= 8, offset + entrySize <= data.count else {
                break
            }

            switch eventCode {
            case CanonPTPCode.eventRequestObjectTransfer,
                 CanonPTPCode.eventRequestObjectTransfer64:
                if entrySize >= 0x1D {
                    let handle = readUInt32LE(data, at: offset + 0x08)
                    let ofc = readUInt16LE(data, at: offset + 0x0C)
                    let fileSize = readUInt32LE(data, at: offset + 0x14)
                    let rawName = readCString(data, at: offset + 0x1C, limit: offset + entrySize)
                    if ofc != CanonPTPCode.formatFolderAssociation {
                        fallbackCounter += 1
                        let filename = normalizeFilename(rawName, ofc: ofc, counter: fallbackCounter)
                        results.append(CanonEOSEventObject(
                            handle: handle,
                            objectFormat: ofc,
                            fileSize: fileSize,
                            filename: filename,
                            isRAMTransfer: true
                        ))
                    }
                }

            case CanonPTPCode.eventRequestObjectTransfer64LFN:
                if entrySize >= 0x18 {
                    let handle = readUInt32LE(data, at: offset + 0x08)
                    let ofc = readUInt16LE(data, at: offset + 0x0C)
                    let fileSize = readUInt32LE(data, at: offset + 0x14)
                    if ofc != CanonPTPCode.formatFolderAssociation {
                        fallbackCounter += 1
                        let filename = normalizeFilename(nil, ofc: ofc, counter: fallbackCounter)
                        results.append(CanonEOSEventObject(
                            handle: handle,
                            objectFormat: ofc,
                            fileSize: fileSize,
                            filename: filename,
                            isRAMTransfer: true
                        ))
                    }
                }

            case CanonPTPCode.eventObjectAddedEx:
                if entrySize >= 0x29 {
                    let handle = readUInt32LE(data, at: offset + 0x08)
                    let ofc = readUInt16LE(data, at: offset + 0x10)
                    let fileSize = readUInt32LE(data, at: offset + 0x1C)
                    let rawName = readCString(data, at: offset + 0x28, limit: offset + entrySize)
                    if ofc != CanonPTPCode.formatFolderAssociation {
                        fallbackCounter += 1
                        let filename = normalizeFilename(rawName, ofc: ofc, counter: fallbackCounter)
                        results.append(CanonEOSEventObject(
                            handle: handle,
                            objectFormat: ofc,
                            fileSize: fileSize,
                            filename: filename,
                            isRAMTransfer: false
                        ))
                    }
                }

            case CanonPTPCode.eventObjectAddedEx64:
                if entrySize >= 0x2D {
                    let handle = readUInt32LE(data, at: offset + 0x08)
                    let ofc = readUInt16LE(data, at: offset + 0x10)
                    let fileSize = readUInt32LE(data, at: offset + 0x1C)
                    let rawName = readCString(data, at: offset + 0x2C, limit: offset + entrySize)
                    if ofc != CanonPTPCode.formatFolderAssociation {
                        fallbackCounter += 1
                        let filename = normalizeFilename(rawName, ofc: ofc, counter: fallbackCounter)
                        results.append(CanonEOSEventObject(
                            handle: handle,
                            objectFormat: ofc,
                            fileSize: fileSize,
                            filename: filename,
                            isRAMTransfer: false
                        ))
                    }
                }

            default:
                break
            }

            offset += entrySize
        }

        return results
    }

    package static func normalizeFilename(_ raw: String?, ofc: UInt16, counter: Int) -> String {
        if let raw {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return (trimmed as NSString).lastPathComponent
            }
        }
        let ext: String = switch ofc {
        case CanonPTPCode.formatCanonCRW, CanonPTPCode.formatCanonCRW3: "CR2"
        case CanonPTPCode.formatCanonCR3: "CR3"
        default: "JPG"
        }
        return String(format: "CANON_%04d.%@", counter, ext)
    }

    package static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    package static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }

    private static func readCString(_ data: Data, at startOffset: Int, limit: Int) -> String? {
        guard startOffset < limit, limit <= data.count else { return nil }
        let slice = data[(data.startIndex + startOffset)..<(data.startIndex + limit)]
        if let zeroIdx = slice.firstIndex(of: 0) {
            return String(data: slice[..<zeroIdx], encoding: .utf8)
        }
        return String(data: slice, encoding: .utf8)
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}

// MARK: - Low-Level Serialized IOUSBHost PTP Bulk Transport

private struct PTPBulkResult: Sendable {
    let dataPayload: Data
    let responseCode: UInt16
    let responseParams: [UInt32]
}

private enum CanonUSBTransportError: LocalizedError {
    case interfaceNotFound
    case openFailed(String)
    case endpointsMissing
    case ioFailed(String)
    case invalidHeader

    var errorDescription: String? {
        switch self {
        case .interfaceNotFound:
            return "No se encontró la interfaz USB PTP de Canon."
        case .openFailed(let detail):
            return "No se pudo tomar control exclusivo USB PTP (\(detail))."
        case .endpointsMissing:
            return "Faltan endpoints Bulk In/Out en la interfaz PTP Canon."
        case .ioFailed(let detail):
            return "Error de transferencia USB PTP: \(detail)"
        case .invalidHeader:
            return "Respuesta PTP USB incompleta o mal formada."
        }
    }
}

/// Owns exclusive `IOUSBHostInterface` + Bulk pipes on a dedicated serial queue so
/// event polling, Live View EVF frames, remote shutter, and file downloads never interleave.
private final class CanonUSBTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.kairosvisuals.photopic.canonusb.io", qos: .userInitiated)
    private var hostInterface: IOUSBHostInterface?
    private var bulkOutPipe: IOUSBHostPipe?
    private var bulkInPipe: IOUSBHostPipe?
    private var transactionCounter: UInt32 = 0
    private var isClosed = false
    private let onUnexpectedDisconnect: @Sendable () -> Void

    init(onUnexpectedDisconnect: @escaping @Sendable () -> Void) {
        self.onUnexpectedDisconnect = onUnexpectedDisconnect
    }

    func open(vendorID: Int, productID: Int) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.openSync(vendorID: vendorID, productID: productID)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func execute(opCode: UInt16, params: [UInt32] = [], outPayload: Data? = nil, timeout: TimeInterval = 6.0) async throws -> PTPBulkResult {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do {
                    let result = try self.executeSync(opCode: opCode, params: params, outPayload: outPayload, timeout: timeout)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func resetTransactionCounter() async {
        await withCheckedContinuation { cont in
            queue.async {
                self.transactionCounter = 0
                cont.resume()
            }
        }
    }

    func close() {
        queue.async {
            self.closeSync()
        }
    }

    // MARK: - Serial Queue Implementation

    private func openSync(vendorID: Int, productID: Int) throws {
        closeSync()
        isClosed = false

        var opened: IOUSBHostInterface?
        var lastError: NSError?

        // Release macOS ptpcamerad first, then acquire IOUSBHostInterface before launchd/icdd respawns it.
        for attempt in 0..<10 {
            Self.killMacOSPTPDaemonSync()
            Thread.sleep(forTimeInterval: attempt == 0 ? 0.06 : 0.08)

            guard let service = Self.findCanonPTPInterfaceService(vendorID: vendorID, productID: productID) else {
                if attempt == 9 {
                    throw CanonUSBTransportError.interfaceNotFound
                }
                continue
            }

            do {
                let iface = try IOUSBHostInterface(
                    __ioService: service,
                    options: [],
                    queue: nil
                ) { [weak self] _, messageType, _ in
                    // kIOMessageServiceIsTerminated == 0xE0000010
                    if messageType == 0xE000_0010 {
                        self?.onUnexpectedDisconnect()
                    }
                }
                IOObjectRelease(service)
                opened = iface
                break
            } catch {
                lastError = error as NSError
                // Retry once with .deviceSeize on the same service if needed
                if let seized = try? IOUSBHostInterface(
                    __ioService: service,
                    options: [.deviceSeize],
                    queue: nil,
                    interestHandler: { [weak self] _, messageType, _ in
                        if messageType == 0xE000_0010 {
                            self?.onUnexpectedDisconnect()
                        }
                    }
                ) {
                    IOObjectRelease(service)
                    opened = seized
                    break
                }
                IOObjectRelease(service)
            }
        }

        guard let iface = opened else {
            throw CanonUSBTransportError.openFailed(lastError?.localizedDescription ?? "desconocido")
        }

        try? iface.setIdleTimeout(0)

        guard let (outAddr, inAddr) = Self.findBulkEndpointAddresses(on: iface) else {
            iface.destroy()
            throw CanonUSBTransportError.endpointsMissing
        }

        let outPipe = try iface.copyPipe(withAddress: Int(outAddr))
        let inPipe = try iface.copyPipe(withAddress: Int(inAddr))
        try? outPipe.clearStall()
        try? inPipe.clearStall()

        self.hostInterface = iface
        self.bulkOutPipe = outPipe
        self.bulkInPipe = inPipe
        self.transactionCounter = 0
    }

    private func closeSync() {
        isClosed = true
        if let outPipe = bulkOutPipe {
            try? outPipe.__abort(with: .synchronous)
        }
        if let inPipe = bulkInPipe {
            try? inPipe.__abort(with: .synchronous)
        }
        bulkOutPipe = nil
        bulkInPipe = nil
        hostInterface?.destroy()
        hostInterface = nil
    }

    private func executeSync(opCode: UInt16, params: [UInt32], outPayload: Data?, timeout: TimeInterval) throws -> PTPBulkResult {
        guard !isClosed, let outPipe = bulkOutPipe, let inPipe = bulkInPipe else {
            throw CanonUSBTransportError.ioFailed("Sesión USB cerrada")
        }

        let txID: UInt32
        if opCode == CanonPTPCode.openSession {
            transactionCounter = 0
            txID = 0
        } else {
            transactionCounter &+= 1
            if transactionCounter == 0 { transactionCounter = 1 }
            txID = transactionCounter
        }

        let cmdData = CanonUSBPTPCodec.buildCommandContainer(opCode: opCode, transactionID: txID, params: params)
        try writeBulk(pipe: outPipe, data: cmdData, timeout: timeout)

        if let outPayload {
            let dataPacket = CanonUSBPTPCodec.buildDataContainer(opCode: opCode, transactionID: txID, payload: outPayload)
            try writeBulk(pipe: outPipe, data: dataPacket, timeout: timeout)
        }

        // Read first Bulk-In transfer (64 KB aligned to USB packet size)
        let firstChunk = try readBulkChunk(pipe: inPipe, maxBytes: 65_536, timeout: timeout)
        guard let header = CanonUSBPTPCodec.parseContainerHeader(firstChunk) else {
            throw CanonUSBTransportError.invalidHeader
        }

        if header.type == 3 {
            let params = extractResponseParams(from: firstChunk)
            return PTPBulkResult(dataPayload: Data(), responseCode: header.code, responseParams: params)
        }

        guard header.type == 2 else {
            throw CanonUSBTransportError.invalidHeader
        }

        let totalExpected = Int(header.length)
        var assembled = Data(capacity: max(totalExpected, firstChunk.count))
        assembled.append(firstChunk)

        while assembled.count < totalExpected {
            let remaining = totalExpected - assembled.count
            // Round up read request to multiple of 512 bytes (USB 2.0/3.0 maxPacketSize) to prevent overrun errors.
            let chunkRequest = min(262_144, ((remaining + 511) / 512) * 512)
            let chunk = try readBulkChunk(pipe: inPipe, maxBytes: max(512, chunkRequest), timeout: max(timeout, 10.0))
            if chunk.isEmpty { break }
            assembled.append(chunk)
        }

        guard assembled.count >= totalExpected, totalExpected >= 12 else {
            throw CanonUSBTransportError.invalidHeader
        }

        let payload = assembled.subdata(in: 12..<totalExpected)

        // If Response block was concatenated right after Data block in rare firmware, parse it directly; otherwise read Bulk-In.
        let respData: Data
        if assembled.count >= totalExpected + 12 {
            respData = assembled.subdata(in: totalExpected..<assembled.count)
        } else {
            respData = try readBulkChunk(pipe: inPipe, maxBytes: 65_536, timeout: timeout)
        }

        guard let respHeader = CanonUSBPTPCodec.parseContainerHeader(respData), respHeader.type == 3 else {
            throw CanonUSBTransportError.invalidHeader
        }

        return PTPBulkResult(
            dataPayload: payload,
            responseCode: respHeader.code,
            responseParams: extractResponseParams(from: respData)
        )
    }

    private func writeBulk(pipe: IOUSBHostPipe, data: Data, timeout: TimeInterval) throws {
        let mutable = NSMutableData(data: data)
        var transferred: Int = 0
        do {
            try pipe.__sendIORequest(with: mutable, bytesTransferred: &transferred, completionTimeout: timeout)
        } catch {
            try? pipe.clearStall()
            throw CanonUSBTransportError.ioFailed(error.localizedDescription)
        }
    }

    private func readBulkChunk(pipe: IOUSBHostPipe, maxBytes: Int, timeout: TimeInterval) throws -> Data {
        guard let mutable = NSMutableData(length: maxBytes) else {
            throw CanonUSBTransportError.ioFailed("Sin memoria para buffer USB")
        }
        var transferred: Int = 0
        do {
            try pipe.__sendIORequest(with: mutable, bytesTransferred: &transferred, completionTimeout: timeout)
        } catch {
            try? pipe.clearStall()
            throw CanonUSBTransportError.ioFailed(error.localizedDescription)
        }
        return Data(bytes: mutable.bytes, count: transferred)
    }

    private func extractResponseParams(from resp: Data) -> [UInt32] {
        guard resp.count > 12 else { return [] }
        var params: [UInt32] = []
        var offset = 12
        while offset + 4 <= resp.count {
            params.append(CanonUSBPTPCodec.readUInt32LE(resp, at: offset))
            offset += 4
        }
        return params
    }

    // MARK: - IOKit Discovery Helpers

    private static func findCanonPTPInterfaceService(vendorID: Int, productID: Int) -> io_service_t? {
        guard let matching = IOServiceMatching("IOUSBHostInterface") as NSMutableDictionary? else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propsRef?.takeRetainedValue() as? [String: Any] {
                let intfClass = dict["bInterfaceClass"] as? Int ?? -1
                let vid = (dict["idVendor"] as? Int) ?? parentIntProperty(service, key: "idVendor")
                let pid = (dict["idProduct"] as? Int) ?? parentIntProperty(service, key: "idProduct")
                if intfClass == CanonPTPCode.ptpInterfaceClass && vid == vendorID && (productID == 0 || pid == productID) {
                    return service // Caller owns & releases
                }
            }
            IOObjectRelease(service)
        }
        return nil
    }

    private static func parentIntProperty(_ service: io_registry_entry_t, key: String) -> Int? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        return IORegistryEntryCreateCFProperty(parent, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }

    private static func findBulkEndpointAddresses(on interface: IOUSBHostInterface) -> (outAddr: UInt8, inAddr: UInt8)? {
        let cfg = interface.configurationDescriptor
        let intf = interface.interfaceDescriptor
        let totalLength = Int(cfg.pointee.wTotalLength)
        guard totalLength >= 9 else { return nil }

        let raw = Data(bytes: cfg, count: totalLength)
        let targetInterfaceNumber = intf.pointee.bInterfaceNumber
        let targetAltSetting = intf.pointee.bAlternateSetting

        var outAddr: UInt8?
        var inAddr: UInt8?
        var offset = 0
        var insideTargetInterface = false

        while offset + 2 <= raw.count {
            let len = Int(raw[offset])
            let descType = raw[offset + 1]
            guard len >= 2, offset + len <= raw.count else { break }

            if descType == UInt8(kUSBInterfaceDesc) && len >= 9 {
                let ifaceNum = raw[offset + 2]
                let altSetting = raw[offset + 3]
                insideTargetInterface = (ifaceNum == targetInterfaceNumber && altSetting == targetAltSetting)
            } else if insideTargetInterface && descType == UInt8(kUSBEndpointDesc) && len >= 7 {
                let addr = raw[offset + 2]
                let transferType = raw[offset + 3] & 0x03 // 2 == Bulk
                if transferType == 2 {
                    if (addr & 0x80) == 0 {
                        outAddr = addr
                    } else {
                        inAddr = addr
                    }
                }
            }
            offset += len
        }

        if let outAddr, let inAddr {
            return (outAddr, inAddr)
        }
        return nil
    }

    private static func killMacOSPTPDaemonSync() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["-9", "PTPCamera", "ptpcamerad"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - MainActor Direct Canon EOS Tethering & Live View Service

/// Direct zero-index USB PTP tethering & Live View engine for Canon EOS bodies (e.g. 70D, 80D, R-series).
/// Bypasses Apple `ptpcamerad` so connection opens in <1s even with thousands of photos on SD,
/// and supports RAM-direct PC capture when `keepOriginalsOnDevice == false`.
@MainActor
@Observable
package final class DirectCanonUSBPTPService {
    private let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "DirectCanonPTP")

    private struct SessionContext {
        var profile: KnownDevice
        let transport: CanonUSBTransport
        var pollTask: Task<Void, Never>?
        var isLiveViewActive: Bool = false
        var isTriggeringShutter: Bool = false
        var fileCounter: Int = 0
        var seenHandles: Set<UInt32> = []
        var activeDownloads: Int = 0
        var lastCaptureDestIsHostRAM: Bool = false
    }

    private var sessions: [String: SessionContext] = [:]

    package private(set) var isDirectLiveViewStreaming = false
    package private(set) var directLiveViewFPS = 0
    package var directLiveViewStatusNote: String?
    package private(set) var controlSnapshots: [String: CameraControlSnapshot] = [:]
    package var inlineFeedbackNote: String?

    private var liveViewStreamTask: Task<Void, Never>?
    private var liveViewGeneration: Int = 0
    private var activeLiveFingerprint: String?

    package var onStatusChanged: ((String, DeviceConnectionStatus, Int?) -> Void)?
    package var onFileStaged: ((URL, String, KnownDevice) -> Void)?
    package var onCaptureError: ((String, String) -> Void)?

    package init() {}

    package func hasSession(for fingerprint: String) -> Bool {
        sessions[fingerprint] != nil
    }

    package func seedSnapshotForTesting(fingerprint: String, snapshot: CameraControlSnapshot) {
        controlSnapshots[fingerprint] = snapshot
    }

    package func openSession(profile: KnownDevice) {
        let fp = profile.fingerprint
        closeSession(for: fp, emitStatus: false)

        onStatusChanged?(fp, .connecting, nil)

        let transport = CanonUSBTransport { [weak self] in
            Task { @MainActor [weak self] in
                self?.handlePhysicalDisconnect(for: fp)
            }
        }

        let ctx = SessionContext(profile: profile, transport: transport)
        sessions[fp] = ctx

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await transport.open(vendorID: profile.usbVendorID, productID: profile.usbProductID)

                // OpenSession(1); if already open from previous run, close and reopen cleanly.
                var openRes = try await transport.execute(opCode: CanonPTPCode.openSession, params: [1])
                if openRes.responseCode == CanonPTPCode.responseSessionAlreadyOpen {
                    _ = try? await transport.execute(opCode: CanonPTPCode.closeSession)
                    await transport.resetTransactionCounter()
                    openRes = try await transport.execute(opCode: CanonPTPCode.openSession, params: [1])
                }
                guard openRes.responseCode == CanonPTPCode.responseOK || openRes.responseCode == CanonPTPCode.responseSessionAlreadyOpen else {
                    throw CanonUSBTransportError.ioFailed(String(format: "OpenSession rechazado (0x%04X)", openRes.responseCode))
                }

                // Enable Canon EOS Remote + Event mode (< 200ms, ZERO SD catalog scan!)
                let remoteRes = try await transport.execute(opCode: CanonPTPCode.eosSetRemoteMode, params: [1])
                guard remoteRes.responseCode != CanonPTPCode.responseOperationNotSupported else {
                    throw CanonUSBTransportError.ioFailed("Este modelo Canon no soporta RemoteMode PTP directo.")
                }
                _ = try await transport.execute(opCode: CanonPTPCode.eosSetEventMode, params: [1])
                // Ensure camera physical dials, menus, and flash controls stay unlocked while tethered
                _ = try? await transport.execute(opCode: CanonPTPCode.eosResetUILock)
                let stroboEnable = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propStroboFiring, value: 0)
                _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: stroboEnable)

                // Read boot property snapshots from eosGetEvent first so we know current/supported CaptureDestination (SD vs RAM)
                var snapshot = CameraControlSnapshot(
                    deviceName: profile.alias,
                    isDemoMode: false,
                    flashAccessory: .externalHotShoe,
                    keepOriginalsOnSD: profile.keepOriginalsOnDevice
                )
                if let bootRes1 = try? await transport.execute(opCode: CanonPTPCode.eosGetEvent), !bootRes1.dataPayload.isEmpty {
                    CanonEOSPropertyParser.applyEvents(from: bootRes1.dataPayload, into: &snapshot)
                }
                try? await Task.sleep(for: .milliseconds(50))
                if let bootRes2 = try? await transport.execute(opCode: CanonPTPCode.eosGetEvent), !bootRes2.dataPayload.isEmpty {
                    CanonEOSPropertyParser.applyEvents(from: bootRes2.dataPayload, into: &snapshot)
                }
                snapshot.keepOriginalsOnSD = profile.keepOriginalsOnDevice

                guard var activeCtx = self.sessions[fp] else {
                    transport.close()
                    return
                }
                activeCtx.lastCaptureDestIsHostRAM = !profile.keepOriginalsOnDevice
                self.sessions[fp] = activeCtx
                self.controlSnapshots[fp] = snapshot
                self.inlineFeedbackNote = nil

                // Apply CaptureDestination based on keepOriginalsOnDevice using detected SD value
                await self.applyCaptureDestination(transport: transport, keepOriginalsOnDevice: profile.keepOriginalsOnDevice, fingerprint: fp)

                self.onStatusChanged?(fp, .connectedReady, snapshot.batteryPercent)
                self.startEventPollLoop(for: fp)
            } catch {
                self.logger.error("Direct Canon openSession failed: \(error.localizedDescription, privacy: .public)")
                transport.close()
                self.sessions.removeValue(forKey: fp)
                self.controlSnapshots.removeValue(forKey: fp)
                self.onStatusChanged?(fp, .error(message: error.localizedDescription), nil)
            }
        }
    }

    package func closeSession(for fingerprint: String, emitStatus: Bool = true) {
        if activeLiveFingerprint == fingerprint {
            stopLiveView()
        }
        controlSnapshots.removeValue(forKey: fingerprint)
        guard let ctx = sessions.removeValue(forKey: fingerprint) else { return }
        ctx.pollTask?.cancel()
        let transport = ctx.transport
        Task.detached(priority: .userInitiated) {
            _ = try? await transport.execute(opCode: CanonPTPCode.eosSetEventMode, params: [0], timeout: 1.5)
            _ = try? await transport.execute(opCode: CanonPTPCode.eosSetRemoteMode, params: [0], timeout: 1.5)
            _ = try? await transport.execute(opCode: CanonPTPCode.closeSession, timeout: 1.5)
            transport.close()
        }
        if emitStatus {
            onStatusChanged?(fingerprint, .detectedNotConnected, nil)
        }
    }

    package func updateProfile(_ profile: KnownDevice) {
        let fp = profile.fingerprint
        guard var ctx = sessions[fp] else { return }
        let keepChanged = ctx.profile.keepOriginalsOnDevice != profile.keepOriginalsOnDevice
        ctx.profile = profile
        sessions[fp] = ctx
        controlSnapshots[fp]?.keepOriginalsOnSD = profile.keepOriginalsOnDevice

        if keepChanged {
            let transport = ctx.transport
            Task { @MainActor [weak self] in
                await self?.applyCaptureDestination(transport: transport, keepOriginalsOnDevice: profile.keepOriginalsOnDevice, fingerprint: fp)
            }
        }
    }

    package func popupBuiltinFlash(for fingerprint: String) async -> Bool {
        guard let ctx = sessions[fingerprint] else { return false }
        let transport = ctx.transport
        do {
            _ = try? await transport.execute(opCode: CanonPTPCode.eosResetUILock, timeout: 2.0)
            let stroboEnable = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propStroboFiring, value: 0)
            _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: stroboEnable, timeout: 2.0)
            let res = try await transport.execute(opCode: CanonPTPCode.eosPopupBuiltinFlash, timeout: 4.0)
            if res.responseCode == CanonPTPCode.responseOK {
                inlineFeedbackNote = "Flash interno levantado."
                return true
            }
            inlineFeedbackNote = "La cámara no pudo levantar el flash interno (revisá el dial físico o si hay algo bloqueando la zapata)."
            return false
        } catch {
            inlineFeedbackNote = "No se pudo levantar el flash interno."
            return false
        }
    }

    // MARK: - Adaptive Camera Controls & Safe External Hot-Shoe Flash

    package func setCameraProperty(for fingerprint: String, property: CameraPropertyID, rawValue: UInt32) async -> Bool {
        guard let ctx = sessions[fingerprint] else { return false }
        let transport = ctx.transport
        let payload = CanonEOSPropertyParser.buildSetPropertyPayload(property: property, rawValue: rawValue)

        do {
            var res = try await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: payload, timeout: 3.0)
            for backoffMs in [100, 200] where res.responseCode == CanonPTPCode.responseDeviceBusy || res.responseCode == CanonPTPCode.responseCanonNotReady {
                try? await Task.sleep(for: .milliseconds(backoffMs))
                res = try await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: payload, timeout: 3.0)
            }
            guard res.responseCode == CanonPTPCode.responseOK else {
                inlineFeedbackNote = "La cámara no permitió cambiar \(property.shortLabel) en este modo (revisá el dial físico)."
                return false
            }
            controlSnapshots[fingerprint]?.applyDemoChange(property: property, rawValue: rawValue)
            inlineFeedbackNote = nil
            return true
        } catch {
            inlineFeedbackNote = "No se pudo aplicar \(property.shortLabel): \(error.localizedDescription)"
            return false
        }
    }

    package func setFlashAccessory(for fingerprint: String, accessory: FlashAccessorySelection) async {
        controlSnapshots[fingerprint]?.flashAccessory = accessory
        switch accessory {
        case .externalHotShoe:
            // Strictly safe: disables Silent LV block (0xD129=0) and enables firing (0xD1DC=0), never touching 0x9131 popup.
            _ = await setCameraProperty(for: fingerprint, property: .silentShutter, rawValue: 0)
            _ = await setCameraProperty(for: fingerprint, property: .stroboFiring, rawValue: 0)
            inlineFeedbackNote = "Flash Externo (Zapata) activo: el flash interno permanecerá cerrado y protegido."
        case .disabled:
            _ = await setCameraProperty(for: fingerprint, property: .stroboFiring, rawValue: 1)
            inlineFeedbackNote = "Disparo de flash desactivado en cámara."
        case .builtinPopup:
            _ = await setCameraProperty(for: fingerprint, property: .stroboFiring, rawValue: 0)
            inlineFeedbackNote = "Modo Flash Interno listo (solo usá el botón manual si la zapata superior está libre)."
        }
    }

    package func engageOpticalHotShoeFlashMode(for fingerprint: String) async {
        stopLiveView()
        if let ctx = sessions[fingerprint] {
            let transport = ctx.transport
            let silentOff = CanonEOSPropertyParser.buildSetPropertyPayload(property: .silentShutter, rawValue: 0)
            _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: silentOff, timeout: 2.0)
            let stroboOn = CanonEOSPropertyParser.buildSetPropertyPayload(property: .stroboFiring, rawValue: 0)
            _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: stroboOn, timeout: 2.0)
        }
        controlSnapshots[fingerprint]?.applyDemoChange(property: .silentShutter, rawValue: 0)
        controlSnapshots[fingerprint]?.applyDemoChange(property: .stroboFiring, rawValue: 0)
        controlSnapshots[fingerprint]?.flashAccessory = .externalHotShoe
        controlSnapshots[fingerprint]?.isMirrorDownOpticalFlashMode = true
        inlineFeedbackNote = "Espejo abajo · Flash de Zapata listo: dispará desde la cámara o aquí; tus fotos siguen llegando al Mac."
    }

    package func triggerAutofocus(for fingerprint: String, cancel: Bool = false) async -> Bool {
        guard let ctx = sessions[fingerprint] else { return false }
        let opCode = cancel ? CanonPTPCode.eosAfCancel : CanonPTPCode.eosDoAf
        do {
            let res = try await ctx.transport.execute(opCode: opCode, timeout: 4.0)
            if res.responseCode == CanonPTPCode.responseOK {
                inlineFeedbackNote = cancel ? "Enfoque AF detenido." : "Enfoque AF ejecutado."
                return true
            }
            inlineFeedbackNote = "No se pudo enfocar ahora (revisá que el lente esté en AF y no esté muy cerca)."
            return false
        } catch {
            inlineFeedbackNote = "Error al ejecutar AF."
            return false
        }
    }

    package func driveManualFocus(for fingerprint: String, near: Bool, stepSize: UInt32 = 2) async -> Bool {
        guard let ctx = sessions[fingerprint] else { return false }
        let clamped = max(1, min(3, stepSize))
        let param: UInt32 = near ? clamped : (clamped | 0x8000)
        do {
            let res = try await ctx.transport.execute(opCode: CanonPTPCode.eosDriveLens, params: [param], timeout: 3.0)
            if res.responseCode == CanonPTPCode.responseOK {
                inlineFeedbackNote = near ? "Enfoque movido más cerca." : "Enfoque movido más lejos."
                return true
            }
            inlineFeedbackNote = "El motor de enfoque no respondió (revisá que el lente esté en modo AF durante Vista en Vivo)."
            return false
        } catch {
            inlineFeedbackNote = "Error al ajustar foco del lente."
            return false
        }
    }

    package func setLiveViewZoom(for fingerprint: String, zoomFactor: UInt32) async -> Bool {
        guard let ctx = sessions[fingerprint], [1, 5, 10].contains(zoomFactor) else { return false }
        do {
            let res = try await ctx.transport.execute(opCode: CanonPTPCode.eosZoom, params: [zoomFactor], timeout: 3.0)
            if res.responseCode == CanonPTPCode.responseOK {
                controlSnapshots[fingerprint]?.liveViewZoom = zoomFactor
                inlineFeedbackNote = nil
                return true
            }
            inlineFeedbackNote = "No se pudo cambiar el zoom del visor (\(zoomFactor)x)."
            return false
        } catch {
            inlineFeedbackNote = "Error cambiando zoom del visor."
            return false
        }
    }

    package func setDOFPreview(for fingerprint: String, enabled: Bool) async -> Bool {
        guard let ctx = sessions[fingerprint] else { return false }
        do {
            let res = try await ctx.transport.execute(
                opCode: CanonPTPCode.eosDepthOfFieldPreview,
                params: [enabled ? 1 : 0],
                timeout: 3.0
            )
            if res.responseCode == CanonPTPCode.responseOK {
                controlSnapshots[fingerprint]?.isDOFPreviewActive = enabled
                inlineFeedbackNote = nil
                return true
            }
            inlineFeedbackNote = "La previsualización de profundidad de campo (DOF) requiere Vista en Vivo activa."
            return false
        } catch {
            inlineFeedbackNote = "No se pudo cambiar DOF."
            return false
        }
    }

    package func triggerRemoteShutter(for fingerprint: String) async -> Bool {
        guard let ctx = sessions[fingerprint] else { return false }
        let transport = ctx.transport
        sessions[fingerprint]?.isTriggeringShutter = true
        defer {
            sessions[fingerprint]?.isTriggeringShutter = false
        }

        // In Manual Focus (MF), trigger immediate release without AF lock wait so dark-studio shots never stall.
        let isManualFocus = controlSnapshots[fingerprint]?.controls[.focusMode]?.currentValue == 3
        do {
            if isManualFocus {
                let immediatePress = try await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOn, params: [3, 0], timeout: 10.0)
                if immediatePress.responseCode == CanonPTPCode.responseOK {
                    try? await Task.sleep(for: .milliseconds(80))
                    _ = try? await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOff, params: [3], timeout: 5.0)
                    return true
                }
            }

            // Modern Canon EOS (70D, 80D, R-series) uses RemoteReleaseOn(1/2) + RemoteReleaseOff(2/1)
            let halfPress = try await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOn, params: [1, 0], timeout: 8.0)
            if halfPress.responseCode == CanonPTPCode.responseOperationNotSupported {
                let capRes = try await transport.execute(opCode: CanonPTPCode.eosCapture, timeout: 10.0)
                return capRes.responseCode == CanonPTPCode.responseOK
            }
            try? await Task.sleep(for: .milliseconds(160))
            let fullPress = try await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOn, params: [2, 0], timeout: 10.0)
            try? await Task.sleep(for: .milliseconds(80))
            let fullRelease = try await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOff, params: [2], timeout: 5.0)
            _ = try? await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOff, params: [1], timeout: 5.0)
            return fullPress.responseCode == CanonPTPCode.responseOK || fullRelease.responseCode == CanonPTPCode.responseOK
        } catch {
            _ = try? await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOff, params: [3], timeout: 2.0)
            _ = try? await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOff, params: [2], timeout: 2.0)
            _ = try? await transport.execute(opCode: CanonPTPCode.eosRemoteReleaseOff, params: [1], timeout: 2.0)
            onCaptureError?(fingerprint, error.localizedDescription)
            return false
        }
    }

    // MARK: - Direct USB Live View (Zero ImageCaptureCore Interference)

    package func startLiveView(
        for fingerprint: String,
        onFrame: @escaping @MainActor (CGImage) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        // Cancel any previous stream cleanly WITHOUT launching a racing disableLiveViewOnCamera Task
        // on the same camera (which previously turned EVF back OFF right after reopening).
        liveViewGeneration &+= 1
        let myGeneration = liveViewGeneration
        liveViewStreamTask?.cancel()
        liveViewStreamTask = nil

        if let prevFP = activeLiveFingerprint, prevFP != fingerprint, let prevTransport = sessions[prevFP]?.transport {
            Task { @MainActor [weak self] in
                await self?.disableLiveViewOnCamera(transport: prevTransport)
            }
        }

        guard let ctx = sessions[fingerprint] else {
            isDirectLiveViewStreaming = false
            activeLiveFingerprint = nil
            onError("La cámara Canon aún no tiene sesión USB abierta.")
            return
        }

        let transport = ctx.transport
        activeLiveFingerprint = fingerprint
        isDirectLiveViewStreaming = true
        sessions[fingerprint]?.isLiveViewActive = true
        controlSnapshots[fingerprint]?.isMirrorDownOpticalFlashMode = false
        directLiveViewStatusNote = "Activando espejo y visor USB directo en \(ctx.profile.alias)..."

        liveViewStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Brief settle window so any cancelled in-flight bulk transfer clears cleanly before re-enabling EVF.
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, self.liveViewGeneration == myGeneration else { return }

                // Respect the user's selected flash mode (never silently re-enable firing if user chose Sin Flash).
                let currentAccessory = self.controlSnapshots[fingerprint]?.flashAccessory ?? .externalHotShoe
                if currentAccessory != .disabled {
                    let silentOff = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propSilentShutterSetting, value: 0)
                    _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: silentOff)
                    let stroboEnable = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propStroboFiring, value: 0)
                    _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: stroboEnable)
                }

                let activated = try await self.enableLiveViewOnCamera(transport: transport)
                guard activated else {
                    throw CanonUSBTransportError.ioFailed("La cámara rechazó iniciar Live View (revisá que no tenga el menú abierto en pantalla).")
                }

                self.directLiveViewStatusNote = "Visor PTP USB directo · \(ctx.profile.alias)"
                var consecutiveBusy = 0
                var didAttemptAutoReattach = false
                var frames = 0
                var windowStart = Date()

                while !Task.isCancelled && self.isDirectLiveViewStreaming && self.liveViewGeneration == myGeneration {
                    // Only pause completely during the brief physical shutter exposure (~300ms) when the mirror/curtain blocks the sensor.
                    let liveCtx = self.sessions[fingerprint]
                    if liveCtx?.isTriggeringShutter == true {
                        consecutiveBusy = 0
                        didAttemptAutoReattach = false
                        try? await Task.sleep(for: .milliseconds(100))
                        continue
                    }

                    // During RAW+JPG chunk downloads, time-slice EVF frames (~5 FPS) between 1 MB USB chunks
                    // so live preview keeps updating while moving the camera without ever tripping busy timeout!
                    let isDownloading = (liveCtx?.activeDownloads ?? 0) > 0

                    let frameRes = try await transport.execute(
                        opCode: CanonPTPCode.eosGetViewFinderData,
                        params: [0x0020_0000],
                        timeout: 4.0
                    )

                    if frameRes.responseCode == CanonPTPCode.responseDeviceBusy || frameRes.responseCode == CanonPTPCode.responseCanonNotReady || frameRes.dataPayload.isEmpty {
                        if isDownloading {
                            consecutiveBusy = 0
                            try? await Task.sleep(for: .milliseconds(180))
                            continue
                        }
                        consecutiveBusy += 1
                        // After a shot (especially in continuous/burst drive on 70D), Canon may pause EVF briefly;
                        // silently re-assert EVFOutputDevice once before giving up.
                        if consecutiveBusy == 15 && !didAttemptAutoReattach {
                            didAttemptAutoReattach = true
                            _ = try? await self.enableLiveViewOnCamera(transport: transport)
                        }
                        if consecutiveBusy > 90 {
                            onError("El visor Live View se detuvo (la cámara cerró el espejo o entró en reposo).")
                            break
                        }
                        try? await Task.sleep(for: .milliseconds(90))
                        continue
                    }

                    if let jpeg = PTPLiveViewService.extractEmbeddedJPEG(from: frameRes.dataPayload),
                       let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
                       let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                        consecutiveBusy = 0
                        didAttemptAutoReattach = false
                        frames += 1
                        let dt = Date().timeIntervalSince(windowStart)
                        if dt >= 1.0 {
                            self.directLiveViewFPS = Int(Double(frames) / dt)
                            frames = 0
                            windowStart = Date()
                        }
                        onFrame(cg)
                    }
                    try? await Task.sleep(for: .milliseconds(isDownloading ? 180 : 45))
                }
            } catch {
                if !Task.isCancelled && self.liveViewGeneration == myGeneration {
                    self.directLiveViewStatusNote = error.localizedDescription
                    onError(error.localizedDescription)
                }
            }

            // Only tear down Live View on camera if no newer startLiveView generation has taken over!
            if self.liveViewGeneration == myGeneration {
                await self.disableLiveViewOnCamera(transport: transport)
                self.sessions[fingerprint]?.isLiveViewActive = false
                self.isDirectLiveViewStreaming = false
                self.directLiveViewFPS = 0
                if self.activeLiveFingerprint == fingerprint {
                    self.activeLiveFingerprint = nil
                }
            }
        }
    }

    package func stopLiveView() {
        let fp = activeLiveFingerprint
        liveViewGeneration &+= 1
        let stopGeneration = liveViewGeneration
        liveViewStreamTask?.cancel()
        liveViewStreamTask = nil
        isDirectLiveViewStreaming = false
        directLiveViewFPS = 0
        directLiveViewStatusNote = nil
        activeLiveFingerprint = nil
        if let fp {
            sessions[fp]?.isLiveViewActive = false
        }

        if let fp, let transport = sessions[fp]?.transport {
            Task { @MainActor [weak self] in
                guard let self, self.liveViewGeneration == stopGeneration else { return }
                await self.disableLiveViewOnCamera(transport: transport)
            }
        }
    }

    private func enableLiveViewOnCamera(transport: CanonUSBTransport) async throws -> Bool {
        let evfPayload = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propEVFMode, value: 1)
        let evfModeRes = try await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: evfPayload)
        try? await Task.sleep(for: .milliseconds(150))

        let outPayload3 = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propEVFOutputDevice, value: 3)
        var outRes = try await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: outPayload3)
        if outRes.responseCode != CanonPTPCode.responseOK {
            let outPayload2 = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propEVFOutputDevice, value: 2)
            outRes = try await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: outPayload2)
        }
        _ = try? await transport.execute(opCode: CanonPTPCode.eosResetUILock)
        return evfModeRes.responseCode == CanonPTPCode.responseOK || outRes.responseCode == CanonPTPCode.responseOK
    }

    // MARK: - Private Event Poll & Download Pipeline

    private func applyCaptureDestination(transport: CanonUSBTransport, keepOriginalsOnDevice: Bool, fingerprint: String) async {
        if !keepOriginalsOnDevice {
            if controlSnapshots[fingerprint]?.currentCaptureDestRaw != CanonPTPCode.captureDestHostRAM {
                let payload = CanonUSBPTPCodec.buildSetPropUInt32Payload(
                    propCode: CanonPTPCode.propCaptureDestination,
                    value: CanonPTPCode.captureDestHostRAM
                )
                let res = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: payload)
                if res?.responseCode == CanonPTPCode.responseOK {
                    controlSnapshots[fingerprint]?.currentCaptureDestRaw = CanonPTPCode.captureDestHostRAM
                }
            }
            _ = try? await transport.execute(
                opCode: CanonPTPCode.eosPCHDDCapacity,
                params: [0x0FFF_FFFF, 0x0000_1000, 0x0000_0001]
            )
            controlSnapshots[fingerprint]?.keepOriginalsOnSD = false
            sessions[fingerprint]?.lastCaptureDestIsHostRAM = true
        } else {
            let preferredCard = controlSnapshots[fingerprint]?.detectedCardCaptureDest ?? CanonPTPCode.captureDestCardSecondary
            if controlSnapshots[fingerprint]?.currentCaptureDestRaw == preferredCard {
                controlSnapshots[fingerprint]?.keepOriginalsOnSD = true
                sessions[fingerprint]?.lastCaptureDestIsHostRAM = false
                return
            }

            let primaryPayload = CanonUSBPTPCodec.buildSetPropUInt32Payload(
                propCode: CanonPTPCode.propCaptureDestination,
                value: preferredCard
            )
            let res1 = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: primaryPayload)
            if res1?.responseCode == CanonPTPCode.responseOK {
                controlSnapshots[fingerprint]?.currentCaptureDestRaw = preferredCard
                controlSnapshots[fingerprint]?.keepOriginalsOnSD = true
                sessions[fingerprint]?.lastCaptureDestIsHostRAM = false
                return
            }

            let fallbackCard = preferredCard == CanonPTPCode.captureDestCardSecondary
                ? CanonPTPCode.captureDestCardPrimary
                : CanonPTPCode.captureDestCardSecondary
            let fallbackPayload = CanonUSBPTPCodec.buildSetPropUInt32Payload(
                propCode: CanonPTPCode.propCaptureDestination,
                value: fallbackCard
            )
            let res2 = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: fallbackPayload)
            if res2?.responseCode == CanonPTPCode.responseOK {
                controlSnapshots[fingerprint]?.currentCaptureDestRaw = fallbackCard
                controlSnapshots[fingerprint]?.keepOriginalsOnSD = true
                sessions[fingerprint]?.lastCaptureDestIsHostRAM = false
                return
            }

            // Fall back safely to Host RAM if no SD/CF card is inserted
            let ramPayload = CanonUSBPTPCodec.buildSetPropUInt32Payload(
                propCode: CanonPTPCode.propCaptureDestination,
                value: CanonPTPCode.captureDestHostRAM
            )
            _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: ramPayload)
            _ = try? await transport.execute(
                opCode: CanonPTPCode.eosPCHDDCapacity,
                params: [0x0FFF_FFFF, 0x0000_1000, 0x0000_0001]
            )
            controlSnapshots[fingerprint]?.currentCaptureDestRaw = CanonPTPCode.captureDestHostRAM
            controlSnapshots[fingerprint]?.keepOriginalsOnSD = false
            sessions[fingerprint]?.lastCaptureDestIsHostRAM = true
            inlineFeedbackNote = "No se detectó tarjeta SD en la cámara; guardando directo en el Mac."
        }
    }

    private func disableLiveViewOnCamera(transport: CanonUSBTransport) async {
        let out0 = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propEVFOutputDevice, value: 0)
        _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: out0, timeout: 1.5)
        let evf0 = CanonUSBPTPCodec.buildSetPropUInt32Payload(propCode: CanonPTPCode.propEVFMode, value: 0)
        _ = try? await transport.execute(opCode: CanonPTPCode.eosSetDevicePropValueEx, outPayload: evf0, timeout: 1.5)
        _ = try? await transport.execute(opCode: CanonPTPCode.eosResetUILock, timeout: 1.5)
    }

    private func startEventPollLoop(for fingerprint: String) {
        sessions[fingerprint]?.pollTask?.cancel()
        sessions[fingerprint]?.pollTask = Task { @MainActor [weak self] in
            var consecutiveErrors = 0
            while !Task.isCancelled {
                guard let self, let ctx = self.sessions[fingerprint] else { break }
                do {
                    let eventRes = try await ctx.transport.execute(opCode: CanonPTPCode.eosGetEvent, timeout: 10.0)
                    consecutiveErrors = 0
                    if !eventRes.dataPayload.isEmpty, var latestCtx = self.sessions[fingerprint] {
                        let events = CanonUSBPTPCodec.parseEOSCaptureEvents(
                            from: eventRes.dataPayload,
                            fallbackCounter: &latestCtx.fileCounter
                        )
                        self.sessions[fingerprint] = latestCtx
                        var snap = self.controlSnapshots[fingerprint] ?? CameraControlSnapshot(
                            deviceName: latestCtx.profile.alias,
                            isDemoMode: false,
                            keepOriginalsOnSD: latestCtx.profile.keepOriginalsOnDevice
                        )
                        let previousBattery = snap.batteryPercent
                        if CanonEOSPropertyParser.applyEvents(from: eventRes.dataPayload, into: &snap) {
                            snap.keepOriginalsOnSD = latestCtx.profile.keepOriginalsOnDevice
                            self.controlSnapshots[fingerprint] = snap
                            if let updatedBattery = snap.batteryPercent, updatedBattery != previousBattery {
                                let status: DeviceConnectionStatus = latestCtx.activeDownloads > 0
                                    ? .capturing(activeDownloads: latestCtx.activeDownloads)
                                    : .connectedReady
                                self.onStatusChanged?(fingerprint, status, updatedBattery)
                            }
                        }
                        for item in events {
                            if self.sessions[fingerprint]?.seenHandles.contains(item.handle) == true {
                                continue
                            }
                            self.sessions[fingerprint]?.seenHandles.insert(item.handle)
                            await self.downloadAndStage(item: item, for: fingerprint)
                        }
                    }
                } catch {
                    if Task.isCancelled { break }
                    consecutiveErrors += 1
                    if consecutiveErrors >= 6 {
                        self.handlePhysicalDisconnect(for: fingerprint)
                        break
                    }
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func downloadAndStage(item: CanonEOSEventObject, for fingerprint: String) async {
        guard var ctx = sessions[fingerprint] else { return }
        ctx.activeDownloads += 1
        sessions[fingerprint] = ctx
        onStatusChanged?(fingerprint, .capturing(activeDownloads: ctx.activeDownloads), nil)

        let transport = ctx.transport
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicCanonDirect/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        do {
            var fileData = Data()
            if item.fileSize > 0 {
                fileData.reserveCapacity(Int(item.fileSize))
            }

            if item.isRAMTransfer || item.fileSize > 0 {
                // Chunked 1 MB reads avoid DIGIC bulk transfer lockups on large CR2/CR3 RAWs.
                let chunkSize: UInt32 = 1_048_576
                var offset: UInt32 = 0
                let total = item.fileSize
                var usedFullGetObjectFallback = false

                while total == 0 || offset < total {
                    let remaining = total > 0 ? min(chunkSize, total - offset) : chunkSize
                    let primaryPartialOp = item.isRAMTransfer ? CanonPTPCode.eosGetPartialObject : CanonPTPCode.getPartialObject
                    var res = try await transport.execute(
                        opCode: primaryPartialOp,
                        params: [item.handle, offset, remaining],
                        timeout: 15.0
                    )
                    if res.responseCode != CanonPTPCode.responseOK && offset == 0 {
                        let secondaryPartialOp = item.isRAMTransfer ? CanonPTPCode.getPartialObject : CanonPTPCode.eosGetPartialObject
                        let altRes = try await transport.execute(
                            opCode: secondaryPartialOp,
                            params: [item.handle, offset, remaining],
                            timeout: 15.0
                        )
                        if altRes.responseCode == CanonPTPCode.responseOK {
                            res = altRes
                        } else {
                            let fullRes = try await transport.execute(opCode: CanonPTPCode.getObject, params: [item.handle], timeout: 25.0)
                            guard fullRes.responseCode == CanonPTPCode.responseOK else {
                                throw CanonUSBTransportError.ioFailed(String(format: "GetObject error 0x%04X", fullRes.responseCode))
                            }
                            fileData = fullRes.dataPayload
                            usedFullGetObjectFallback = true
                            break
                        }
                    }
                    guard res.responseCode == CanonPTPCode.responseOK else {
                        throw CanonUSBTransportError.ioFailed(String(format: "Descarga falló (0x%04X)", res.responseCode))
                    }
                    if res.dataPayload.isEmpty { break }
                    fileData.append(res.dataPayload)
                    offset &+= UInt32(res.dataPayload.count)
                    if total == 0 && UInt32(res.dataPayload.count) < remaining { break }
                }

                if item.isRAMTransfer && !usedFullGetObjectFallback {
                    _ = try? await transport.execute(opCode: CanonPTPCode.eosTransferComplete, params: [item.handle])
                } else if item.isRAMTransfer {
                    _ = try? await transport.execute(opCode: CanonPTPCode.eosTransferComplete, params: [item.handle])
                }
            } else {
                let fullRes = try await transport.execute(opCode: CanonPTPCode.getObject, params: [item.handle], timeout: 25.0)
                guard fullRes.responseCode == CanonPTPCode.responseOK else {
                    throw CanonUSBTransportError.ioFailed(String(format: "GetObject error 0x%04X", fullRes.responseCode))
                }
                fileData = fullRes.dataPayload
            }

            if !fileData.isEmpty {
                let destURL = stagingDir.appendingPathComponent(item.filename)
                try fileData.write(to: destURL, options: .atomic)
                if let profile = sessions[fingerprint]?.profile {
                    onFileStaged?(destURL, item.filename, profile)
                }
            }
        } catch {
            logger.error("Direct Canon download error for \(item.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            onCaptureError?(fingerprint, error.localizedDescription)
            if item.isRAMTransfer {
                _ = try? await transport.execute(opCode: CanonPTPCode.eosCancelTransfer, params: [item.handle])
            }
        }

        try? FileManager.default.removeItem(at: stagingDir)
        if var updatedCtx = sessions[fingerprint] {
            updatedCtx.activeDownloads = max(0, updatedCtx.activeDownloads - 1)
            let remaining = updatedCtx.activeDownloads
            sessions[fingerprint] = updatedCtx
            onStatusChanged?(fingerprint, remaining > 0 ? .capturing(activeDownloads: remaining) : .connectedReady, nil)
        }
    }

    private func handlePhysicalDisconnect(for fingerprint: String) {
        if activeLiveFingerprint == fingerprint {
            stopLiveView()
        }
        controlSnapshots.removeValue(forKey: fingerprint)
        guard let ctx = sessions.removeValue(forKey: fingerprint) else { return }
        ctx.pollTask?.cancel()
        ctx.transport.close()
        onStatusChanged?(fingerprint, .disconnected(lastSeen: Date()), nil)
    }
}
