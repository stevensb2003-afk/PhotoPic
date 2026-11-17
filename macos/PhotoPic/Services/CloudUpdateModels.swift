import CryptoKit
import Foundation

/// Cloud release manifest published automatically to GitHub Releases (`latest.json`).
package struct CloudReleaseManifest: Codable, Sendable, Equatable {
    package let version: String
    package let buildNumber: Int
    package let commitSHA: String
    package let publishedAt: String
    package let releaseNotes: String
    package let macosZipURL: String
    package let macosSha256: String
    package let macosSizeBytes: Int64
    package let macosDmgURL: String?
    package let windowsZipURL: String?
    package let windowsSha256: String?
    package let windowsSizeBytes: Int64?

    package init(
        version: String,
        buildNumber: Int,
        commitSHA: String,
        publishedAt: String,
        releaseNotes: String,
        macosZipURL: String,
        macosSha256: String,
        macosSizeBytes: Int64,
        macosDmgURL: String? = nil,
        windowsZipURL: String? = nil,
        windowsSha256: String? = nil,
        windowsSizeBytes: Int64? = nil
    ) {
        self.version = version
        self.buildNumber = buildNumber
        self.commitSHA = commitSHA
        self.publishedAt = publishedAt
        self.releaseNotes = releaseNotes
        self.macosZipURL = macosZipURL
        self.macosSha256 = macosSha256
        self.macosSizeBytes = macosSizeBytes
        self.macosDmgURL = macosDmgURL
        self.windowsZipURL = windowsZipURL
        self.windowsSha256 = windowsSha256
        self.windowsSizeBytes = windowsSizeBytes
    }
}

/// Identifies the currently running app bundle version, build number, and GitHub repository.
package struct AppBuildIdentity: Sendable, Equatable {
    package static let defaultRepository = "stevensb2003-afk/PhotoPic"
    package static let expectedBundleIdentifier = "com.kairosvisuals.photopic"

    package let shortVersion: String
    package let buildNumber: Int
    package let commitSHA: String
    package let repository: String
    package let bundleURL: URL
    package let isRunningFromAppBundle: Bool

    package init(
        shortVersion: String,
        buildNumber: Int,
        commitSHA: String,
        repository: String,
        bundleURL: URL,
        isRunningFromAppBundle: Bool
    ) {
        self.shortVersion = shortVersion
        self.buildNumber = buildNumber
        self.commitSHA = commitSHA
        self.repository = repository
        self.bundleURL = bundleURL
        self.isRunningFromAppBundle = isRunningFromAppBundle
    }

    package static func current(bundle: Bundle = .main) -> AppBuildIdentity {
        let info = bundle.infoDictionary ?? [:]
        let shortVer = (info["CFBundleShortVersionString"] as? String) ?? "2.6"
        let buildRaw = (info["CFBundleVersion"] as? String) ?? "0"
        let buildNum = Int(buildRaw) ?? 0
        let commit = (info["PhotoPicCommitSHA"] as? String) ?? "dev"
        let repo = (info["PhotoPicRepository"] as? String) ?? defaultRepository
        let url = bundle.bundleURL
        let isApp = url.pathExtension.lowercased() == "app" && bundle.bundleIdentifier != nil
        return AppBuildIdentity(
            shortVersion: shortVer,
            buildNumber: buildNum,
            commitSHA: commit,
            repository: repo,
            bundleURL: url,
            isRunningFromAppBundle: isApp
        )
    }

    package func hasNewerCloudBuild(_ manifest: CloudReleaseManifest) -> Bool {
        manifest.buildNumber > buildNumber
    }
}

/// Observable OTA update lifecycle states presented in the HUD banner and Settings.
package enum CloudUpdateState: Sendable, Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(CloudReleaseManifest)
    case downloading(CloudReleaseManifest, progress: Double)
    case readyToInstall(CloudReleaseManifest, stagedAppURL: URL)
    case installing(version: String)
    case failed(String)

    package var statusSummary: String {
        switch self {
        case .idle:
            return "Actualizaciones automáticas conectadas a GitHub Releases."
        case .checking:
            return "Buscando nueva versión en la nube..."
        case .upToDate(let version):
            return "Estás al día (v\(version))."
        case .updateAvailable(let manifest):
            return "Disponible v\(manifest.version): \(manifest.releaseNotes)"
        case .downloading(let manifest, _):
            return "Descargando v\(manifest.version) en segundo plano..."
        case .readyToInstall(let manifest, _):
            return "Versión v\(manifest.version) verificada (SHA-256) y lista para instalar."
        case .installing(let version):
            return "Instalando v\(version) y reiniciando PhotoPic..."
        case .failed(let message):
            return message
        }
    }
}

/// Pure SHA-256 verification helper used before extracting any downloaded cloud binary.
package enum CloudUpdateCrypto {
    package static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
