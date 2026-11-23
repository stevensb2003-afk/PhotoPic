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
        try await testFolderSessionImportAndAuditFixes(rootURL: tempRoot)

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

    private static func testFolderSessionImportAndAuditFixes(rootURL: URL) async throws {
        let fm = FileManager.default
        let externalShoot = rootURL.appendingPathComponent("ExternalShoot", isDirectory: true)
        let subA = externalShoot.appendingPathComponent("SubA", isDirectory: true)
        let subB = externalShoot.appendingPathComponent("SubB", isDirectory: true)
        let splitRAW = externalShoot.appendingPathComponent("SplitRAW", isDirectory: true)
        let splitJPG = externalShoot.appendingPathComponent("SplitJPG", isDirectory: true)
        let mobileDir = externalShoot.appendingPathComponent("Mobile", isDirectory: true)

        for dir in [subA, subB, splitRAW, splitJPG, mobileDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Same-dir RAW + JPG + XMP sidecar
        let img101Dng = subA.appendingPathComponent("IMG_101.DNG")
        let img101Jpg = subA.appendingPathComponent("IMG_101.JPG")
        let img101Xmp = subA.appendingPathComponent("IMG_101.xmp")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: img101Dng, width: 320, height: 240)
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: img101Jpg, iso: 200, aperture: 2.8, exposureSeconds: 1.0 / 250.0)
        try Data("<x:xmpmeta/>".utf8).write(to: img101Xmp)

        // Colliding stem in SubB -> must allocate IMG_101_2.DNG + IMG_101_2.JPG preserving pair
        let img101BDng = subB.appendingPathComponent("IMG_101.DNG")
        let img101BJpg = subB.appendingPathComponent("IMG_101.JPG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: img101BDng, width: 320, height: 240)
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: img101BJpg, iso: 400, aperture: 2.0, exposureSeconds: 1.0 / 125.0)

        // Cross-subdirectory RAW + JPG pairing
        try SyntheticDNGGenerator.writeSyntheticDNG(to: splitRAW.appendingPathComponent("IMG_202.DNG"), width: 320, height: 240)
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: splitJPG.appendingPathComponent("IMG_202.JPG"), iso: 100, aperture: 4.0, exposureSeconds: 1.0 / 500.0)

        // Standalone compressed photo
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: mobileDir.appendingPathComponent("SOLO_303.JPG"), iso: 160, aperture: 1.8, exposureSeconds: 1.0 / 1000.0)

        let topOnlySummary = try SessionFolderImporter.scanFolder(at: externalShoot, includeSubfolders: false)
        try assertTrue(topOnlySummary.totalPhotoUnitsCount == 0, "Top-level only scan should find 0 units")

        let deepSummary = try SessionFolderImporter.scanFolder(at: externalShoot, includeSubfolders: true)
        try assertTrue(
            deepSummary.rawUnitsCount == 3
                && deepSummary.pairedJpgCount == 3
                && deepSummary.standaloneCompressedCount == 1
                && deepSummary.totalPhotoUnitsCount == 4,
            "Two-pass scan counts mismatch: raw=\(deepSummary.rawUnitsCount) paired=\(deepSummary.pairedJpgCount) standalone=\(deepSummary.standaloneCompressedCount)"
        )

        let copyResult = try await SessionFolderImporter.importAsNewSession(
            from: deepSummary,
            sessionName: "Imported_Boda",
            groupName: "Bodas_2026",
            initialTags: ["Offline", "RAW"],
            transferMode: .copy,
            in: rootURL
        )
        try assertTrue(
            copyResult.importedUnitsCount == 4
                && copyResult.rawCount == 3
                && copyResult.pairedJpgCount == 3
                && copyResult.standaloneCompressedCount == 1,
            "Copy import counts mismatch"
        )
        try assertTrue(fm.fileExists(atPath: img101Dng.path), "Copy mode must keep source IMG_101.DNG")
        try assertTrue(fm.fileExists(atPath: copyResult.session.rawFolderURL.appendingPathComponent("IMG_101.xmp").path), "XMP sidecar must copy alongside IMG_101.DNG")
        try assertTrue(fm.fileExists(atPath: copyResult.session.rawFolderURL.appendingPathComponent("IMG_101_2.DNG").path), "Colliding RAW must get _2 stem")
        try assertTrue(fm.fileExists(atPath: copyResult.session.jpgFolderURL.appendingPathComponent("IMG_101_2.JPG").path), "Colliding paired JPG must get _2 stem")

        let vm = CullingSessionViewModel(
            session: copyResult.session,
            renderer: RawImageRenderer(),
            visionAnalyzer: PhotoVisionAnalyzer()
        )
        vm.autoTagOnIngest = false
        try assertTrue(vm.pendingItems.count == 4, "Imported session must load 4 pending items")

        // Audit Bug #1: Standalone compressed item round-tripping from Seleccionadas back to Filtrar
        guard let soloIndex = vm.pendingItems.firstIndex(where: { $0.filename == "SOLO_303.JPG" }) else {
            throw NSError(domain: "PhotoPicVerify", code: 101, userInfo: [NSLocalizedDescriptionKey: "SOLO_303.JPG missing in pendingItems"])
        }
        vm.jumpToIndex(soloIndex)
        vm.approveCurrentToEditing()
        guard let soloEditing = vm.forEditingItems.first(where: { $0.filename == "SOLO_303.JPG" }) else {
            throw NSError(domain: "PhotoPicVerify", code: 102, userInfo: [NSLocalizedDescriptionKey: "SOLO_303.JPG missing in forEditingItems"])
        }
        vm.returnEditingItemToPending(soloEditing)
        vm.reloadFromDisk()
        try assertTrue(
            vm.pendingItems.contains(where: { $0.filename == "SOLO_303.JPG" }),
            "Returned standalone compressed item must remain visible in pendingItems after reloadFromDisk"
        )

        // Audit Bug #2: Custom tag + XMP sidecar sync inside Seleccionadas (forEditingItems)
        vm.jumpToIndex(0)
        vm.approveCurrentToEditing()
        guard let approvedItem = vm.forEditingItems.first else {
            throw NSError(domain: "PhotoPicVerify", code: 103, userInfo: [NSLocalizedDescriptionKey: "Expected at least 1 approved item in forEditingItems"])
        }
        vm.addCustomTag("Portada", to: approvedItem)
        try assertTrue(
            vm.forEditingItems[0].visionTags?.allTags.contains("Portada") == true,
            "addCustomTag must update forEditingItems in-memory"
        )
        try assertTrue(
            fm.fileExists(atPath: PhotoTagStore.xmpSidecarURL(for: approvedItem.fileURL).path),
            "XMP sidecar must exist inside Para_Edicion/ when tagging selected item"
        )

        // Manual batch Vision AI must analyze all pending items even with autoTagOnIngest == false
        vm.runManualVisionAnalysisBatch()
        let deadline = Date().addingTimeInterval(10.0)
        while vm.isAnalyzingVision && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try assertTrue(!vm.isAnalyzingVision, "Manual batch Vision AI timed out")
        try assertTrue(vm.pendingItems.allSatisfy { $0.visionTags != nil }, "Manual batch Vision AI must tag all pending items")

        // Move transfer mode check
        let moveShoot = rootURL.appendingPathComponent("MoveShoot", isDirectory: true)
        try fm.createDirectory(at: moveShoot, withIntermediateDirectories: true)
        let moveDng = moveShoot.appendingPathComponent("MOVE_01.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: moveDng, width: 320, height: 240)
        let moveSummary = try SessionFolderImporter.scanFolder(at: moveShoot, includeSubfolders: true)
        let moveResult = try await SessionFolderImporter.importAsNewSession(
            from: moveSummary,
            sessionName: "Moved_Shoot",
            groupName: nil,
            initialTags: [],
            transferMode: .move,
            in: rootURL
        )
        try assertTrue(!fm.fileExists(atPath: moveDng.path), "Move mode must remove source MOVE_01.DNG")
        try assertTrue(fm.fileExists(atPath: moveResult.session.rawFolderURL.appendingPathComponent("MOVE_01.DNG").path), "Moved DNG must exist in destination RAW/")

        // Regression test: importing a session literally named `RAW` inside a Master Group must NOT turn the group into a 0-photo session
        let christmasGroup = try SessionFileManager.createMasterGroup(named: "2026 Sesiones Navidenas", in: rootURL)
        let rawSubfolderShoot = rootURL.appendingPathComponent("Familia_Navidad/RAW", isDirectory: true)
        try fm.createDirectory(at: rawSubfolderShoot, withIntermediateDirectories: true)
        try SyntheticDNGGenerator.writeSyntheticDNG(to: rawSubfolderShoot.appendingPathComponent("NAV_01.DNG"), width: 320, height: 240)
        try assertTrue(
            HomeViewModel.suggestedImportedSessionName(for: rawSubfolderShoot) == "Familia_Navidad",
            "Importing a generic RAW subfolder must suggest its parent folder name"
        )
        let rawSubSummary = try SessionFolderImporter.scanFolder(at: rawSubfolderShoot, includeSubfolders: false)
        _ = try await SessionFolderImporter.importAsNewSession(
            from: rawSubSummary,
            sessionName: "RAW",
            groupName: christmasGroup,
            initialTags: [],
            transferMode: .copy,
            in: rootURL
        )
        let discoveredGroups = SessionFileManager.loadMasterGroups(in: rootURL)
        let discoveredSessions = SessionFileManager.loadSessions(in: rootURL)
        try assertTrue(discoveredGroups.contains(christmasGroup), "Group containing a session named RAW must still be detected as a group")
        try assertTrue(!discoveredSessions.contains(where: { $0.name == christmasGroup && $0.groupName == nil }), "Group must never be misclassified as a 0-photo session")
        try assertTrue(
            discoveredSessions.contains(where: { $0.name == "RAW" && $0.groupName == christmasGroup && $0.counts.pending == 1 }),
            "Session named RAW inside group must be loaded under its group with real counts"
        )

        // Rename session & rename master group directly on disk
        guard let rawSessionToRename = discoveredSessions.first(where: { $0.name == "RAW" && $0.groupName == christmasGroup }) else {
            throw NSError(domain: "PhotoPicVerify", code: 104, userInfo: [NSLocalizedDescriptionKey: "Expected RAW session inside group"])
        }
        let renamedSession = try SessionFileManager.renameSession(rawSessionToRename, to: "Familia_Navidad", in: rootURL)
        try assertTrue(renamedSession.name == "Familia_Navidad" && fm.fileExists(atPath: renamedSession.directoryURL.path), "Session rename failed on disk")
        let renamedGroup = try SessionFileManager.renameMasterGroup(named: christmasGroup, to: "Navidad_2026", in: rootURL)
        try assertTrue(renamedGroup == "Navidad_2026", "Group rename returned unexpected name")
        let afterRenameSessions = SessionFileManager.loadSessions(in: rootURL)
        try assertTrue(
            afterRenameSessions.contains(where: { $0.name == "Familia_Navidad" && $0.groupName == "Navidad_2026" && $0.counts.pending == 1 }),
            "Renamed group + session must reload cleanly from disk"
        )

        // Persistent lossless 90° clockwise rotation on RAW (DNG) + paired JPG + CIRAWFilter dimension verification
        let rotSession = try SessionFileManager.createSession(named: "Rotation_Proof", in: rootURL)
        let rotDng = rotSession.rawFolderURL.appendingPathComponent("ROT_01.DNG")
        let rotJpg = rotSession.jpgFolderURL.appendingPathComponent("ROT_01.JPG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: rotDng, width: 320, height: 240)
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: rotJpg, iso: 200, aperture: 2.8, exposureSeconds: 1.0 / 250.0)
        let rotItem = PhotoItem(fileURL: rotDng, pairedCompressedURL: rotJpg)

        let o1 = try PhotoOrientationService.rotateClockwise90(item: rotItem)
        try assertTrue(o1 == 6, "First clockwise rotation must set EXIF orientation 6")
        try assertTrue(PhotoOrientationService.readOrientation(at: rotDng) == 6, "DNG orientation 6 must persist on disk")
        try assertTrue(PhotoOrientationService.readOrientation(at: rotJpg) == 6, "Paired JPG orientation 6 must persist on disk")

        let rotRenderer = RawImageRenderer()
        let rotatedPayload = await rotRenderer.renderViewportImage(for: rotItem, maxDimension: 1280)
        try assertTrue(
            rotatedPayload?.cgImage.width == 240 && rotatedPayload?.cgImage.height == 320,
            "CIRAWFilter must render rotated 240x320 dimensions after persisted DNG rotation"
        )
        _ = try PhotoOrientationService.rotateClockwise90(item: rotItem) // 3
        _ = try PhotoOrientationService.rotateClockwise90(item: rotItem) // 8
        let o4 = try PhotoOrientationService.rotateClockwise90(item: rotItem) // 1
        try assertTrue(o4 == 1 && PhotoOrientationService.readOrientation(at: rotDng) == 1, "Full 360° cycle must return orientation to 1")

        // Verify Canon EOS PTP property payloads (ISO 0xD103, Shutter 0xD102, Aperture 0xD101, Flash 0xD1DC) & Live View overlays
        let isoPayload = CanonEOSPropertyParser.buildSetPropertyPayload(property: .iso, rawValue: 0x58) // ISO 400
        try assertTrue(
            isoPayload.count == 12
                && CanonUSBPTPCodec.readUInt32LE(isoPayload, at: 0) == 12
                && CanonUSBPTPCodec.readUInt32LE(isoPayload, at: 4) == CameraPropertyID.iso.rawValue
                && isoPayload[8] == 0x58,
            "Canon ISO 0xD103 PTP payload encoding mismatch"
        )
        let tvPayload = CanonEOSPropertyParser.buildSetPropertyPayload(property: .shutterSpeed, rawValue: 0x70)
        let avPayload = CanonEOSPropertyParser.buildSetPropertyPayload(property: .aperture, rawValue: 0x20)
        try assertTrue(
            CanonUSBPTPCodec.readUInt32LE(tvPayload, at: 4) == CameraPropertyID.shutterSpeed.rawValue
                && CanonUSBPTPCodec.readUInt32LE(avPayload, at: 4) == CameraPropertyID.aperture.rawValue,
            "Canon Tv/Av PTP payload encoding mismatch"
        )
        let liveSvc = LiveViewCameraService()
        liveSvc.showThirdsGrid = true
        liveSvc.mirrorHorizontally = true
        if let altGuide = LiveAspectGuide.allCases.dropFirst().first {
            liveSvc.aspectGuide = altGuide
        }
        try assertTrue(
            liveSvc.showThirdsGrid && liveSvc.mirrorHorizontally && LiveAspectGuide.allCases.count >= 4,
            "LiveView overlays (3x3, mirror, aspect guide) state mismatch"
        )

        // Verify Canon 0xD111 battery percent mapping & <= 10% LowBatteryAlertTracker hysteresis
        try assertTrue(CanonEOSLookupTables.batteryPercent(for: 4) == 100, "Canon battery 4 must map to 100%")
        try assertTrue(CanonEOSLookupTables.batteryPercent(for: 1) == 25, "Canon battery 1 must map to 25%")
        try assertTrue(CanonEOSLookupTables.batteryPercent(for: 0) == 5, "Canon critical battery 0 must map to 5% (<=10%)")
        try assertTrue(CanonEOSLookupTables.batteryPercent(for: 10) == 10, "Direct 10% battery must map to 10%")
        try assertTrue(CanonEOSLookupTables.batteryPercent(for: 255) == nil, "External AC power must map to nil")

        var batTracker = LowBatteryAlertTracker()
        try assertTrue(!batTracker.evaluate(fingerprint: "cam-70d", batteryPercent: 25), "25% must not trigger <=10% alert")
        try assertTrue(batTracker.evaluate(fingerprint: "cam-70d", batteryPercent: 10), "10% must trigger low-battery alert once")
        try assertTrue(!batTracker.evaluate(fingerprint: "cam-70d", batteryPercent: 8), "Repeated <=10% must not spam alert")
        try assertTrue(!batTracker.evaluate(fingerprint: "cam-70d", batteryPercent: 12), "12% inside hysteresis band must stay latched")
        try assertTrue(!batTracker.evaluate(fingerprint: "cam-70d", batteryPercent: 25), "25% must reset latch without alerting")
        try assertTrue(batTracker.evaluate(fingerprint: "cam-70d", batteryPercent: 5), "Dropping <=10% after recovery must alert again")

        // Verify Canon 70D CaptureDestination [2, 6, 4] AvailList prefers 6 (SD + Host PC) over 2 (SD-only)
        var capDestEvent = Data()
        for word: UInt32 in [32, 0xC18A, 0xD11C, 3, 3, 2, 6, 4] {
            var le = word.littleEndian
            withUnsafeBytes(of: &le) { capDestEvent.append(contentsOf: $0) }
        }
        var capSnap = CameraControlSnapshot(deviceName: "Canon EOS 70D")
        CanonEOSPropertyParser.applyEvents(from: capDestEvent, into: &capSnap)
        try assertTrue(
            capSnap.detectedCardCaptureDest == 6,
            "Canon 70D AvailList [2, 6, 4] must select 6 (SD + Host PC), got \(String(describing: capSnap.detectedCardCaptureDest))"
        )

        // Verify compact 24-byte (0x18) 0xC186 RequestObjectTransfer event parses cleanly without being dropped
        var shortTransferEvent = Data()
        for word: UInt32 in [0x18, CanonPTPCode.eventRequestObjectTransfer, 0x9100_0042, UInt32(CanonPTPCode.formatCanonCRW3), 0, 24_500_000] {
            var le = word.littleEndian
            withUnsafeBytes(of: &le) { shortTransferEvent.append(contentsOf: $0) }
        }
        var dummyCounter = 0
        let parsedShortEvents = CanonUSBPTPCodec.parseEOSCaptureEvents(from: shortTransferEvent, fallbackCounter: &dummyCounter)
        try assertTrue(
            parsedShortEvents.count == 1
                && parsedShortEvents[0].handle == 0x9100_0042
                && parsedShortEvents[0].isRAMTransfer
                && parsedShortEvents[0].filename.hasSuffix(".CR2"),
            "Compact 24-byte 0xC186 RequestObjectTransfer must parse cleanly as CR2 RAM transfer"
        )

        print("[PASS] 7. Folder session import, group/session rename, persistent Shift rotation, Canon ISO/Tv/Av PTP payloads, LiveView overlays & <=10% battery alerts")
    }
}
