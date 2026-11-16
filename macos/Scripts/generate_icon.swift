import AppKit
import CoreGraphics
import Foundation

/// Draws the PhotoPic icon ("icono vacilón" combining Pictogrammers `camera-iris`,
/// viewfinder focus brackets, tilted Polaroid accent, and `creation` AI sparkle),
/// exporting `assets/logo.svg`, `macos/Resources/AppIcon.icns`, and `windows/assets/AppIcon.ico`.

let irisPath = "M13.73,15L9.83,21.76C10.53,21.91 11.25,22 12,22C14.4,22 16.6,21.15 18.32,19.75L14.66,13.4M2.46,15C3.38,17.92 5.61,20.26 8.45,21.34L12.12,15M8.54,12L4.64,5.25C3,7 2,9.39 2,12C2,12.68 2.07,13.35 2.2,14H9.69M21.8,10H14.31L14.6,10.5L19.36,18.75C21,16.97 22,14.6 22,12C22,11.31 21.93,10.64 21.8,10M21.54,9C20.62,6.07 18.39,3.74 15.55,2.66L11.88,9M9.4,10.5L14.17,2.24C13.47,2.09 12.75,2 12,2C9.6,2 7.4,2.84 5.68,4.25L9.34,10.6L9.4,10.5Z"
let sparklePath = "M19,1L17.74,3.75L15,5L17.74,6.26L19,9L20.25,6.26L23,5L20.25,3.75M9,4L6.5,9.5L1,12L6.5,14.5L9,20L11.5,14.5L17,12L11.5,9.5M19,15L17.74,17.74L15,19L17.74,20.25L19,23L20.25,20.25L23,19L20.25,17.74"

func buildMasterLogoSVG() -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
      <defs>
        <linearGradient id="bgGrad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#1D222B"/>
          <stop offset="100%" stop-color="#0B0C10"/>
        </linearGradient>
        <linearGradient id="irisGrad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#F8FAFC"/>
          <stop offset="100%" stop-color="#94A3B8"/>
        </linearGradient>
      </defs>
      <rect x="32" y="32" width="448" height="448" rx="104" fill="url(#bgGrad)" stroke="#334155" stroke-width="6"/>
      <g transform="translate(256 266) rotate(-7)">
        <rect x="-136" y="-128" width="272" height="256" rx="26" fill="#14171F" stroke="#38BDF8" stroke-opacity="0.55" stroke-width="5"/>
        <rect x="-112" y="-104" width="224" height="174" rx="14" fill="#090B0E"/>
      </g>
      <path d="M104 152 V114 A14 14 0 0 1 118 100 H156" fill="none" stroke="#22C55E" stroke-width="10" stroke-linecap="round"/>
      <path d="M408 360 V398 A14 14 0 0 1 394 412 H356" fill="none" stroke="#22C55E" stroke-width="10" stroke-linecap="round"/>
      <path d="M104 360 V398 A14 14 0 0 0 118 412 H156" fill="none" stroke="#F59E0B" stroke-width="10" stroke-linecap="round"/>
      <g transform="translate(154 144) scale(8.5)">
        <path fill="url(#irisGrad)" d="\(irisPath)"/>
      </g>
      <circle cx="256" cy="246" r="18" fill="#38BDF8"/>
      <circle cx="262" cy="240" r="6" fill="#FFFFFF" fill-opacity="0.85"/>
      <g transform="translate(314 72) scale(3.2)">
        <path fill="#FBBF24" d="\(sparklePath)"/>
      </g>
      <circle cx="422" cy="96" r="15" fill="#22C55E" stroke="#141820" stroke-width="5"/>
    </svg>
    """
}

func renderLogoPNG(svgData: Data, size: Int) throws -> Data {
    guard let svgImage = NSImage(data: svgData) else {
        throw NSError(domain: "PhotoPicIcon", code: 1)
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    guard let rep else { throw NSError(domain: "PhotoPicIcon", code: 2) }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    svgImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PhotoPicIcon", code: 3)
    }
    return png
}

func writeICO(pngEntries: [(size: Int, data: Data)], to url: URL) throws {
    var ico = Data()
    func appendLE16(_ v: UInt16) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { ico.append(contentsOf: $0) }
    }
    func appendLE32(_ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { ico.append(contentsOf: $0) }
    }

    appendLE16(0)
    appendLE16(1)
    appendLE16(UInt16(pngEntries.count))

    var offset = UInt32(6 + pngEntries.count * 16)
    for entry in pngEntries {
        let dimByte: UInt8 = entry.size >= 256 ? 0 : UInt8(entry.size)
        ico.append(dimByte)
        ico.append(dimByte)
        ico.append(0)
        ico.append(0)
        appendLE16(1)
        appendLE16(32)
        appendLE32(UInt32(entry.data.count))
        appendLE32(offset)
        offset += UInt32(entry.data.count)
    }
    for entry in pngEntries {
        ico.append(entry.data)
    }
    try ico.write(to: url, options: .atomic)
}

let svgString = buildMasterLogoSVG()
let svgData = Data(svgString.utf8)

let logoURL = URL(fileURLWithPath: "assets/logo.svg")
let icnsURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "macos/Resources/AppIcon.icns")
let icoURL = URL(fileURLWithPath: "windows/assets/AppIcon.ico")

try FileManager.default.createDirectory(at: logoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: icoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try svgData.write(to: logoURL, options: .atomic)

let iconsetDir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoPicIcon_\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetDir) }

let macSpecs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

var pngCache: [Int: Data] = [:]
for (filename, px) in macSpecs {
    let png: Data
    if let existing = pngCache[px] {
        png = existing
    } else {
        png = try renderLogoPNG(svgData: svgData, size: px)
        pngCache[px] = png
    }
    try png.write(to: iconsetDir.appendingPathComponent(filename), options: .atomic)
}

let icoSizes = [16, 32, 48, 64, 128, 256]
let icoEntries = try icoSizes.map { sz -> (Int, Data) in
    let data = try pngCache[sz] ?? renderLogoPNG(svgData: svgData, size: sz)
    return (sz, data)
}
try writeICO(pngEntries: icoEntries, to: icoURL)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    exit(1)
}
print("Generated assets/logo.svg, \(icnsURL.path), and \(icoURL.path)")
