import Foundation
import os

/// Local atomic JSON store managing remembered USB cameras and smartphones.
@MainActor
package final class KnownDevicesStore {
    private let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "KnownDevicesStore")
    private let fileURL: URL
    package private(set) var devices: [KnownDevice] = []

    package init(storageURL: URL? = nil) {
        if let storageURL {
            self.fileURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            let dir = appSupport.appendingPathComponent("PhotoPic", isDirectory: true)
            self.fileURL = dir.appendingPathComponent("known_devices.json")
        }
        load()
    }

    package func device(for fingerprint: String) -> KnownDevice? {
        devices.first { $0.id == fingerprint }
    }

    package func saveOrUpdate(_ device: KnownDevice) {
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = device
        } else {
            devices.insert(device, at: 0)
        }
        persist()
    }

    package func updateAlias(fingerprint: String, alias: String) {
        guard let idx = devices.firstIndex(where: { $0.id == fingerprint }) else { return }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        devices[idx].alias = trimmed.isEmpty ? devices[idx].displayName : trimmed
        persist()
    }

    package func setAutoConnect(fingerprint: String, enabled: Bool) {
        guard let idx = devices.firstIndex(where: { $0.id == fingerprint }) else { return }
        devices[idx].autoConnectOnPlug = enabled
        persist()
    }

    package func setKeepOriginals(fingerprint: String, enabled: Bool) {
        guard let idx = devices.firstIndex(where: { $0.id == fingerprint }) else { return }
        devices[idx].keepOriginalsOnDevice = enabled
        persist()
    }

    package func setAllowJpgWhenNoRaw(fingerprint: String, enabled: Bool) {
        guard let idx = devices.firstIndex(where: { $0.id == fingerprint }) else { return }
        devices[idx].allowJpgWhenNoRaw = enabled
        persist()
    }

    package func recordConnection(fingerprint: String) {
        guard let idx = devices.firstIndex(where: { $0.id == fingerprint }) else { return }
        devices[idx].lastConnectedAt = Date()
        persist()
    }

    package func forget(fingerprint: String) {
        devices.removeAll { $0.id == fingerprint }
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            devices = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            devices = try decoder.decode([KnownDevice].self, from: data)
        } catch {
            logger.error("Failed loading known devices: \(error.localizedDescription, privacy: .public)")
            devices = []
        }
    }

    private func persist() {
        do {
            let parentDir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(devices)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed persisting known devices: \(error.localizedDescription, privacy: .public)")
        }
    }
}
