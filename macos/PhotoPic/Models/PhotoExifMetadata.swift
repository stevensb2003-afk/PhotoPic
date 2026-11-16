import Foundation

/// Compact EXIF telemetry extracted from RAW or compressed photo headers.
package struct PhotoExifMetadata: Sendable, Equatable, Hashable, Codable {
    package var cameraMake: String?
    package var cameraModel: String?
    package var lensModel: String?
    package var iso: Int?
    package var aperture: Double?
    package var shutterSpeedSeconds: Double?
    package var focalLengthMM: Double?
    package var pixelWidth: Int?
    package var pixelHeight: Int?
    package var captureDate: Date?

    package init(
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        iso: Int? = nil,
        aperture: Double? = nil,
        shutterSpeedSeconds: Double? = nil,
        focalLengthMM: Double? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        captureDate: Date? = nil
    ) {
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.iso = iso
        self.aperture = aperture
        self.shutterSpeedSeconds = shutterSpeedSeconds
        self.focalLengthMM = focalLengthMM
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.captureDate = captureDate
    }

    package var formattedISO: String? {
        iso.map { "ISO \($0)" }
    }

    package var formattedAperture: String? {
        guard let aperture, aperture > 0 else { return nil }
        if aperture.rounded() == aperture {
            return String(format: "f/%.0f", aperture)
        }
        return String(format: "f/%.1f", aperture)
    }

    package var formattedShutter: String? {
        guard let seconds = shutterSpeedSeconds, seconds > 0 else { return nil }
        if seconds >= 1.0 {
            return seconds.rounded() == seconds
                ? String(format: "%.0fs", seconds)
                : String(format: "%.1fs", seconds)
        }
        let denominator = max(1, Int((1.0 / seconds).rounded()))
        return "1/\(denominator)s"
    }

    package var formattedFocalLength: String? {
        guard let focalLengthMM, focalLengthMM > 0 else { return nil }
        return "\(Int(focalLengthMM.rounded()))mm"
    }

    package var formattedDimensions: String? {
        guard let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 else { return nil }
        return "\(w) × \(h)"
    }

    /// Concise single-line EXIF telemetry string for the studio HUD.
    package var compactHudSummary: String {
        let parts = [
            formattedISO,
            formattedAperture,
            formattedShutter,
            formattedFocalLength
        ].compactMap { $0 }
        return parts.isEmpty ? "Sin metadatos EXIF" : parts.joined(separator: " · ")
    }
}
