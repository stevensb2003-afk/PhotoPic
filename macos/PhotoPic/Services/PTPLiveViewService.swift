import CoreGraphics
import Foundation
@preconcurrency import ImageCaptureCore
import ImageIO
import Observation
import os

/// Native zero-dependency USB PTP Live View streamer for Canon EOS (e.g. 70D, 80D, 5D, R-series)
/// and Nikon DSLRs via `ICCameraDevice.requestSendPTPCommand`, keeping tethering active simultaneously.
@MainActor
@Observable
package final class PTPLiveViewService {
    private let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "PTPLiveView")

    package private(set) var isStreaming = false
    package private(set) var statusNote: String?
    package private(set) var fpsEstimate: Int = 0

    private var streamTask: Task<Void, Never>?
    private var activeCamera: ICCameraDevice?
    private var activeVendorID: Int = 0
    private var transactionCounter: UInt32 = 100
    private var isCapturingStill = false

    private enum CanonPTP {
        static let vendorID = 0x04A9 // 1193
        static let setRemoteMode: UInt16 = 0x9114
        static let setEventMode: UInt16 = 0x9115
        static let getEvent: UInt16 = 0x9116
        static let setDevicePropValueEx: UInt16 = 0x9110
        static let getViewFinderData: UInt16 = 0x9153
        static let capture: UInt16 = 0x910F
        static let remoteReleaseOn: UInt16 = 0x9128
        static let remoteReleaseOff: UInt16 = 0x9129
        static let propEVFOutputDevice: UInt32 = 0xD1B0
        static let propEVFMode: UInt32 = 0xD1B1
    }

    private enum NikonPTP {
        static let vendorID = 0x04B0 // 1200
        static let startLiveView: UInt16 = 0x9201
        static let endLiveView: UInt16 = 0x9202
        static let getLiveViewImage: UInt16 = 0x9203
        static let initiateCaptureRecInMedia: UInt16 = 0x9207
        static let initiateCapture: UInt16 = 0x100E
    }

    package init() {}

    package func supportsDirectPTPLiveView(vendorID: Int) -> Bool {
        vendorID == CanonPTP.vendorID || vendorID == NikonPTP.vendorID
    }

    package func startStream(
        camera: ICCameraDevice,
        deviceState: ConnectedDeviceState,
        onFrame: @escaping @MainActor (CGImage) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        stopStream()

        guard camera.hasOpenSession else {
            onError("La sesión PTP de \(deviceState.alias) aún no está abierta.")
            return
        }

        let vendor = deviceState.usbVendorID
        guard supportsDirectPTPLiveView(vendorID: vendor) else {
            onError("\(deviceState.alias) no expone visor PTP directo Canon/Nikon. En Sony/Lumix activá 'USB Streaming (UVC)' en el menú de la cámara o usá capturadora HDMI→USB.")
            return
        }

        activeCamera = camera
        activeVendorID = vendor
        isStreaming = true
        statusNote = "Activando espejo y visor PTP USB en \(deviceState.alias)..."

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = await self.enableCameraEVF(camera: camera, vendorID: vendor)
            guard started, !Task.isCancelled else {
                if !Task.isCancelled {
                    self.isStreaming = false
                    let msg = "La cámara no aceptó abrir Live View PTP USB. Verificá que no esté en modo video bloqueado ni con el menú abierto en pantalla."
                    self.statusNote = msg
                    onError(msg)
                }
                return
            }

            self.statusNote = "Visor PTP USB en vivo · \(deviceState.alias)"
            var consecutiveEmpty = 0
            var framesInWindow = 0
            var windowStart = Date()

            while !Task.isCancelled && self.isStreaming {
                if self.isCapturingStill {
                    try? await Task.sleep(for: .milliseconds(80))
                    continue
                }

                let result = await self.fetchSingleEVFFrame(camera: camera, vendorID: vendor)
                switch result {
                case .frame(let image):
                    consecutiveEmpty = 0
                    framesInWindow += 1
                    let elapsed = Date().timeIntervalSince(windowStart)
                    if elapsed >= 1.0 {
                        self.fpsEstimate = Int(Double(framesInWindow) / elapsed)
                        framesInWindow = 0
                        windowStart = Date()
                    }
                    onFrame(image)
                    try? await Task.sleep(for: .milliseconds(55))

                case .busyRetry:
                    consecutiveEmpty += 1
                    if consecutiveEmpty > 45 {
                        let msg = "Visor PTP detenido: la cámara dejó de entregar cuadros (espejo bajado o modo ahorro)."
                        self.statusNote = msg
                        onError(msg)
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(110))

                case .fatal(let reason):
                    self.statusNote = reason
                    onError(reason)
                    break
                }
            }

            await self.disableCameraEVF(camera: camera, vendorID: vendor)
            self.isStreaming = false
            self.fpsEstimate = 0
        }
    }

    package func stopStream() {
        let cam = activeCamera
        let vendor = activeVendorID
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        fpsEstimate = 0
        statusNote = nil
        activeCamera = nil

        if let cam, cam.hasOpenSession, supportsDirectPTPLiveView(vendorID: vendor) {
            Task { @MainActor [weak self] in
                await self?.disableCameraEVF(camera: cam, vendorID: vendor)
            }
        }
    }

    package func triggerRemoteShutter() async -> Bool {
        guard let cam = activeCamera, cam.hasOpenSession else { return false }
        isCapturingStill = true
        defer { isCapturingStill = false }

        try? await Task.sleep(for: .milliseconds(70))

        if activeVendorID == CanonPTP.vendorID {
            let capResp = await sendCommand(camera: cam, opCode: CanonPTP.capture)
            var ok = capResp.responseCode == 0x2001
            if !ok {
                let onResp = await sendCommand(camera: cam, opCode: CanonPTP.remoteReleaseOn, params: [3, 0])
                try? await Task.sleep(for: .milliseconds(120))
                let offResp = await sendCommand(camera: cam, opCode: CanonPTP.remoteReleaseOff, params: [3])
                ok = onResp.responseCode == 0x2001 || offResp.responseCode == 0x2001
            }
            try? await Task.sleep(for: .milliseconds(350))
            _ = await sendCommand(camera: cam, opCode: CanonPTP.getEvent)
            if isStreaming {
                _ = await setCanonPropUInt32(camera: cam, propCode: CanonPTP.propEVFOutputDevice, value: 3)
            }
            return ok
        } else if activeVendorID == NikonPTP.vendorID {
            let resp = await sendCommand(camera: cam, opCode: NikonPTP.initiateCaptureRecInMedia, params: [0xFFFF_FFFF, 0])
            if resp.responseCode == 0x2001 { return true }
            let fallback = await sendCommand(camera: cam, opCode: NikonPTP.initiateCapture, params: [0, 0])
            return fallback.responseCode == 0x2001
        }
        return false
    }

    // MARK: - Vendor EVF Handshakes

    private enum FramePollOutcome {
        case frame(CGImage)
        case busyRetry
        case fatal(String)
    }

    private func enableCameraEVF(camera: ICCameraDevice, vendorID: Int) async -> Bool {
        if vendorID == CanonPTP.vendorID {
            _ = await sendCommand(camera: camera, opCode: CanonPTP.setRemoteMode, params: [1])
            _ = await sendCommand(camera: camera, opCode: CanonPTP.setEventMode, params: [1])
            let evfModeResp = await setCanonPropUInt32(camera: camera, propCode: CanonPTP.propEVFMode, value: 1)
            try? await Task.sleep(for: .milliseconds(160))
            var outResp = await setCanonPropUInt32(camera: camera, propCode: CanonPTP.propEVFOutputDevice, value: 3)
            if outResp != 0x2001 {
                outResp = await setCanonPropUInt32(camera: camera, propCode: CanonPTP.propEVFOutputDevice, value: 2)
            }
            try? await Task.sleep(for: .milliseconds(160))
            _ = await sendCommand(camera: camera, opCode: CanonPTP.getEvent)
            return evfModeResp == 0x2001 || outResp == 0x2001
        } else if vendorID == NikonPTP.vendorID {
            let resp = await sendCommand(camera: camera, opCode: NikonPTP.startLiveView)
            try? await Task.sleep(for: .milliseconds(200))
            return resp.responseCode == 0x2001
        }
        return false
    }

    private func disableCameraEVF(camera: ICCameraDevice, vendorID: Int) async {
        guard camera.hasOpenSession else { return }
        if vendorID == CanonPTP.vendorID {
            _ = await setCanonPropUInt32(camera: camera, propCode: CanonPTP.propEVFOutputDevice, value: 0)
            _ = await setCanonPropUInt32(camera: camera, propCode: CanonPTP.propEVFMode, value: 0)
            _ = await sendCommand(camera: camera, opCode: CanonPTP.setRemoteMode, params: [0])
        } else if vendorID == NikonPTP.vendorID {
            _ = await sendCommand(camera: camera, opCode: NikonPTP.endLiveView)
        }
    }

    private func fetchSingleEVFFrame(camera: ICCameraDevice, vendorID: Int) async -> FramePollOutcome {
        let resp: PTPExchangeResult
        if vendorID == CanonPTP.vendorID {
            resp = await sendCommand(camera: camera, opCode: CanonPTP.getViewFinderData, params: [0x0020_0000])
        } else {
            resp = await sendCommand(camera: camera, opCode: NikonPTP.getLiveViewImage)
        }

        if let err = resp.errorMessage {
            logger.warning("PTP EVF error: \(err, privacy: .public)")
            return .fatal("Error PTP en Vista en Vivo: \(err)")
        }

        // 0x2001 = OK, 0x2019 = Device Busy, 0xA102 = Canon Not Ready / Mirror Moving
        if resp.responseCode == 0x2019 || resp.responseCode == 0xA102 || resp.inData.isEmpty {
            return .busyRetry
        }

        guard let jpegData = Self.extractEmbeddedJPEG(from: resp.inData),
              let src = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return .busyRetry
        }
        return .frame(cgImage)
    }

    private func setCanonPropUInt32(camera: ICCameraDevice, propCode: UInt32, value: UInt32) async -> UInt16 {
        var payload = Data(capacity: 12)
        Self.appendUInt32LE(12, to: &payload)
        Self.appendUInt32LE(propCode, to: &payload)
        Self.appendUInt32LE(value, to: &payload)
        let res = await sendCommand(camera: camera, opCode: CanonPTP.setDevicePropValueEx, outPayload: payload)
        return res.responseCode
    }

    // MARK: - Low-Level PTP Framing & Swift 6 Nonisolated Dispatch

    private struct PTPExchangeResult: Sendable {
        let inData: Data
        let responseCode: UInt16
        let errorMessage: String?
    }

    private func nextTransactionID() -> UInt32 {
        transactionCounter &+= 1
        return transactionCounter
    }

    private func sendCommand(
        camera: ICCameraDevice,
        opCode: UInt16,
        params: [UInt32] = [],
        outPayload: Data? = nil
    ) async -> PTPExchangeResult {
        let txID = nextTransactionID()
        let cmdContainer = Self.buildCommandContainer(opCode: opCode, transID: txID, params: params)
        let dataContainer = outPayload.map { Self.buildDataContainer(opCode: opCode, transID: txID, payload: $0) }

        return await withCheckedContinuation { continuation in
            Self.startNonisolatedPTPCommand(camera: camera, command: cmdContainer, outData: dataContainer) { inData, respData, errorText in
                let code = Self.parseResponseCode(from: respData)
                continuation.resume(returning: PTPExchangeResult(inData: inData, responseCode: code, errorMessage: errorText))
            }
        }
    }

    nonisolated private static func startNonisolatedPTPCommand(
        camera: ICCameraDevice,
        command: Data,
        outData: Data?,
        completion: @escaping @Sendable (Data, Data, String?) -> Void
    ) {
        camera.requestSendPTPCommand(command, outData: outData) { inData, responseContainer, error in
            completion(inData, responseContainer, error?.localizedDescription)
        }
    }

    nonisolated package static func buildCommandContainer(opCode: UInt16, transID: UInt32, params: [UInt32]) -> Data {
        var data = Data(capacity: 12 + params.count * 4)
        appendUInt32LE(UInt32(12 + params.count * 4), to: &data)
        appendUInt16LE(1, to: &data) // Command Block
        appendUInt16LE(opCode, to: &data)
        appendUInt32LE(transID, to: &data)
        for p in params {
            appendUInt32LE(p, to: &data)
        }
        return data
    }

    nonisolated package static func buildDataContainer(opCode: UInt16, transID: UInt32, payload: Data) -> Data {
        var data = Data(capacity: 12 + payload.count)
        appendUInt32LE(UInt32(12 + payload.count), to: &data)
        appendUInt16LE(2, to: &data) // Data Block
        appendUInt16LE(opCode, to: &data)
        appendUInt32LE(transID, to: &data)
        data.append(payload)
        return data
    }

    nonisolated package static func parseResponseCode(from resp: Data) -> UInt16 {
        guard resp.count >= 8 else { return 0 }
        let lo = UInt16(resp[resp.startIndex + 6])
        let hi = UInt16(resp[resp.startIndex + 7]) << 8
        return lo | hi
    }

    nonisolated package static func extractEmbeddedJPEG(from buffer: Data) -> Data? {
        guard buffer.count > 16 else { return nil }
        let bytes = [UInt8](buffer)
        var soiIndex: Int?
        for i in 0..<(bytes.count - 3) {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF {
                soiIndex = i
                break
            }
        }
        guard let start = soiIndex else { return nil }
        for j in stride(from: bytes.count - 2, through: start + 2, by: -1) {
            if bytes[j] == 0xFF && bytes[j + 1] == 0xD9 {
                return Data(bytes[start...(j + 1)])
            }
        }
        return nil
    }

    nonisolated private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    nonisolated private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
