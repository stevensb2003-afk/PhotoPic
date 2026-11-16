import Foundation
import os

/// Persists Vision AI & custom tags per session in `.photopic_tags.json`, writes standard
/// Adobe/Lightroom-compatible `.xmp` sidecars, and updates macOS Finder tags.
package enum PhotoTagStore {
    private static let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "PhotoTagStore")
    private static let storeFilename = ".photopic_tags.json"

    package static func loadAll(for session: PhotoSession) -> [String: PhotoVisionTags] {
        let storeURL = session.directoryURL.appendingPathComponent(storeFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: PhotoVisionTags].self, from: data)) ?? [:]
    }

    package static func save(
        tags: PhotoVisionTags,
        for item: PhotoItem,
        in session: PhotoSession,
        writeSidecarAndFinderTags: Bool = true
    ) {
        var map = loadAll(for: session)
        map[item.baseFilename] = tags
        persist(map: map, to: session.directoryURL.appendingPathComponent(storeFilename, isDirectory: false))

        if writeSidecarAndFinderTags {
            writeXMPSidecar(tags: tags, forImageAt: item.fileURL)
            applyFinderTags(tags.allTags, to: item.fileURL)
        }
    }

    package static func xmpSidecarURL(for imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension("xmp")
    }

    package static func relocateSidecarIfPresent(from oldImageURL: URL, to newImageURL: URL) {
        let oldXMP = xmpSidecarURL(for: oldImageURL)
        guard FileManager.default.fileExists(atPath: oldXMP.path) else { return }
        let newXMP = xmpSidecarURL(for: newImageURL)
        try? FileManager.default.removeItem(at: newXMP)
        try? FileManager.default.moveItem(at: oldXMP, to: newXMP)
    }

    package static func writeXMPSidecar(tags: PhotoVisionTags, forImageAt imageURL: URL) {
        let xmpURL = xmpSidecarURL(for: imageURL)
        let subjectItems = tags.allTags
            .map { "          <rdf:li>\(escapeXML($0))</rdf:li>" }
            .joined(separator: "\n")

        let xmpContent = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:dc="http://purl.org/dc/elements/1.1/"
                xmlns:photopic="https://github.com/stevensb2003-afk/PhotoPic/ns/1.0/">
              <photopic:PersonCount>\(tags.personCount)</photopic:PersonCount>
              <photopic:FaceCount>\(tags.faceCount)</photopic:FaceCount>
              <photopic:ClosedEyesWarning>\(tags.hasClosedEyesWarning ? "true" : "false")</photopic:ClosedEyesWarning>
              <dc:subject>
                <rdf:Bag>
        \(subjectItems)
                </rdf:Bag>
              </dc:subject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """

        do {
            try Data(xmpContent.utf8).write(to: xmpURL, options: .atomic)
        } catch {
            logger.warning("XMP sidecar write skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    package static func applyFinderTags(_ tags: [String], to fileURL: URL) {
        guard !tags.isEmpty, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? (fileURL as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    private static func persist(map: [String: PhotoVisionTags], to storeURL: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(map) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
