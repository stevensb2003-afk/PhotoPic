import CoreGraphics
import CoreImage
import Foundation
import Metal
import os

/// Rendered image payload produced from pure sensor RAW or fallback compressed data.
package struct RenderedPhotoPayload: Sendable {
    package let cgImage: CGImage
    package let nativeSize: CGSize
    package let isFullSensorResolution: Bool
}

/// GPU-accelerated (Metal) RAW developer built strictly on `CIRAWFilter` + `CIContext`.
/// Never reads embedded JPG previews when a RAW master is present.
package actor RawImageRenderer {
    private let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "RawImageRenderer")
    private let ciContext: CIContext
    private let viewportCache = NSCache<NSString, CGImage>()
    private var fullSensorCache: [String: CGImage] = [:]
    private var fullSensorOrder: [String] = []
    private let maxFullSensorCached = 2

    package init() {
        let colorSpaceP3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? colorSpaceP3

        let contextOptions: [CIContextOption: Any] = [
            .workingColorSpace: linearP3,
            .outputColorSpace: colorSpaceP3,
            .cacheIntermediates: false,
            .useSoftwareRenderer: false
        ]

        if let mtlDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: mtlDevice, options: contextOptions)
        } else {
            self.ciContext = CIContext(options: contextOptions)
        }
        self.viewportCache.totalCostLimit = 384 * 1024 * 1024
    }

    /// Renders a GPU-developed image sized cleanly to the viewport (never using embedded JPG thumbs for RAW).
    package func renderViewportImage(
        for item: PhotoItem,
        maxDimension: CGFloat = 2400
    ) async -> RenderedPhotoPayload? {
        guard !Task.isCancelled else { return nil }
        let cacheKey = Self.cacheKey(for: item.fileURL, suffix: "vp:\(Int(maxDimension))")

        if let cached = viewportCache.object(forKey: cacheKey as NSString) {
            return RenderedPhotoPayload(
                cgImage: cached,
                nativeSize: CGSize(width: cached.width, height: cached.height),
                isFullSensorResolution: false
            )
        }

        let targetURL = item.fileURL
        let formatKind = item.formatKind

        if formatKind == .raw {
            return decodeRaw(url: targetURL, scaleToMaxDimension: maxDimension, cacheKey: cacheKey)
        } else {
            return decodeCompressed(url: targetURL, scaleToMaxDimension: maxDimension, cacheKey: cacheKey)
        }
    }

    /// Renders unscaled 1:1 pure sensor pixels (`scaleFactor = 1.0`) for critical eye/detail focus checks.
    package func renderFullSensorImage(for item: PhotoItem) async -> RenderedPhotoPayload? {
        guard !Task.isCancelled else { return nil }
        let key = Self.cacheKey(for: item.fileURL, suffix: "full")

        if let cached = fullSensorCache[key] {
            touchFullSensorKey(key)
            return RenderedPhotoPayload(
                cgImage: cached,
                nativeSize: CGSize(width: cached.width, height: cached.height),
                isFullSensorResolution: true
            )
        }

        let payload: RenderedPhotoPayload?
        if item.formatKind == .raw {
            payload = decodeRaw(url: item.fileURL, scaleToMaxDimension: nil, cacheKey: nil)
        } else {
            payload = decodeCompressed(url: item.fileURL, scaleToMaxDimension: nil, cacheKey: nil)
        }

        if let payload {
            storeFullSensorImage(payload.cgImage, forKey: key)
        }
        return payload
    }

    /// Background prefetching for upcoming photos in the queue.
    package func prefetch(items: [PhotoItem], maxDimension: CGFloat = 2400) async {
        for item in items.prefix(3) {
            guard !Task.isCancelled else { return }
            _ = await renderViewportImage(for: item, maxDimension: maxDimension)
        }
    }

    package func evictCache(for url: URL) {
        let vpPrefix = Self.cacheKey(for: url, suffix: "vp:2400")
        viewportCache.removeObject(forKey: vpPrefix as NSString)
        let fullKey = Self.cacheKey(for: url, suffix: "full")
        fullSensorCache.removeValue(forKey: fullKey)
        fullSensorOrder.removeAll { $0 == fullKey }
    }

    // MARK: - Core Image Metal Decoding

    private func decodeRaw(
        url: URL,
        scaleToMaxDimension: CGFloat?,
        cacheKey: String?
    ) -> RenderedPhotoPayload? {
        guard let rawFilter = CIRAWFilter(imageURL: url) else {
            logger.error("CIRAWFilter failed to open RAW file: \(url.lastPathComponent, privacy: .public)")
            return nil
        }

        rawFilter.isDraftModeEnabled = false
        rawFilter.isGamutMappingEnabled = true
        if rawFilter.isLensCorrectionSupported {
            rawFilter.isLensCorrectionEnabled = true
        }

        let nativeSize = rawFilter.nativeSize
        let longestSide = max(nativeSize.width, nativeSize.height)

        if let maxDim = scaleToMaxDimension, longestSide > maxDim, longestSide > 0 {
            let computedScale = Float(maxDim / longestSide)
            rawFilter.scaleFactor = max(0.08, min(1.0, computedScale))
        } else {
            rawFilter.scaleFactor = 1.0
        }

        guard let outputImage = rawFilter.outputImage else {
            logger.error("CIRAWFilter produced nil outputImage for: \(url.lastPathComponent, privacy: .public)")
            return nil
        }

        let extent = outputImage.extent
        guard !extent.isEmpty, let cgImage = ciContext.createCGImage(outputImage, from: extent) else {
            return nil
        }

        if let cacheKey {
            let cost = cgImage.bytesPerRow * cgImage.height
            viewportCache.setObject(cgImage, forKey: cacheKey as NSString, cost: cost)
        }

        return RenderedPhotoPayload(
            cgImage: cgImage,
            nativeSize: nativeSize.width > 0 ? nativeSize : CGSize(width: cgImage.width, height: cgImage.height),
            isFullSensorResolution: scaleToMaxDimension == nil
        )
    }

    private func decodeCompressed(
        url: URL,
        scaleToMaxDimension: CGFloat?,
        cacheKey: String?
    ) -> RenderedPhotoPayload? {
        guard var image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            return nil
        }

        let nativeExtent = image.extent
        let nativeSize = nativeExtent.size
        let longestSide = max(nativeSize.width, nativeSize.height)

        if let maxDim = scaleToMaxDimension, longestSide > maxDim, longestSide > 0 {
            let scale = maxDim / longestSide
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let extent = image.extent
        guard !extent.isEmpty, let cgImage = ciContext.createCGImage(image, from: extent) else {
            return nil
        }

        if let cacheKey {
            let cost = cgImage.bytesPerRow * cgImage.height
            viewportCache.setObject(cgImage, forKey: cacheKey as NSString, cost: cost)
        }

        return RenderedPhotoPayload(
            cgImage: cgImage,
            nativeSize: nativeSize,
            isFullSensorResolution: scaleToMaxDimension == nil
        )
    }

    private func storeFullSensorImage(_ image: CGImage, forKey key: String) {
        fullSensorCache[key] = image
        touchFullSensorKey(key)
        while fullSensorOrder.count > maxFullSensorCached {
            let evicted = fullSensorOrder.removeFirst()
            fullSensorCache.removeValue(forKey: evicted)
        }
    }

    private func touchFullSensorKey(_ key: String) {
        fullSensorOrder.removeAll { $0 == key }
        fullSensorOrder.append(key)
    }

    private static func cacheKey(for url: URL, suffix: String) -> String {
        "\(url.standardizedFileURL.path)|\(suffix)"
    }
}
