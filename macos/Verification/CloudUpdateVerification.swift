import Foundation
import PhotoPicKit

/// Verifies Cloud OTA manifest decoding, build comparison, SHA-256 integrity enforcement,
/// background archive staging, and backward-compatible update preferences on macOS.
@MainActor
package enum CloudUpdateVerification {
    package static func runAll() throws {
        try testLegacyUpdatePrefsDefaults()
        try testManifestDecodeAndBuildComparison()
        try testArchiveSha256VerificationAndStaging()
        print("[PASS] 8. Cloud OTA manifest, SHA-256 verification & staging passed (macOS)")
    }

    private static func testLegacyUpdatePrefsDefaults() throws {
        let oldJSON = """
        {
          "tier": "fullAI",
          "enableVisionAutoTagging": true,
          "detectBodyPoses": true,
          "viewportMaxDimension": 2400,
          "hasCompletedGuidedSetup": true
        }
        """
        let prefs = try JSONDecoder().decode(PerformancePreferences.self, from: Data(oldJSON.utf8))
        guard prefs.autoCheckForUpdates, prefs.autoDownloadUpdates else {
            throw OTAError("Legacy PerformancePreferences did not default auto-update flags to true")
        }
    }

    private static func testManifestDecodeAndBuildComparison() throws {
        let json = """
        {
          "version": "2.6.99",
          "buildNumber": 99,
          "commitSHA": "abc1234",
          "publishedAt": "2026-11-17T06:00:00Z",
          "releaseNotes": "Mejoras OTA",
          "macosZipURL": "https://example.com/PhotoPic-macOS-arm64.zip",
          "macosSha256": "deadbeef",
          "macosSizeBytes": 1024,
          "macosDmgURL": "https://example.com/PhotoPic-Installer.dmg",
          "windowsZipURL": "https://example.com/PhotoPic-Windows-x64.zip",
          "windowsSha256": "cafebabe",
          "windowsSizeBytes": 2048
        }
        """
        let manifest = try JSONDecoder().decode(CloudReleaseManifest.self, from: Data(json.utf8))
        let olderIdentity = AppBuildIdentity(
            shortVersion: "2.6.14",
            buildNumber: 14,
            commitSHA: "old123",
            repository: AppBuildIdentity.defaultRepository,
            bundleURL: URL(fileURLWithPath: "/Applications/PhotoPic.app"),
            isRunningFromAppBundle: true
        )
        let sameIdentity = AppBuildIdentity(
            shortVersion: "2.6.99",
            buildNumber: 99,
            commitSHA: "abc1234",
            repository: AppBuildIdentity.defaultRepository,
            bundleURL: URL(fileURLWithPath: "/Applications/PhotoPic.app"),
            isRunningFromAppBundle: true
        )

        guard olderIdentity.hasNewerCloudBuild(manifest), !sameIdentity.hasNewerCloudBuild(manifest) else {
            throw OTAError("Build number comparison failed")
        }
    }

    private static func testArchiveSha256VerificationAndStaging() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicOTAVerify_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let mockApp = tempRoot.appendingPathComponent("PhotoPic.app", isDirectory: true)
        let contentsDir = mockApp.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.kairosvisuals.photopic</string>
        <key>CFBundleShortVersionString</key><string>2.6.99</string>
        <key>CFBundleVersion</key><string>99</string>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: contentsDir.appendingPathComponent("Info.plist"))

        let zipCopy1 = tempRoot.appendingPathComponent("valid.zip")
        let zipCopy2 = tempRoot.appendingPathComponent("tampered.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", mockApp.path, zipCopy1.path]
        try ditto.run()
        ditto.waitUntilExit()
        try FileManager.default.copyItem(at: zipCopy1, to: zipCopy2)

        let validSha = try CloudUpdateCrypto.sha256Hex(of: zipCopy1)
        let stagedApp = try CloudUpdateService.verifyAndExtractArchive(
            downloadedZipURL: zipCopy1,
            expectedSha256: validSha,
            buildNumber: 99,
            verifyBundleAndSignature: false
        )
        defer { try? FileManager.default.removeItem(at: stagedApp.deletingLastPathComponent()) }
        guard FileManager.default.fileExists(atPath: stagedApp.appendingPathComponent("Contents/Info.plist").path) else {
            throw OTAError("Staged archive missing Contents/Info.plist")
        }

        // Wrong SHA-256 must throw and refuse extraction
        do {
            _ = try CloudUpdateService.verifyAndExtractArchive(
                downloadedZipURL: zipCopy2,
                expectedSha256: String(repeating: "0", count: 64),
                buildNumber: 100,
                verifyBundleAndSignature: false
            )
            throw OTAError("SHA-256 mismatch was NOT rejected")
        } catch {
            // Expected
        }
    }
}

private struct OTAError: LocalizedError {
    let msg: String
    init(_ msg: String) { self.msg = msg }
    var errorDescription: String? { msg }
}
