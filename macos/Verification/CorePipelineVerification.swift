import CoreGraphics
import Foundation
import PhotoPicKit

/// Automated verification suite checking every functional invariant of PhotoPic.
@MainActor
package enum CorePipelineVerification {
    package static func runAll() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicVerify_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try testExpandedFormatSupport()
        try testSessionFolderStructure(rootURL: tempRoot)
        testAntiOldGalleryShield()
        try testSmartIngestAndFallback(rootURL: tempRoot)
        try await testCullingResilienceAndUndo(rootURL: tempRoot)
        try await testVisionAutoTaggingAndXMPSidecarSync(rootURL: tempRoot)
        try await testRawPureSensorMetalDecode(rootURL: tempRoot)
        testDeviceClassificationAndStore(rootURL: tempRoot)

        print("ALL PHOTOPIC CORE VERIFICATIONS PASSED")
    }

    private static func assertTrue(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "PhotoPicVerify", code: 100, userInfo: [NSLocalizedDescriptionKey: "ASSERT FAILED: \(message)"])
        }
    }

    private static func testExpandedFormatSupport() throws {
        let expectedRaws = [
            "a.cr2", "a.cr3", "a.dng", "a.nef", "a.nrw", "a.arw", "a.raf", "a.orf",
            "a.rw2", "a.pef", "a.srw", "a.3fr", "a.fff", "a.iiq", "a.rwl"
        ]
        let expectedCompressed = [
            "b.jpg", "b.jpeg", "b.heic", "b.heif", "b.hif", "b.avif", "b.jxl", "b.webp", "b.png", "b.tiff"
        ]
        for f in expectedRaws {
            try assertTrue(MediaFormatClassifier.classify(filename: f) == .raw, "Expected RAW classification for \(f)")
        }
        for f in expectedCompressed {
            try assertTrue(MediaFormatClassifier.classify(filename: f) == .compressed, "Expected compressed classification for \(f)")
        }
        print("[PASS] 0. Multi-brand image classifier verified across \(MediaFormatClassifier.rawExtensions.count) RAW + \(MediaFormatClassifier.compressedExtensions.count) mobile/compressed formats")
    }

    private static func testSessionFolderStructure(rootURL: URL) throws {
        let session = try SessionFileManager.createSession(named: "Editorial_Novia", in: rootURL)
        for sub in SessionSubfolder.allCases {
            let subURL = session.directoryURL.appendingPathComponent(sub.rawValue, isDirectory: true)
            try assertTrue(FileManager.default.fileExists(atPath: subURL.path), "Subfolder \(sub.rawValue) must exist")
        }
        let discovered = SessionFileManager.loadSessions(in: rootURL)
        try assertTrue(discovered.count == 1 && discovered[0].name == session.name, "Session discovery failed")
        print("[PASS] 1. Session 4-subfolder structure (RAW/JPG/Para_Edicion/Archivadas) & disk scan")
    }

    private static func testAntiOldGalleryShield() {
        let connectTime = Date()
        var gate = TetherBaselineGate(connectedAtTimestamp: connectTime)

        // Simulate 200 old photos already on Android phone roll or DSLR SD card
        for idx in 1...200 {
            let key = TetherBaselineGate.itemKey(ptpHandle: UInt32(idx), filename: "OLD_\(idx).DNG", fileSize: 28_000_000)
            let oldDate = connectTime.addingTimeInterval(-Double(idx * 60))
            gate.recordPreCatalogItem(key: key, itemDate: oldDate)
            // Nothing can download before catalog completes
            assert(gate.shouldDownloadLiveItem(key: key, itemDate: oldDate, wasAddedAfterCatalog: false) == false)
        }

        gate.markCatalogComplete()

        // Re-evaluating any of the 200 pre-existing items via Smart Delta Watcher must stay false
        for idx in 1...200 {
            let key = TetherBaselineGate.itemKey(ptpHandle: UInt32(idx), filename: "OLD_\(idx).DNG", fileSize: 28_000_000)
            let oldDate = connectTime.addingTimeInterval(-Double(idx * 60))
            assert(gate.shouldDownloadLiveItem(key: key, itemDate: oldDate, wasAddedAfterCatalog: false) == false)
        }

        // Old unindexed file older than connection timestamp must also be rejected
        let staleKey = TetherBaselineGate.itemKey(ptpHandle: 9001, filename: "OLD_EXTRA.JPG", fileSize: 4_000_000)
        assert(gate.shouldDownloadLiveItem(key: staleKey, itemDate: connectTime.addingTimeInterval(-300), wasAddedAfterCatalog: false) == false)

        // Brand-new shot taken 0.5s after connecting must pass immediately (and never duplicate on second delta poll)
        let newKey = TetherBaselineGate.itemKey(ptpHandle: 9002, filename: "NEW_0001.DNG", fileSize: 31_000_000)
        let newDate = connectTime.addingTimeInterval(0.5)
        assert(gate.shouldDownloadLiveItem(key: newKey, itemDate: newDate, wasAddedAfterCatalog: true) == true)
        assert(gate.shouldDownloadLiveItem(key: newKey, itemDate: newDate, wasAddedAfterCatalog: false) == false)

        print("[PASS] 2. Anti-Old-Gallery shield (0/200 old items downloaded; live shots accepted once)")
    }

    private static func testSmartIngestAndFallback(rootURL: URL) throws {
        let session = try SessionFileManager.createSession(named: "Ingest_Test", in: rootURL)
        let stageDir = rootURL.appendingPathComponent("Stage", isDirectory: true)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        let dslrDng = stageDir.appendingPathComponent("IMG_0001.DNG")
        let dslrJpg = stageDir.appendingPathComponent("IMG_0001.JPG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: dslrDng, width: 320, height: 240)
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: dslrJpg)

        let res1 = try SessionIngestRouter.ingestCapturedFile(
            stagedURL: dslrDng, originalFilename: "IMG_0001.DNG",
            deviceAlias: "Canon 70D", deviceCategory: .dslrMirrorless, allowJpgWhenNoRaw: false, in: session
        )
        guard case .addedRaw = res1 else {
            try assertTrue(false, "Expected addedRaw for DNG")
            return
        }

        let res2 = try SessionIngestRouter.ingestCapturedFile(
            stagedURL: dslrJpg, originalFilename: "IMG_0001.JPG",
            deviceAlias: "Canon 70D", deviceCategory: .dslrMirrorless, allowJpgWhenNoRaw: false, in: session
        )
        guard case .separatedCompanionJpg = res2 else {
            try assertTrue(false, "Expected separatedCompanionJpg for companion JPG")
            return
        }

        // Mobile fallback OFF ignores JPG from entering RAW queue
        let mobOffJpg = stageDir.appendingPathComponent("PHONE_OFF.JPG")
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: mobOffJpg)
        let resOff = try SessionIngestRouter.ingestCapturedFile(
            stagedURL: mobOffJpg, originalFilename: "PHONE_OFF.JPG",
            deviceAlias: "Pixel", deviceCategory: .androidPTP, allowJpgWhenNoRaw: false, in: session
        )
        guard case .separatedCompanionJpg = resOff else {
            try assertTrue(false, "Expected JPG to go to JPG/ when mobile fallback is OFF")
            return
        }

        // Mobile fallback ON enters RAW/, then late-arriving DNG demotes the JPG into JPG/
        let mobOnJpg = stageDir.appendingPathComponent("PHONE_0099.JPG")
        let mobOnDng = stageDir.appendingPathComponent("PHONE_0099.DNG")
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: mobOnJpg)
        try SyntheticDNGGenerator.writeSyntheticDNG(to: mobOnDng, width: 320, height: 240)

        let resOn = try SessionIngestRouter.ingestCapturedFile(
            stagedURL: mobOnJpg, originalFilename: "PHONE_0099.JPG",
            deviceAlias: "Samsung Fold", deviceCategory: .androidPTP, allowJpgWhenNoRaw: true, in: session
        )
        guard case .addedMobileFallbackCompressed = resOn else {
            try assertTrue(false, "Expected mobile fallback compressed entry")
            return
        }

        let resLateDng = try SessionIngestRouter.ingestCapturedFile(
            stagedURL: mobOnDng, originalFilename: "PHONE_0099.DNG",
            deviceAlias: "Samsung Fold", deviceCategory: .androidPTP, allowJpgWhenNoRaw: true, in: session
        )
        guard case .addedRaw(_, let demoted) = resLateDng, demoted == "PHONE_0099.JPG" else {
            try assertTrue(false, "Late DNG must demote PHONE_0099.JPG to JPG/")
            return
        }

        let counts = SessionFileManager.readDiskCounts(for: session)
        try assertTrue(counts.pending == 2 && counts.companionJpgs == 3, "Disk counts mismatch after smart pairing")
        print("[PASS] 3. RAW+JPG separation, mobile JPG fallback, and late-DNG promotion")
    }

    private static func testCullingResilienceAndUndo(rootURL: URL) async throws {
        let session = try SessionFileManager.createSession(named: "Culling_Test", in: rootURL)
        let vm = CullingSessionViewModel(session: session, renderer: RawImageRenderer())
        let androidProfile = KnownDevice(id: "android1", displayName: "Galaxy", alias: "Samsung Z Fold", category: .androidPTP)

        let stageDir = rootURL.appendingPathComponent("StageCull", isDirectory: true)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        for i in 1...3 {
            let file = stageDir.appendingPathComponent("SHOT_0\(i).DNG")
            try SyntheticDNGGenerator.writeSyntheticDNG(to: file, width: 320, height: 240, seedOffset: i)
            _ = vm.handleCapturedFileStaged(stagedURL: file, originalFilename: "SHOT_0\(i).DNG", deviceProfile: androidProfile)
        }

        try assertTrue(vm.pendingItems.count == 3, "Expected 3 pending shots")
        try assertTrue(vm.currentIndex == 0, "Should stay on index 0 when followLatestCapture == false")

        // Follow latest capture OFF must NOT interrupt current photo when SHOT_04 arrives
        vm.navigateNext()
        try assertTrue(vm.currentIndex == 1 && vm.currentPendingItem?.filename == "SHOT_02.DNG", "Navigate next failed")
        let shot4 = stageDir.appendingPathComponent("SHOT_04.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: shot4, width: 320, height: 240, seedOffset: 4)
        _ = vm.handleCapturedFileStaged(stagedURL: shot4, originalFilename: "SHOT_04.DNG", deviceProfile: androidProfile)
        try assertTrue(vm.currentIndex == 1 && vm.pendingItems.count == 4, "Live capture interrupted active index!")

        // Follow latest capture ON jumps straight to SHOT_05
        vm.followLatestCapture = true
        let shot5 = stageDir.appendingPathComponent("SHOT_05.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: shot5, width: 320, height: 240, seedOffset: 5)
        _ = vm.handleCapturedFileStaged(stagedURL: shot5, originalFilename: "SHOT_05.DNG", deviceProfile: androidProfile)
        try assertTrue(vm.currentIndex == 4 && vm.currentPendingItem?.filename == "SHOT_05.DNG", "Follow latest capture failed")

        // Swipe Right -> Para_Edicion
        vm.approveCurrentToEditing()
        try assertTrue(vm.session.counts.forEditing == 1 && vm.pendingItems.count == 4, "Approve to Para_Edicion failed")

        // Swipe Left -> Archivadas, then Undo -> RAW, then Archive again -> Recover to Para_Edicion
        let targetName = vm.currentPendingItem?.filename ?? ""
        vm.archiveCurrent()
        try assertTrue(vm.session.counts.archived == 1 && vm.archivedItems.count == 1, "Archive move failed")

        vm.undoLastMove()
        try assertTrue(vm.session.counts.archived == 0 && vm.currentPendingItem?.filename == targetName, "Cmd+Z undo failed")

        vm.archiveCurrent()
        let archivedItem = vm.archivedItems[0]
        vm.recoverArchivedItemToEditing(archivedItem)
        try assertTrue(vm.session.counts.archived == 0 && vm.session.counts.forEditing == 2 && vm.forEditingItems.count == 2, "Archived recovery failed")

        try assertTrue(WorkspaceTab.cullPending.title == "Filtrar" && WorkspaceTab.forEditing.title == "Seleccionadas", "Workspace tab titles synthesized cleanly")
        let firstSelected = vm.forEditingItems[0]
        vm.moveEditingItemToArchived(firstSelected)
        try assertTrue(vm.session.counts.forEditing == 1 && vm.forEditingItems.count == 1 && vm.session.counts.archived == 1, "Moving selected item to Archivadas failed")
        let secondSelected = vm.forEditingItems[0]
        vm.returnEditingItemToPending(secondSelected)
        try assertTrue(vm.session.counts.forEditing == 0 && vm.forEditingItems.isEmpty && vm.pendingItems.count == 4, "Returning selected item to Filtrar failed")
        print("[PASS] 4. Live non-disruptive queue, followLatest, Seleccionadas transitions, Cmd+Z Undo & Recovery")
    }

    private static func testVisionAutoTaggingAndXMPSidecarSync(rootURL: URL) async throws {
        let session = try SessionFileManager.createSession(named: "Vision_Tag_Test", in: rootURL)
        let vm = CullingSessionViewModel(session: session, renderer: RawImageRenderer(), visionAnalyzer: PhotoVisionAnalyzer())
        vm.autoTagOnIngest = false
        let stageDir = rootURL.appendingPathComponent("StageVision", isDirectory: true)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        let shot = stageDir.appendingPathComponent("VSN_0001.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: shot, width: 480, height: 320)
        let profile = KnownDevice(id: "cam1", displayName: "Sony A7 IV", alias: "Sony A7 IV", category: .dslrMirrorless)
        _ = vm.handleCapturedFileStaged(stagedURL: shot, originalFilename: "VSN_0001.DNG", deviceProfile: profile)
        try assertTrue(vm.pendingItems.count == 1, "Vision test shot must be queued")

        let tags = await vm.runVisionAnalysis(for: vm.pendingItems[0])
        try assertTrue(tags != nil && !(tags?.allTags.isEmpty ?? true), "Vision analyzer must emit semantic tags")

        vm.addCustomTag("Pareja", to: vm.pendingItems[0])
        let xmpInRaw = PhotoTagStore.xmpSidecarURL(for: vm.pendingItems[0].fileURL)
        try assertTrue(FileManager.default.fileExists(atPath: xmpInRaw.path), "XMP sidecar must be created beside RAW")

        // Tag filter matches custom/auto tag cleanly
        vm.selectedTagFilter = "Pareja"
        try assertTrue(vm.visiblePendingItems.count == 1, "Tag filter must retain matching item")

        // Moving photo to Para_Edicion must also relocate its .xmp sidecar into Para_Edicion/RAW/!
        vm.approveCurrentToEditing()
        try assertTrue(!FileManager.default.fileExists(atPath: xmpInRaw.path), "Old XMP sidecar must move out of RAW/")
        let movedDng = session.forEditingRawFolderURL.appendingPathComponent("VSN_0001.DNG")
        let xmpInEditing = PhotoTagStore.xmpSidecarURL(for: movedDng)
        try assertTrue(FileManager.default.fileExists(atPath: movedDng.path), "Approved RAW must move into Para_Edicion/RAW/")
        try assertTrue(FileManager.default.fileExists(atPath: xmpInEditing.path), "XMP sidecar must follow RAW into Para_Edicion/RAW/")

        // Undo must bring both RAW and .xmp back to RAW/
        vm.undoLastMove()
        try assertTrue(FileManager.default.fileExists(atPath: xmpInRaw.path), "Undo must restore XMP sidecar to RAW/")

        // Reloading from disk must rehydrate tags from .photopic_tags.json
        let reloadedMap = PhotoTagStore.loadAll(for: session)
        try assertTrue(reloadedMap["vsn_0001"]?.allTags.contains("Pareja") == true, "Tag JSON persistence mismatch")
        print("[PASS] 5. Offline Vision AI tagging + .photopic_tags.json + .xmp sidecar sync & tag filtering")
    }

    private static func testRawPureSensorMetalDecode(rootURL: URL) async throws {
        let dngURL = rootURL.appendingPathComponent("SENSOR_PROOF.DNG")
        let jpgURL = rootURL.appendingPathComponent("EXIF_PROOF.JPG")
        // Embedded IFD0 thumb is 16x12; true LinearRaw sensor in SubIFD0 is 640x480!
        try SyntheticDNGGenerator.writeSyntheticDNG(to: dngURL, width: 640, height: 480)
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: jpgURL, iso: 800, aperture: 1.8, exposureSeconds: 1.0 / 500.0)

        let renderer = RawImageRenderer()
        let rawItem = PhotoItem(fileURL: dngURL)
        let vpPayload = await renderer.renderViewportImage(for: rawItem, maxDimension: 2400)
        let fullPayload = await renderer.renderFullSensorImage(for: rawItem)

        try assertTrue(vpPayload?.cgImage.width == 640 && vpPayload?.cgImage.height == 480, "Viewport RAW must decode 640x480 sensor, NOT 16x12 thumb")
        try assertTrue(fullPayload?.cgImage.width == 640 && fullPayload?.cgImage.height == 480, "1:1 RAW must decode full 640x480 sensor")
        try assertTrue(fullPayload?.isFullSensorResolution == true, "1:1 flag must be true")

        let exif = ExifMetadataReader.read(from: jpgURL)
        try assertTrue(exif.iso == 800 && exif.formattedAperture == "f/1.8" && exif.formattedShutter == "1/500s", "EXIF reader mismatch")
        print("[PASS] 5. Metal CIRAWFilter decoded pure 640x480 sensor (not 16x12 thumb) + EXIF reader")
    }

    private static func testDeviceClassificationAndStore(rootURL: URL) {
        let canon = DeviceFingerprintMatcher.classify(name: "Canon EOS 70D", productKind: "Camera", vendorID: 0x04A9)
        let pixel = DeviceFingerprintMatcher.classify(name: "Pixel 9 Pro", productKind: "Camera", vendorID: 0x18D1)
        let iphone = DeviceFingerprintMatcher.classify(name: "iPhone 16 Pro", productKind: "iPhone", vendorID: 0x05AC)
        let gopro = DeviceFingerprintMatcher.classify(name: "HERO13 Black", productKind: "Camera", vendorID: 0x2672)
        assert(canon == .dslrMirrorless && pixel == .androidPTP && iphone == .iPhoneIOS && gopro == .compactAction)

        let storeURL = rootURL.appendingPathComponent("known_devices.json")
        let store1 = KnownDevicesStore(storageURL: storeURL)
        let dev = KnownDevice(id: "sn:1193:canon70d", displayName: "Canon EOS 70D", alias: "Canon 70D Principal", category: .dslrMirrorless)
        store1.saveOrUpdate(dev)
        store1.setAllowJpgWhenNoRaw(fingerprint: dev.fingerprint, enabled: true)

        let store2 = KnownDevicesStore(storageURL: storeURL)
        assert(store2.device(for: dev.fingerprint)?.alias == "Canon 70D Principal")
        assert(store2.device(for: dev.fingerprint)?.allowJpgWhenNoRaw == true)
        store2.forget(fingerprint: dev.fingerprint)
        assert(store2.devices.isEmpty)
        print("[PASS] 6. Hardware fingerprinting, category classification & KnownDevicesStore JSON")
    }
}
