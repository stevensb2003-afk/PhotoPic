import Foundation
import ImageIO

/// Reads fast header-only EXIF metadata without decoding pixel buffers or embedded thumbs.
package enum ExifMetadataReader {
    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    package static func read(from url: URL, fallbackCompanionURL: URL? = nil) -> PhotoExifMetadata {
        var primary = readSingleFile(from: url)
        if let fallbackCompanionURL, primary.iso == nil || primary.aperture == nil || primary.shutterSpeedSeconds == nil {
            let companion = readSingleFile(from: fallbackCompanionURL)
            primary = PhotoExifMetadata(
                cameraMake: primary.cameraMake ?? companion.cameraMake,
                cameraModel: primary.cameraModel ?? companion.cameraModel,
                lensModel: primary.lensModel ?? companion.lensModel,
                iso: primary.iso ?? companion.iso,
                aperture: primary.aperture ?? companion.aperture,
                shutterSpeedSeconds: primary.shutterSpeedSeconds ?? companion.shutterSpeedSeconds,
                focalLengthMM: primary.focalLengthMM ?? companion.focalLengthMM,
                pixelWidth: primary.pixelWidth ?? companion.pixelWidth,
                pixelHeight: primary.pixelHeight ?? companion.pixelHeight,
                captureDate: primary.captureDate ?? companion.captureDate
            )
        }
        return primary
    }

    private static func readSingleFile(from url: URL) -> PhotoExifMetadata {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [CFString: Any] else {
            return PhotoExifMetadata()
        }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any]

        let isoArray = exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber]
        let iso = isoArray?.first?.intValue

        let aperture = (exif?[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue
        let exposure = (exif?[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue
        let focalLength = (exif?[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue

        let pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue

        let make = (tiff?[kCGImagePropertyTIFFMake] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lens = (exif?[kCGImagePropertyExifLensModel] as? String ?? aux?[kCGImagePropertyExifAuxLensModel] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dateString = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        let captureDate = dateString.flatMap { exifDateFormatter.date(from: $0) }

        return PhotoExifMetadata(
            cameraMake: make,
            cameraModel: model,
            lensModel: lens,
            iso: iso,
            aperture: aperture,
            shutterSpeedSeconds: exposure,
            focalLengthMM: focalLength,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            captureDate: captureDate
        )
    }
}
