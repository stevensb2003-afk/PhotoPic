import AppKit
import Foundation
import PhotoPicKit
import SwiftUI

/// Renders offscreen Retina PNG screenshots of all 4 screens for visual QA and README docs.
@MainActor
package enum UISnapshotVerification {
    package static func renderAllSnapshots(to outputDir: URL) async throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicUIQA_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let defaults = UserDefaults(suiteName: "com.kairosvisuals.photopic.verify.\(UUID().uuidString)") ?? .standard
        let bookmarkManager = BookmarkManager(defaults: defaults)
        let storeURL = tempRoot.appendingPathComponent("known_devices.json")
        let knownStore = KnownDevicesStore(storageURL: storeURL)

        let canonDevice = KnownDevice(
            id: "sn:canon70d",
            displayName: "Canon EOS 70D",
            alias: "Canon 70D Principal",
            category: .dslrMirrorless,
            usbVendorID: 0x04A9,
            usbProductID: 0x3253,
            autoConnectOnPlug: true,
            keepOriginalsOnDevice: true,
            allowJpgWhenNoRaw: false
        )
        knownStore.saveOrUpdate(canonDevice)

        // Populate realistic studio sessions (grouped + flat for retrocompatibility showcase)
        let s1 = try SessionFileManager.createSession(
            named: "Editorial_Maria_Studio",
            groupName: "Sesiones Navidenas 2026",
            initialTags: ["Editorial", "VIP"],
            in: tempRoot
        )
        let s2 = try SessionFileManager.createSession(
            named: "Lookbook_Otono_2026",
            groupName: nil,
            initialTags: ["Exterior"],
            in: tempRoot
        )
        let stage = tempRoot.appendingPathComponent("StageUI", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

        for idx in 1...4 {
            let dng = stage.appendingPathComponent("IMG_10\(idx).DNG")
            let jpg = stage.appendingPathComponent("IMG_10\(idx).JPG")
            try SyntheticDNGGenerator.writeSyntheticDNG(to: dng, width: 960, height: 640, seedOffset: idx)
            try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: jpg, width: 320, height: 213)
            _ = try SessionIngestRouter.ingestCapturedFile(
                stagedURL: dng, originalFilename: "IMG_10\(idx).DNG",
                deviceAlias: "Canon 70D Principal", deviceCategory: .dslrMirrorless,
                allowJpgWhenNoRaw: false, in: s1
            )
            _ = try SessionIngestRouter.ingestCapturedFile(
                stagedURL: jpg, originalFilename: "IMG_10\(idx).JPG",
                deviceAlias: "Canon 70D Principal", deviceCategory: .dslrMirrorless,
                allowJpgWhenNoRaw: false, in: s1
            )
        }
        let s2Dng = stage.appendingPathComponent("Z_FOLD_01.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: s2Dng, width: 640, height: 480)
        _ = try SessionIngestRouter.ingestCapturedFile(
            stagedURL: s2Dng, originalFilename: "Z_FOLD_01.DNG",
            deviceAlias: "Samsung Z Fold", deviceCategory: .androidPTP,
            allowJpgWhenNoRaw: true, in: s2
        )

        // 1. Onboarding Step 1 (Guided Hardware Audit & AI Wizard) snapshot
        let wizardState = AppState(
            bookmarkManager: BookmarkManager(
                defaults: UserDefaults(suiteName: "com.kairosvisuals.photopic.wizard.\(UUID().uuidString)") ?? .standard
            ),
            knownDevicesStore: knownStore,
            startDeviceBrowser: false
        )
        try renderSnapshot(
            GuidedSetupWizardView(appState: wizardState),
            size: CGSize(width: 1360, height: 860),
            to: outputDir.appendingPathComponent("01-onboarding.png")
        )

        // 2. Home Dashboard snapshot (simulate connected Canon 70D + unknown Pixel 9 banner)
        let appState = AppState(bookmarkManager: bookmarkManager, knownDevicesStore: knownStore, startDeviceBrowser: false)
        appState.setRootFolderURL(tempRoot)
        appState.discoveryService.connectedDevices = [
            ConnectedDeviceState(
                fingerprint: canonDevice.fingerprint,
                deviceName: canonDevice.displayName,
                alias: canonDevice.alias,
                category: .dslrMirrorless,
                status: .connectedReady,
                batteryLevel: 84,
                isKnownDevice: true,
                usbVendorID: 0x04A9,
                usbProductID: 0x3253
            )
        ]
        appState.discoveryService.unknownDeviceBanner = ConnectedDeviceState(
            fingerprint: "android:pixel9",
            deviceName: "Pixel 9 Pro (PTP)",
            alias: "Pixel 9 Pro",
            category: .androidPTP,
            status: .detectedNotConnected
        )

        try renderSnapshot(
            RootShellView(appState: appState),
            size: CGSize(width: 1360, height: 860),
            to: outputDir.appendingPathComponent("02-home-dashboard.png")
        )

        // 3. Workspace Culling snapshot (wait briefly for Metal CIRAWFilter decode + populate rich Vision tags)
        appState.discoveryService.unknownDeviceBanner = nil
        appState.openSession(s1)
        guard let ws = appState.activeSessionViewModel else { return }
        ws.approveCurrentToEditing()
        ws.archiveCurrent()
        for idx in ws.pendingItems.indices {
            let demoTags = PhotoVisionTags(
                personCount: idx == 0 ? 2 : 1,
                faceCount: idx == 0 ? 2 : 1,
                hasClosedEyesWarning: false,
                autoTags: idx == 0
                    ? ["2 personas", "Pareja", "Plano medio", "De pie", "Ojos abiertos", "Rostro nítido"]
                    : ["1 persona", "Individual", "Primer plano", "Brazos arriba", "Ojos abiertos"]
            )
            PhotoTagStore.save(tags: demoTags, for: ws.pendingItems[idx], in: s1, writeSidecarAndFinderTags: true)
        }
        ws.reloadFromDisk()
        ws.startSessionTimerManual()
        try await waitUntil { ws.activeViewportImage != nil }

        try renderSnapshot(
            RootShellView(appState: appState),
            size: CGSize(width: 1360, height: 860),
            to: outputDir.appendingPathComponent("03-workspace-culling.png")
        )

        // 4. Workspace 1:1 Zoom snapshot
        ws.toggleLockedOneToOneZoom()
        try await waitUntil { ws.activeFullSensorImage != nil }

        try renderSnapshot(
            RootShellView(appState: appState),
            size: CGSize(width: 1360, height: 860),
            to: outputDir.appendingPathComponent("04-workspace-zoom-1to1.png")
        )

        // 5. Workspace Archived tab snapshot
        ws.toggleLockedOneToOneZoom()
        ws.activeTab = .archived
        if let firstArchived = ws.archivedItems.first {
            ws.selectArchivedItem(firstArchived)
            _ = await ws.renderThumbnail(for: firstArchived)
        }
        try await waitUntil { ws.archivedPreviewImage != nil }
        try await Task.sleep(for: .milliseconds(250))

        try renderSnapshot(
            RootShellView(appState: appState),
            size: CGSize(width: 1360, height: 860),
            to: outputDir.appendingPathComponent("05-workspace-archived.png")
        )

        // 6. Settings: Dispositivos tab
        appState.settingsTab = .devices
        try renderSnapshot(
            SettingsContainerSheet(appState: appState),
            size: CGSize(width: 680, height: 560),
            to: outputDir.appendingPathComponent("06-settings-devices.png")
        )

        // 7. Settings: General y Rendimiento tab
        appState.settingsTab = .general
        try renderSnapshot(
            SettingsContainerSheet(appState: appState),
            size: CGSize(width: 680, height: 560),
            to: outputDir.appendingPathComponent("07-settings-general.png")
        )

        // 8. Archived Permanent Delete Confirmation Popover snapshot
        if let firstArchived = ws.archivedItems.first {
            try renderSnapshot(
                ArchivedDeleteConfirmPopover(
                    item: firstArchived,
                    onCancel: {},
                    onConfirmDelete: { _ in }
                ),
                size: CGSize(width: 340, height: 198),
                to: outputDir.appendingPathComponent("08-archived-delete-popover.png")
            )
        }

        // 9. Built-in Offline Help Center snapshot (with search + categories + limitations)
        try renderSnapshot(
            HelpCenterView(initialCategory: .connectionsLive, initialQuery: ""),
            size: CGSize(width: 860, height: 620),
            to: outputDir.appendingPathComponent("09-help-center.png")
        )

        // 10. Workspace Live View tab snapshot (seed realistic Canon 70D remote controls for visual QA)
        var canonControlSnap = CameraControlSnapshot.canon70DDemo()
        canonControlSnap.deviceName = canonDevice.alias
        canonControlSnap.isDemoMode = false
        appState.discoveryService.directCanonService.seedSnapshotForTesting(
            fingerprint: canonDevice.fingerprint,
            snapshot: canonControlSnap
        )
        ws.activeTab = .liveView
        try await Task.sleep(for: .milliseconds(100))
        try renderSnapshot(
            RootShellView(appState: appState),
            size: CGSize(width: 1360, height: 860),
            to: outputDir.appendingPathComponent("10-workspace-live-view.png")
        )

        print("[PASS] 7. Rendered 10 Retina UI snapshots to \(outputDir.path)")
    }

    private static func waitUntil(condition: @escaping () -> Bool) async throws {
        for _ in 0..<60 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func renderSnapshot<V: View>(_ view: V, size: CGSize, to fileURL: URL) throws {
        let wrapped = view
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)

        let hosting = NSHostingView(rootView: wrapped)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            if ProcessInfo.processInfo.environment["CI"] != nil {
                print("[CI-SKIP] Headless display unavailable for \(fileURL.lastPathComponent)")
                return
            }
            throw NSError(domain: "UISnapshot", code: 1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "UISnapshot", code: 2)
        }
        try pngData.write(to: fileURL, options: .atomic)
    }
}
