import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generates real synthetic 16-bit LinearRaw SubIFD `.DNG` files (with a tiny 16x12 IFD0
/// thumbnail so tests mathematically prove `CIRAWFilter` decodes the full sensor) and EXIF `.JPG` files.
package enum SyntheticDNGGenerator {
    package static func writeSyntheticDNG(
        to url: URL,
        width: Int = 640,
        height: Int = 480,
        cameraModel: String = "Canon EOS 70D",
        seedOffset: Int = 0
    ) throws {
        let thumbW = 16
        let thumbH = 12
        var thumbBytes = Data(capacity: thumbW * thumbH * 3)
        for _ in 0..<(thumbW * thumbH) {
            thumbBytes.append(contentsOf: [38, 38, 42])
        }

        // Full 16-bit RGB LinearRaw sensor with high-contrast resolution test chart & gradient
        var sensorPixels = Data(capacity: width * height * 6)
        for y in 0..<height {
            for x in 0..<width {
                let grid = ((x + seedOffset * 13) % 32 == 0) || (y % 32 == 0)
                let centerDist = hypot(Double(x - width / 2), Double(y - height / 2))
                let targetRing = centerDist > 75 && centerDist < 85

                let r16: UInt16
                let g16: UInt16
                let b16: UInt16

                if targetRing {
                    r16 = 56000; g16 = 46000; b16 = 22000
                } else if grid {
                    r16 = 12000; g16 = 12000; b16 = 13500
                } else {
                    let fx = Double(x) / Double(max(1, width - 1))
                    let fy = Double(y) / Double(max(1, height - 1))
                    r16 = UInt16(18000 + fx * 32000)
                    g16 = UInt16(20000 + fy * 28000)
                    b16 = UInt16(26000 + (1.0 - fx) * 18000)
                }

                var rLE = r16.littleEndian
                var gLE = g16.littleEndian
                var bLE = b16.littleEndian
                withUnsafeBytes(of: &rLE) { sensorPixels.append(contentsOf: $0) }
                withUnsafeBytes(of: &gLE) { sensorPixels.append(contentsOf: $0) }
                withUnsafeBytes(of: &bLE) { sensorPixels.append(contentsOf: $0) }
            }
        }

        var extra = Data()
        func appendExtra(_ bytes: Data) -> UInt32 {
            if extra.count % 2 == 1 { extra.append(0) }
            let offset = UInt32(extra.count)
            extra.append(bytes)
            return offset
        }

        let bps8Off = appendExtra(packUInt16([8, 8, 8]))
        let bps16Off = appendExtra(packUInt16([16, 16, 16]))
        let wlOff = appendExtra(packUInt32([65535, 65535, 65535]))
        let blOff = appendExtra(packUInt32([0, 0, 0]))
        let makeBytes = Data("Canon\0".utf8)
        let makeOff = appendExtra(makeBytes)
        let modelBytes = Data((cameraModel + "\0").utf8)
        let modelOff = appendExtra(modelBytes)
        let cmOff = appendExtra(packInt32([
            6722, 10000, -635, 10000, -963, 10000,
            -4287, 10000, 12460, 10000, 2028, 10000,
            -908, 10000, 2162, 10000, 5668, 10000
        ]))
        let asnOff = appendExtra(packUInt32([10000, 10000, 10000, 10000, 10000, 10000]))
        let thumbOff = appendExtra(thumbBytes)
        let pixOff = appendExtra(sensorPixels)

        let ifd0Count = 21
        let subifdCount = 14
        let ifd0Base: UInt32 = 8
        let subifdBase: UInt32 = ifd0Base + 2 + UInt32(ifd0Count * 12) + 4
        let extraBase: UInt32 = subifdBase + 2 + UInt32(subifdCount * 12) + 4

        let ifd0Entries: [(UInt16, UInt16, UInt32, Data)] = [
            (254, 4, 1, packUInt32([1])),
            (256, 4, 1, packUInt32([UInt32(thumbW)])),
            (257, 4, 1, packUInt32([UInt32(thumbH)])),
            (258, 3, 3, packUInt32([extraBase + bps8Off])),
            (259, 3, 1, packUInt16([1, 0])),
            (262, 3, 1, packUInt16([2, 0])),
            (271, 2, UInt32(makeBytes.count), packUInt32([extraBase + makeOff])),
            (272, 2, UInt32(modelBytes.count), packUInt32([extraBase + modelOff])),
            (273, 4, 1, packUInt32([extraBase + thumbOff])),
            (274, 3, 1, packUInt16([1, 0])),
            (277, 3, 1, packUInt16([3, 0])),
            (278, 4, 1, packUInt32([UInt32(thumbH)])),
            (279, 4, 1, packUInt32([UInt32(thumbBytes.count)])),
            (284, 3, 1, packUInt16([1, 0])),
            (330, 4, 1, packUInt32([subifdBase])),
            (50706, 1, 4, Data([1, 4, 0, 0])),
            (50707, 1, 4, Data([1, 1, 0, 0])),
            (50708, 2, UInt32(modelBytes.count), packUInt32([extraBase + modelOff])),
            (50721, 10, 9, packUInt32([extraBase + cmOff])),
            (50728, 5, 3, packUInt32([extraBase + asnOff])),
            (50778, 3, 1, packUInt16([21, 0]))
        ]

        let subifdEntries: [(UInt16, UInt16, UInt32, Data)] = [
            (254, 4, 1, packUInt32([0])),
            (256, 4, 1, packUInt32([UInt32(width)])),
            (257, 4, 1, packUInt32([UInt32(height)])),
            (258, 3, 3, packUInt32([extraBase + bps16Off])),
            (259, 3, 1, packUInt16([1, 0])),
            (262, 3, 1, packUInt16([34892, 0])),
            (273, 4, 1, packUInt32([extraBase + pixOff])),
            (277, 3, 1, packUInt16([3, 0])),
            (278, 4, 1, packUInt32([UInt32(height)])),
            (279, 4, 1, packUInt32([UInt32(sensorPixels.count)])),
            (284, 3, 1, packUInt16([1, 0])),
            (50714, 4, 3, packUInt32([extraBase + blOff])),
            (50717, 4, 3, packUInt32([extraBase + wlOff])),
            (50718, 5, 2, packUInt32([extraBase + asnOff]))
        ]

        var out = Data()
        out.append(contentsOf: [0x49, 0x49])
        out.append(packUInt16([42]))
        out.append(packUInt32([ifd0Base]))
        out.append(packUInt16([UInt16(ifd0Entries.count)]))
        for (tag, typ, cnt, val) in ifd0Entries {
            out.append(packUInt16([tag, typ]))
            out.append(packUInt32([cnt]))
            out.append(val)
        }
        out.append(packUInt32([0]))
        out.append(packUInt16([UInt16(subifdEntries.count)]))
        for (tag, typ, cnt, val) in subifdEntries {
            out.append(packUInt16([tag, typ]))
            out.append(packUInt32([cnt]))
            out.append(val)
        }
        out.append(packUInt32([0]))
        out.append(extra)

        try out.write(to: url, options: .atomic)
    }

    package static func writeSyntheticJPEGWithExif(
        to url: URL,
        width: Int = 320,
        height: Int = 240,
        iso: Int = 400,
        aperture: Double = 2.8,
        exposureSeconds: Double = 1.0 / 250.0,
        focalLength: Double = 50.0,
        cameraModel: String = "Canon EOS 70D"
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "SyntheticGen", code: 1)
        }

        ctx.setFillColor(CGColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.88, green: 0.65, blue: 0.32, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))

        guard let cgImage = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "SyntheticGen", code: 2)
        }

        let exifDict: [CFString: Any] = [
            kCGImagePropertyExifISOSpeedRatings: [iso],
            kCGImagePropertyExifFNumber: aperture,
            kCGImagePropertyExifExposureTime: exposureSeconds,
            kCGImagePropertyExifFocalLength: focalLength,
            kCGImagePropertyExifDateTimeOriginal: "2026:11:16 11:30:00"
        ]
        let tiffDict: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "Canon",
            kCGImagePropertyTIFFModel: cameraModel
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exifDict,
            kCGImagePropertyTIFFDictionary: tiffDict
        ]

        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "SyntheticGen", code: 3)
        }
    }

    private static func packUInt16(_ values: [UInt16]) -> Data {
        var data = Data(capacity: values.count * 2)
        for v in values {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func packUInt32(_ values: [UInt32]) -> Data {
        var data = Data(capacity: values.count * 4)
        for v in values {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func packInt32(_ values: [Int32]) -> Data {
        var data = Data(capacity: values.count * 4)
        for v in values {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}
