import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import os

/// Persists lossless 90° clockwise image rotations directly into photo files on disk
/// (TIFF-based RAWs `.CR2/.DNG/.NEF/.ARW/...`, Canon `.CR3` `CMT1`, and compressed
/// `.JPG/.HEIC/.PNG/.TIFF`) so macOS Finder, Quick Look, Preview, Lightroom, and PhotoPic
/// immediately display the rotated orientation.
package enum PhotoOrientationService {
    private static let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "PhotoOrientation")

    package enum OrientationError: LocalizedError, Sendable {
        case unreadableImage(String)
        case unsupportedWriteFormat(String)
        case writeFailed(String)

        package var errorDescription: String? {
            switch self {
            case .unreadableImage(let name):
                return "No se pudo leer la orientación de \(name)."
            case .unsupportedWriteFormat(let name):
                return "Este formato no permite guardar la orientación directamente en \(name)."
            case .writeFailed(let detail):
                return "No se pudo guardar la rotación en disco: \(detail)"
            }
        }
    }

    /// Standard EXIF Orientation (Tag `0x0112`) +90° clockwise state transition.
    package static func nextClockwiseOrientation(from current: UInt16) -> UInt16 {
        switch current {
        case 1: return 6
        case 6: return 3
        case 3: return 8
        case 8: return 1
        case 2: return 7
        case 7: return 4
        case 4: return 5
        case 5: return 2
        default: return 6
        }
    }

    /// Reads the current EXIF Orientation (`1...8`) without decoding pixels.
    package static func readOrientation(at url: URL) -> UInt16 {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [CFString: Any] else {
            return 1
        }
        if let raw = props[kCGImagePropertyOrientation] as? NSNumber {
            let val = raw.uint16Value
            if (1...8).contains(val) { return val }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = tiff[kCGImagePropertyTIFFOrientation] as? NSNumber {
            let val = raw.uint16Value
            if (1...8).contains(val) { return val }
        }
        return 1
    }

    /// Rotates `item.fileURL` (and its paired `.JPG` companion if present) by 90° clockwise on disk.
    @discardableResult
    package static func rotateClockwise90(item: PhotoItem) throws -> UInt16 {
        let current = readOrientation(at: item.fileURL)
        let target = nextClockwiseOrientation(from: current)

        try persistOrientation(target, to: item.fileURL)

        if let companion = item.pairedCompressedURL,
           FileManager.default.fileExists(atPath: companion.path) {
            do {
                try persistOrientation(target, to: companion)
            } catch {
                logger.warning("Paired JPG orientation sync skipped for \(companion.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        updateXMPOrientationIfPresent(forImageAt: item.fileURL, orientation: target)
        return target
    }

    package static func persistOrientation(_ orientation: UInt16, to url: URL) throws {
        let ext = url.pathExtension.lowercased()

        if ext == "cr3" {
            let patched = try patchCR3OrientationInPlace(at: url, orientation: orientation)
            if patched > 0 { return }
            throw OrientationError.unsupportedWriteFormat(url.lastPathComponent)
        }

        let isRaw = MediaFormatClassifier.classify(filename: url.lastPathComponent) == .raw
        if isRaw || ext == "tif" || ext == "tiff" {
            if let patched = try? patchTIFFOrientationInPlace(at: url, baseOffset: 0, orientation: orientation),
               patched > 0 {
                return
            }
            if isRaw {
                throw OrientationError.unsupportedWriteFormat(url.lastPathComponent)
            }
        }

        try rewriteCompressedOrientation(at: url, orientation: orientation)
    }

    // MARK: - Lossless In-Place TIFF IFD `0x0112` Patcher (CR2, DNG, NEF, ARW, ORF, RW2, PEF, SRW, TIFF)

    @discardableResult
    private static func patchTIFFOrientationInPlace(
        at url: URL,
        baseOffset: UInt64,
        orientation: UInt16
    ) throws -> Int {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard baseOffset + 8 <= fileSize else { return 0 }

        try handle.seek(toOffset: baseOffset)
        guard let header = try handle.read(upToCount: 8), header.count == 8 else { return 0 }

        let isLittleEndian: Bool
        if header[0] == 0x49 && header[1] == 0x49 { // "II"
            isLittleEndian = true
        } else if header[0] == 0x4D && header[1] == 0x4D { // "MM"
            isLittleEndian = false
        } else {
            return 0
        }

        let magic = readUInt16(header, at: 2, littleEndian: isLittleEndian)
        // Standard TIFF (42), Olympus ORF (0x4F52 / 0x5352), Panasonic RW2 (0x0055)
        guard magic == 42 || magic == 0x4F52 || magic == 0x5352 || magic == 0x0055 else {
            return 0
        }

        let firstIFDOffset = UInt64(readUInt32(header, at: 4, littleEndian: isLittleEndian))
        var pendingIFDs: [UInt64] = [firstIFDOffset]
        var visitedIFDs: Set<UInt64> = []
        var patchedCount = 0
        let maxIFDsToInspect = 12

        while let relIFDOffset = pendingIFDs.first, visitedIFDs.count < maxIFDsToInspect {
            pendingIFDs.removeFirst()
            guard relIFDOffset >= 8, visitedIFDs.insert(relIFDOffset).inserted else { continue }
            let absIFD = baseOffset + relIFDOffset
            guard absIFD + 2 <= fileSize else { continue }

            try handle.seek(toOffset: absIFD)
            guard let countData = try handle.read(upToCount: 2), countData.count == 2 else { continue }
            let entryCount = Int(readUInt16(countData, at: 0, littleEndian: isLittleEndian))
            guard entryCount > 0, entryCount < 512 else { continue }

            let tableByteCount = entryCount * 12 + 4
            guard absIFD + 2 + UInt64(tableByteCount) <= fileSize else { continue }
            guard let tableData = try handle.read(upToCount: tableByteCount), tableData.count == tableByteCount else {
                continue
            }

            for i in 0..<entryCount {
                let entryOffset = i * 12
                let tag = readUInt16(tableData, at: entryOffset, littleEndian: isLittleEndian)
                let type = readUInt16(tableData, at: entryOffset + 2, littleEndian: isLittleEndian)
                let count = readUInt32(tableData, at: entryOffset + 4, littleEndian: isLittleEndian)

                if tag == 0x0112 && type == 3 && count == 1 {
                    let valueFileOffset = absIFD + 2 + UInt64(entryOffset) + 8
                    let encoded = encodeUInt16(orientation, littleEndian: isLittleEndian)
                    try handle.seek(toOffset: valueFileOffset)
                    try handle.write(contentsOf: encoded)
                    patchedCount += 1
                } else if tag == 0x014A && (type == 4 || type == 13) && count >= 1 && count <= 4 {
                    // SubIFDs pointer(s)
                    if count == 1 {
                        let subOffset = UInt64(readUInt32(tableData, at: entryOffset + 8, littleEndian: isLittleEndian))
                        pendingIFDs.append(subOffset)
                    } else {
                        let arrayRelOffset = UInt64(readUInt32(tableData, at: entryOffset + 8, littleEndian: isLittleEndian))
                        let arrayAbs = baseOffset + arrayRelOffset
                        if arrayAbs + UInt64(count * 4) <= fileSize {
                            try handle.seek(toOffset: arrayAbs)
                            if let arrData = try handle.read(upToCount: Int(count * 4)), arrData.count == Int(count * 4) {
                                for s in 0..<Int(count) {
                                    let subOff = UInt64(readUInt32(arrData, at: s * 4, littleEndian: isLittleEndian))
                                    pendingIFDs.append(subOff)
                                }
                            }
                        }
                    }
                }
            }

            let nextIFD = UInt64(readUInt32(tableData, at: entryCount * 12, littleEndian: isLittleEndian))
            if nextIFD > 0 {
                pendingIFDs.append(nextIFD)
            }
        }

        if patchedCount > 0 {
            try handle.synchronize()
        }
        return patchedCount
    }

    // MARK: - Lossless Canon CR3 `CMT1` Box Patcher

    /// Locates Canon's `CMT1` TIFF metadata box inside `moov/uuid` in a `.CR3` ISO BMFF file
    /// and updates its `0x0112` Orientation tag in place.
    @discardableResult
    private static func patchCR3OrientationInPlace(at url: URL, orientation: UInt16) throws -> Int {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard let moov = findISOBMFFBox(named: "moov", in: handle, range: 0..<fileSize) else {
            return 0
        }

        // Canon metadata UUID: 85c0b687-820f-11e0-8111-f4ce462b6a48
        let canonMetaUUID: [UInt8] = [
            0x85, 0xC0, 0xB6, 0x87, 0x82, 0x0F, 0x11, 0xE0,
            0x81, 0x11, 0xF4, 0xCE, 0x46, 0x2B, 0x6A, 0x48
        ]

        var cursor = moov.payloadStart
        while cursor + 8 <= moov.end {
            guard let box = readISOBMFFBoxHeader(in: handle, at: cursor, limit: moov.end) else { break }
            if box.type == "uuid", box.payloadStart + 16 <= box.end {
                try handle.seek(toOffset: box.payloadStart)
                if let uuidBytes = try handle.read(upToCount: 16), Array(uuidBytes) == canonMetaUUID {
                    if let cmt1 = findISOBMFFBox(named: "CMT1", in: handle, range: (box.payloadStart + 16)..<box.end) {
                        try handle.close()
                        return try patchTIFFOrientationInPlace(at: url, baseOffset: cmt1.payloadStart, orientation: orientation)
                    }
                }
            }
            cursor = box.end
        }
        return 0
    }

    private struct ISOBMFFBox {
        let type: String
        let payloadStart: UInt64
        let end: UInt64
    }

    private static func findISOBMFFBox(
        named target: String,
        in handle: FileHandle,
        range: Range<UInt64>
    ) -> ISOBMFFBox? {
        var cursor = range.lowerBound
        while cursor + 8 <= range.upperBound {
            guard let box = readISOBMFFBoxHeader(in: handle, at: cursor, limit: range.upperBound) else {
                return nil
            }
            if box.type == target {
                return box
            }
            cursor = box.end
        }
        return nil
    }

    private static func readISOBMFFBoxHeader(
        in handle: FileHandle,
        at offset: UInt64,
        limit: UInt64
    ) -> ISOBMFFBox? {
        guard offset + 8 <= limit else { return nil }
        do {
            try handle.seek(toOffset: offset)
            guard let header = try handle.read(upToCount: 8), header.count == 8 else { return nil }
            let size32 = UInt64(readUInt32(header, at: 0, littleEndian: false))
            let type = String(bytes: header[4..<8], encoding: .ascii) ?? ""
            var boxSize = size32
            var payloadStart = offset + 8

            if size32 == 1 {
                guard offset + 16 <= limit else { return nil }
                guard let extSize = try handle.read(upToCount: 8), extSize.count == 8 else { return nil }
                boxSize = readUInt64BigEndian(extSize)
                payloadStart = offset + 16
            } else if size32 == 0 {
                boxSize = limit - offset
            }

            guard boxSize >= (payloadStart - offset), offset + boxSize <= limit else { return nil }
            return ISOBMFFBox(type: type, payloadStart: payloadStart, end: offset + boxSize)
        } catch {
            return nil
        }
    }

    // MARK: - Compressed Image Orientation Rewrite (Lossless Copy + Fallback)

    private static func rewriteCompressedOrientation(at url: URL, orientation: UInt16) throws {
        let fm = FileManager.default
        let originalAttributes = try? fm.attributesOfItem(atPath: url.path)

        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              let uti = CGImageSourceGetType(source) else {
            throw OrientationError.unreadableImage(url.lastPathComponent)
        }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".photopic_rot_\(UUID().uuidString).\(url.pathExtension)")
        defer { try? fm.removeItem(at: tempURL) }

        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
            throw OrientationError.writeFailed("No se pudo crear el destino de imagen")
        }

        // Attempt 1: lossless metadata-only rewrite preserving original compressed JPEG/HEIC/TIFF data.
        var copyError: Unmanaged<CFError>?
        let losslessOptions: [CFString: Any] = [
            kCGImageDestinationOrientation: Int(orientation),
            kCGImagePropertyOrientation: Int(orientation)
        ]
        var succeeded = CGImageDestinationCopyImageSource(
            destination,
            source,
            losslessOptions as CFDictionary,
            &copyError
        )

        // Attempt 2: fallback for formats like PNG/WebP where pixel rotation is needed.
        if !succeeded {
            guard let fallbackDest = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil),
                  let ciImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                throw OrientationError.writeFailed(
                    copyError?.takeRetainedValue().localizedDescription ?? "Formato no compatible"
                )
            }
            let rotated = ciImage.oriented(.right)
            let context = CIContext()
            guard let cgImage = context.createCGImage(rotated, from: rotated.extent) else {
                throw OrientationError.writeFailed("No se pudo rasterizar la imagen rotada")
            }
            let props: [CFString: Any] = [kCGImagePropertyOrientation: 1]
            CGImageDestinationAddImage(fallbackDest, cgImage, props as CFDictionary)
            succeeded = CGImageDestinationFinalize(fallbackDest)
        }

        guard succeeded else {
            throw OrientationError.writeFailed("No se pudo finalizar el archivo rotado")
        }

        _ = try fm.replaceItemAt(url, withItemAt: tempURL)

        if let attrs = originalAttributes {
            var preserved: [FileAttributeKey: Any] = [:]
            if let created = attrs[.creationDate] { preserved[.creationDate] = created }
            if let modified = attrs[.modificationDate] { preserved[.modificationDate] = modified }
            if !preserved.isEmpty {
                try? fm.setAttributes(preserved, ofItemAtPath: url.path)
            }
        }
    }

    // MARK: - XMP Sidecar Orientation Sync

    private static func updateXMPOrientationIfPresent(forImageAt imageURL: URL, orientation: UInt16) {
        let xmpURL = PhotoTagStore.xmpSidecarURL(for: imageURL)
        guard FileManager.default.fileExists(atPath: xmpURL.path),
              var content = try? String(contentsOf: xmpURL, encoding: .utf8) else {
            return
        }

        if let range = content.range(of: #"<tiff:Orientation>\d+</tiff:Orientation>"#, options: .regularExpression) {
            content.replaceSubrange(range, with: "<tiff:Orientation>\(orientation)</tiff:Orientation>")
        } else if let descRange = content.range(of: "xmlns:dc=\"http://purl.org/dc/elements/1.1/\"") {
            content.replaceSubrange(
                descRange,
                with: "xmlns:dc=\"http://purl.org/dc/elements/1.1/\"\n        xmlns:tiff=\"http://ns.adobe.com/tiff/1.0/\""
            )
            if let closeRange = content.range(of: "</rdf:Description>") {
                content.insert(
                    contentsOf: "      <tiff:Orientation>\(orientation)</tiff:Orientation>\n    ",
                    at: closeRange.lowerBound
                )
            }
        }
        try? Data(content.utf8).write(to: xmpURL, options: .atomic)
    }

    // MARK: - Endian Binary Helpers

    private static func readUInt16(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt16 {
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        return littleEndian ? (b0 | (b1 << 8)) : ((b0 << 8) | b1)
    }

    private static func readUInt32(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt32 {
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        return littleEndian
            ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
            : ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    }

    private static func readUInt64BigEndian(_ data: Data) -> UInt64 {
        var result: UInt64 = 0
        for i in 0..<8 {
            result = (result << 8) | UInt64(data[data.startIndex + i])
        }
        return result
    }

    private static func encodeUInt16(_ value: UInt16, littleEndian: Bool) -> Data {
        let lo = UInt8(value & 0xFF)
        let hi = UInt8((value >> 8) & 0xFF)
        return littleEndian ? Data([lo, hi]) : Data([hi, lo])
    }
}
