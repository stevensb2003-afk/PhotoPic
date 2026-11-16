import Foundation

/// Distinguishes sensor RAW masters from compressed camera/phone formats.
package enum MediaFormatKind: String, Sendable, Equatable, Hashable, Codable {
    case raw
    case compressed
}

/// Supported image formats across DSLR, Mirrorless, Medium Format, Android, and iPhone devices.
package enum MediaFormatClassifier {
    package static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "crw",
        "nef", "nrw",
        "arw", "srf", "sr2",
        "raf",
        "orf", "ori",
        "rw2", "raw",
        "pef", "srw",
        "3fr", "fff", "iiq", "rwl", "erf", "mos", "mrw", "dcr", "kdc"
    ]

    package static let compressedExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "hif", "avif", "jxl", "webp", "png", "tif", "tiff"
    ]

    package static func classify(filename: String) -> MediaFormatKind? {
        let ext = (filename as NSString).pathExtension.lowercased()
        if rawExtensions.contains(ext) {
            return .raw
        }
        if compressedExtensions.contains(ext) {
            return .compressed
        }
        return nil
    }

    package static func isSupportedImage(url: URL) -> Bool {
        classify(filename: url.lastPathComponent) != nil
    }

    package static func baseFilename(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.lowercased()
    }
}

/// Represents a physical image file tracked in `RAW/`, `Para_Edicion/`, or `Archivadas/`.
package struct PhotoItem: Identifiable, Sendable, Equatable, Hashable {
    package let id: String
    package var fileURL: URL
    package var pairedCompressedURL: URL?
    package var filename: String
    package var formatExtension: String
    package var formatKind: MediaFormatKind
    package var fileSizeBytes: Int64
    package var capturedAt: Date
    package var sourceDeviceAlias: String?
    package var sourceCategory: DeviceCategory?
    package var exif: PhotoExifMetadata
    package var visionTags: PhotoVisionTags?

    package init(
        fileURL: URL,
        pairedCompressedURL: URL? = nil,
        fileSizeBytes: Int64 = 0,
        capturedAt: Date = Date(),
        sourceDeviceAlias: String? = nil,
        sourceCategory: DeviceCategory? = nil,
        exif: PhotoExifMetadata = PhotoExifMetadata(),
        visionTags: PhotoVisionTags? = nil
    ) {
        self.id = fileURL.lastPathComponent.lowercased()
        self.fileURL = fileURL
        self.pairedCompressedURL = pairedCompressedURL
        self.filename = fileURL.lastPathComponent
        self.formatExtension = fileURL.pathExtension.uppercased()
        self.formatKind = MediaFormatClassifier.classify(filename: fileURL.lastPathComponent) ?? .compressed
        self.fileSizeBytes = fileSizeBytes
        self.capturedAt = capturedAt
        self.sourceDeviceAlias = sourceDeviceAlias
        self.sourceCategory = sourceCategory
        self.exif = exif
        self.visionTags = visionTags
    }

    package var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    package var baseFilename: String {
        MediaFormatClassifier.baseFilename(for: fileURL)
    }
}
