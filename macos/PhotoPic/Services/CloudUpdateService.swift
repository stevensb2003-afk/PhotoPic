import AppKit
import Foundation
import Observation

/// Manages background cloud update checks against GitHub Releases, SHA-256 validation,
/// background `.app` staging, and atomic self-replacement + relaunch.
@MainActor
@Observable
package final class CloudUpdateService {
    package let identity: AppBuildIdentity
    package private(set) var state: CloudUpdateState = .idle
    package var autoCheckEnabled: Bool
    package var autoDownloadEnabled: Bool
    package var bannerDismissedForBuild: Int? = nil

    private var periodicTask: Task<Void, Never>?

    package init(
        identity: AppBuildIdentity = .current(),
        autoCheckEnabled: Bool = true,
        autoDownloadEnabled: Bool = true
    ) {
        self.identity = identity
        self.autoCheckEnabled = autoCheckEnabled
        self.autoDownloadEnabled = autoDownloadEnabled
    }

    package func manifestURL() -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        return URL(string: "https://github.com/\(identity.repository)/releases/latest/download/latest.json?t=\(stamp)")
    }

    package func startAutomaticLifecycle() {
        periodicTask?.cancel()
        periodicTask = nil
        guard autoCheckEnabled else { return }

        periodicTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            while let self, !Task.isCancelled {
                await self.checkForUpdates(userInitiated: false)
                try? await Task.sleep(for: .seconds(1800))
            }
        }
    }

    package func stopAutomaticLifecycle() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    package func checkForUpdates(userInitiated: Bool = false) async {
        switch state {
        case .checking, .downloading, .installing:
            return
        case .readyToInstall where !userInitiated:
            return
        default:
            break
        }
        guard let url = manifestURL() else { return }

        state = .checking
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
            request.setValue("PhotoPic/\(identity.shortVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                state = .upToDate(version: identity.shortVersion)
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                state = userInitiated
                    ? .failed("El servidor de actualizaciones respondió HTTP \(http.statusCode).")
                    : .upToDate(version: identity.shortVersion)
                return
            }

            let manifest = try JSONDecoder().decode(CloudReleaseManifest.self, from: data)
            guard identity.hasNewerCloudBuild(manifest) else {
                state = .upToDate(version: identity.shortVersion)
                return
            }

            if case .readyToInstall(let stagedManifest, _) = state, stagedManifest.buildNumber == manifest.buildNumber {
                return
            }

            bannerDismissedForBuild = nil
            state = .updateAvailable(manifest)
            if autoDownloadEnabled && identity.isRunningFromAppBundle {
                await downloadAndStageUpdate(manifest)
            }
        } catch {
            state = userInitiated
                ? .failed("No se pudo conectar con GitHub Releases: \(error.localizedDescription)")
                : .idle
        }
    }

    package func downloadAndStageUpdate(
        _ manifest: CloudReleaseManifest,
        verifyBundleAndSignature: Bool = true
    ) async {
        guard let zipURL = URL(string: manifest.macosZipURL) else {
            state = .failed("URL de descarga macOS inválida en latest.json.")
            return
        }

        state = .downloading(manifest, progress: 0.25)
        do {
            var request = URLRequest(url: zipURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 180)
            request.setValue("PhotoPic/\(identity.shortVersion)", forHTTPHeaderField: "User-Agent")
            let (tempZipURL, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: tempZipURL)
                state = .failed("Error descargando actualización (HTTP \(http.statusCode)).")
                return
            }

            state = .downloading(manifest, progress: 0.8)
            let stagedAppURL = try await Task.detached(priority: .utility) {
                try Self.verifyAndExtractArchive(
                    downloadedZipURL: tempZipURL,
                    expectedSha256: manifest.macosSha256,
                    buildNumber: manifest.buildNumber,
                    verifyBundleAndSignature: verifyBundleAndSignature
                )
            }.value

            state = .readyToInstall(manifest, stagedAppURL: stagedAppURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    package func installReadyUpdateAndRelaunch() {
        guard case .readyToInstall(let manifest, let stagedAppURL) = state else { return }
        guard identity.isRunningFromAppBundle else {
            state = .failed("La auto-instalación requiere ejecutar PhotoPic desde el paquete .app.")
            return
        }

        state = .installing(version: manifest.version)
        do {
            try Self.spawnDetachedSwapAndRelaunch(
                stagedAppURL: stagedAppURL,
                targetAppURL: identity.bundleURL,
                pid: ProcessInfo.processInfo.processIdentifier
            )
            NSApplication.shared.terminate(nil)
        } catch {
            state = .failed("No se pudo iniciar el instalador automático: \(error.localizedDescription)")
        }
    }

    nonisolated package static func verifyAndExtractArchive(
        downloadedZipURL: URL,
        expectedSha256: String,
        buildNumber: Int,
        verifyBundleAndSignature: Bool
    ) throws -> URL {
        defer { try? FileManager.default.removeItem(at: downloadedZipURL) }
        let actualSha = try CloudUpdateCrypto.sha256Hex(of: downloadedZipURL).lowercased()
        guard actualSha == expectedSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            throw NSError(
                domain: "PhotoPicUpdater",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "Verificación SHA-256 fallida: archivo corrupto o alterado."]
            )
        }

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicUpdate_\(buildNumber)", isDirectory: true)
        try? FileManager.default.removeItem(at: stagingRoot)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        try runProcess("/usr/bin/ditto", ["-x", "-k", downloadedZipURL.path, stagingRoot.path])

        let appURL = stagingRoot.appendingPathComponent("PhotoPic.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw NSError(
                domain: "PhotoPicUpdater",
                code: 102,
                userInfo: [NSLocalizedDescriptionKey: "El paquete descargado no contiene PhotoPic.app."]
            )
        }

        try? runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", appURL.path])

        if verifyBundleAndSignature {
            let plistURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
            if let dict = NSDictionary(contentsOf: plistURL),
               let bundleID = dict["CFBundleIdentifier"] as? String,
               bundleID != AppBuildIdentity.expectedBundleIdentifier {
                throw NSError(
                    domain: "PhotoPicUpdater",
                    code: 103,
                    userInfo: [NSLocalizedDescriptionKey: "Bundle Identifier inválido: \(bundleID)."]
                )
            }
            try runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        }
        return appURL
    }

    nonisolated private static func spawnDetachedSwapAndRelaunch(
        stagedAppURL: URL,
        targetAppURL: URL,
        pid: Int32
    ) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("photopic_ota_install_\(pid).sh", isDirectory: false)
        let script = """
        #!/bin/sh
        PID="$1"
        STAGED="$2"
        TARGET="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.25; done
        PARENT=$(dirname "$TARGET")
        if [ -w "$PARENT" ] && ([ ! -e "$TARGET" ] || [ -w "$TARGET" ]); then
          rm -rf "${TARGET}.backup"
          if [ -e "$TARGET" ]; then mv "$TARGET" "${TARGET}.backup" || exit 1; fi
          if ditto "$STAGED" "$TARGET"; then
            xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
            rm -rf "${TARGET}.backup" "$(dirname "$STAGED")"
          else
            [ -e "${TARGET}.backup" ] && mv "${TARGET}.backup" "$TARGET"
            exit 1
          fi
        else
          ESCAPED=$(printf '%s' "rm -rf '$TARGET' && ditto '$STAGED' '$TARGET' && xattr -dr com.apple.quarantine '$TARGET'" | sed "s/'/'\\\\\\\\''/g")
          osascript -e "do shell script '$ESCAPED' with administrator privileges" || exit 1
          rm -rf "$(dirname "$STAGED")"
        fi
        open -n "$TARGET"
        rm -f "$0"
        """
        try Data(script.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        task.arguments = ["/bin/sh", scriptURL.path, String(pid), stagedAppURL.path, targetAppURL.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
    }

    nonisolated private static func runProcess(_ launchPath: String, _ arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let stderr = Pipe()
        proc.standardError = stderr
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Exit \(proc.terminationStatus)"
            throw NSError(
                domain: "PhotoPicUpdater",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Error en \(launchPath): \(msg.trimmingCharacters(in: .whitespacesAndNewlines))"]
            )
        }
    }
}
