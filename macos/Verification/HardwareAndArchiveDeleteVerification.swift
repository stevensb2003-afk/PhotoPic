import Foundation
import PhotoPicKit

/// Verifies HardwareCapabilityAuditor, AI disabling / balanced modes,
/// and permanent Archived deletion (including sidecar + undoStack cleanup & path safety).
@MainActor
package enum HardwareAndArchiveDeleteVerification {
    package static func runAll() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicVerifyV21_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try testHardwareAuditorAndStore()
        try await testAIDisableAndLiveToggle(rootURL: tempRoot)
        try await testPermanentArchiveDeletionAndSafetyGuard(rootURL: tempRoot)
        try testHelpSearchAndLiveViewDefaults()
        try await testAndroidPermissionAndOffMainWriteQueueSafety()
        try testUSBValidatorIOSAndZeroLostShotShield(rootURL: tempRoot)

        print("ALL PHOTOPIC V2.1 HARDWARE & ARCHIVE DELETE VERIFICATIONS PASSED")
    }

    private static func assertTrue(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "PhotoPicVerify", code: 210, userInfo: [NSLocalizedDescriptionKey: "ASSERT FAILED: \(message)"])
        }
    }

    private static func testHardwareAuditorAndStore() throws {
        let hostReport = HardwareCapabilityAuditor.auditCurrentMac()
        try assertTrue(!hostReport.cpuBrand.isEmpty, "Host CPU brand detected")
        try assertTrue(hostReport.physicalMemoryGB >= 1, "Host RAM detected")

        let lowSpec = HardwareCapabilityAuditor.evaluateTier(
            isAppleSilicon: false, ramGB: 4, cores: 2, hasMetalGPU: false
        )
        try assertTrue(lowSpec.tier == .lightweightNoAI, "4GB/2-core no Metal recommends lightweightNoAI")

        let intelSpec = HardwareCapabilityAuditor.evaluateTier(
            isAppleSilicon: false, ramGB: 16, cores: 8, hasMetalGPU: true
        )
        try assertTrue(intelSpec.tier == .balancedAI, "Intel without Neural Engine recommends balancedAI")

        let appleSiliconSpec = HardwareCapabilityAuditor.evaluateTier(
            isAppleSilicon: true, ramGB: 16, cores: 8, hasMetalGPU: true
        )
        try assertTrue(appleSiliconSpec.tier == .fullAI, "Apple Silicon >=12GB recommends fullAI")

        let suiteName = "com.kairosvisuals.photopic.perfverify.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = PerformancePreferencesStore(defaults: defaults)
        var seeded = store.loadOrSeed(from: hostReport)
        try assertTrue(!seeded.hasCompletedGuidedSetup, "First seed starts before guided setup completion")
        seeded.enableVisionAutoTagging = false
        seeded.tier = .lightweightNoAI
        seeded.hasCompletedGuidedSetup = true
        store.save(seeded)

        let reloaded = store.loadOrSeed(from: hostReport)
        try assertTrue(!reloaded.enableVisionAutoTagging, "Disabled AI flag persists")
        try assertTrue(reloaded.hasCompletedGuidedSetup, "Guided setup completion persists")
        print("[PASS] 9. HardwareCapabilityAuditor & PerformancePreferencesStore verified")
    }

    private static func testAIDisableAndLiveToggle(rootURL: URL) async throws {
        let session = try SessionFileManager.createSession(named: "Audit_AI_Toggle", in: rootURL)
        let stage = rootURL.appendingPathComponent("StageAI", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

        let dng = stage.appendingPathComponent("NO_AI_01.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: dng, width: 640, height: 480)
        _ = try SessionIngestRouter.ingestCapturedFile(
            stagedURL: dng, originalFilename: "NO_AI_01.DNG",
            deviceAlias: "Canon", deviceCategory: .dslrMirrorless,
            allowJpgWhenNoRaw: false, in: session
        )

        let lightweightPrefs = PerformancePreferences.preset(for: .lightweightNoAI, completedSetup: true)
        let vm = CullingSessionViewModel(session: session, performancePreferences: lightweightPrefs)
        try await Task.sleep(for: .milliseconds(250))

        try assertTrue(!vm.autoTagOnIngest, "autoTagOnIngest disabled under lightweightNoAI")
        try assertTrue(vm.pendingItems.first?.visionTags == nil, "No AI tags generated when AI disabled")

        // Switch live to balancedAI -> triggers Vision face-only pass
        vm.applyPerformancePreferences(PerformancePreferences.preset(for: .balancedAI, completedSetup: true))
        try assertTrue(vm.autoTagOnIngest && !vm.detectBodyPoses, "Balanced mode enables faces & skips body poses")
        let tags = await vm.runVisionAnalysis(for: vm.pendingItems[0])
        try assertTrue(tags != nil, "Live re-enable of AI analyzes photo on demand")
        print("[PASS] 10. Disabling & live-toggling Neural Engine/Vision AI verified")
    }

    private static func testPermanentArchiveDeletionAndSafetyGuard(rootURL: URL) async throws {
        let session = try SessionFileManager.createSession(named: "Delete_Archived_Test", in: rootURL)
        let stage = rootURL.appendingPathComponent("StageDel", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

        for idx in 1...4 {
            let dng = stage.appendingPathComponent("DEL_\(idx).DNG")
            let jpg = stage.appendingPathComponent("DEL_\(idx).JPG")
            try SyntheticDNGGenerator.writeSyntheticDNG(to: dng, width: 512, height: 384, seedOffset: idx)
            try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: jpg, width: 160, height: 120)
            _ = try SessionIngestRouter.ingestCapturedFile(
                stagedURL: dng, originalFilename: "DEL_\(idx).DNG",
                deviceAlias: "Sony", deviceCategory: .dslrMirrorless,
                allowJpgWhenNoRaw: false, in: session
            )
            _ = try SessionIngestRouter.ingestCapturedFile(
                stagedURL: jpg, originalFilename: "DEL_\(idx).JPG",
                deviceAlias: "Sony", deviceCategory: .dslrMirrorless,
                allowJpgWhenNoRaw: false, in: session
            )
        }

        let vm = CullingSessionViewModel(
            session: session,
            performancePreferences: .preset(for: .lightweightNoAI, completedSetup: true)
        )
        // Photo 1 -> Para_Edicion/{RAW,JPG}, Photos 2 & 3 -> Archivadas/{RAW,JPG}, Photo 4 stays in RAW/
        vm.approveCurrentToEditing()
        let approvedRaw = session.forEditingRawFolderURL.appendingPathComponent("DEL_1.DNG")
        let approvedJpg = session.forEditingJpgFolderURL.appendingPathComponent("DEL_1.JPG")
        try assertTrue(FileManager.default.fileExists(atPath: approvedRaw.path), "DEL_1.DNG moved to Para_Edicion/RAW/")
        try assertTrue(FileManager.default.fileExists(atPath: approvedJpg.path), "DEL_1.JPG moved alongside RAW to Para_Edicion/JPG/")

        // Late-arriving extra JPG for DEL_1 must route directly to Para_Edicion/JPG/
        let lateJpg = stage.appendingPathComponent("DEL_1.HEIC")
        try SyntheticDNGGenerator.writeSyntheticJPEGWithExif(to: lateJpg, width: 120, height: 90)
        _ = vm.handleCapturedFileStaged(
            stagedURL: lateJpg, originalFilename: "DEL_1.HEIC",
            deviceProfile: KnownDevice(id: "cam", displayName: "Sony", alias: "Sony", category: .dslrMirrorless)
        )
        try assertTrue(
            FileManager.default.fileExists(atPath: session.forEditingJpgFolderURL.appendingPathComponent("DEL_1.HEIC").path),
            "Late compressed companion routes to Para_Edicion/JPG/"
        )

        // Archive DEL_2, then Undo -> both RAW and JPG must return to Sesión/{RAW,JPG}/
        vm.archiveCurrent()
        try assertTrue(
            FileManager.default.fileExists(atPath: session.archivedJpgFolderURL.appendingPathComponent("DEL_2.JPG").path),
            "DEL_2.JPG moved to Archivadas/JPG/"
        )
        vm.undoLastMove()
        try assertTrue(
            FileManager.default.fileExists(atPath: session.rawFolderURL.appendingPathComponent("DEL_2.DNG").path)
                && FileManager.default.fileExists(atPath: session.jpgFolderURL.appendingPathComponent("DEL_2.JPG").path),
            "Undo restores BOTH RAW and companion JPG back to RAW/ and JPG/"
        )

        vm.archiveCurrent()
        vm.archiveCurrent()

        try assertTrue(vm.pendingItems.count == 1, "1 pending item left in RAW/")
        try assertTrue(vm.session.counts.forEditing == 1, "1 approved item in Para_Edicion/")
        try assertTrue(vm.archivedItems.count == 2, "2 archived items in Archivadas/")
        try assertTrue(
            FileManager.default.fileExists(atPath: session.archivedRawFolderURL.appendingPathComponent("DEL_2.DNG").path),
            "DEL_2.DNG in Archivadas/RAW/"
        )
        try assertTrue(
            FileManager.default.fileExists(atPath: session.archivedJpgFolderURL.appendingPathComponent("DEL_2.JPG").path),
            "DEL_2.JPG moved alongside RAW to Archivadas/JPG/"
        )

        // Guard rail: refuse permanently deleting an item still in RAW/
        var threwOutsideGuard = false
        do {
            try SessionArchiveCleaner.permanentlyDeleteArchivedItem(
                vm.pendingItems[0], alsoDeleteCompanionJpg: false, in: session
            )
        } catch {
            threwOutsideGuard = true
        }
        try assertTrue(threwOutsideGuard, "Cleaner blocks permanent deletion outside Archivadas/")

        // Save tag & XMP sidecar for archived item #1
        let targetOne = vm.archivedItems[0]
        PhotoTagStore.save(
            tags: PhotoVisionTags(personCount: 1, faceCount: 1, autoTags: ["1 persona"]),
            for: targetOne,
            in: session,
            writeSidecarAndFinderTags: true
        )
        let xmpOne = PhotoTagStore.xmpSidecarURL(for: targetOne.fileURL)
        try assertTrue(FileManager.default.fileExists(atPath: xmpOne.path), "Archived XMP exists before delete")

        // Delete item #1 (because DEL_1..DEL_3 JPGs already moved into Archivadas/JPG/, deleting archived photo removes its archived pair too)
        vm.deleteArchivedItemPermanently(targetOne, alsoDeleteCompanionJpg: false)
        try assertTrue(!FileManager.default.fileExists(atPath: targetOne.fileURL.path), "Archived RAW permanently deleted")
        try assertTrue(!FileManager.default.fileExists(atPath: xmpOne.path), "Archived XMP permanently deleted")
        try assertTrue(targetOne.pairedCompressedURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true, "Archived JPG pair in Archivadas/JPG/ also cleaned")
        try assertTrue(PhotoTagStore.loadAll(for: session)[targetOne.baseFilename] == nil, "Tag store pruned")
        try assertTrue(vm.archivedItems.count == 1 && vm.session.counts.archived == 1, "1 archived left")

        // Cmd+Z must restore Photo 1 (from Para_Edicion) or skip purged item cleanly, not resurrect deleted file
        let remainingArchived = vm.archivedItems[0]
        vm.emptyAllArchivedPermanently(alsoDeleteCompanionJpgs: true)
        try assertTrue(vm.archivedItems.isEmpty && vm.session.counts.archived == 0, "Archivadas emptied")
        try assertTrue(!FileManager.default.fileExists(atPath: remainingArchived.fileURL.path), "Remaining archived file deleted")
        if let jpgURL = remainingArchived.pairedCompressedURL {
            try assertTrue(!FileManager.default.fileExists(atPath: jpgURL.path), "Companion JPG also deleted when checked")
        }
        // RAW and Para_Edicion untouched
        let finalCounts = SessionFileManager.readDiskCounts(for: session)
        try assertTrue(finalCounts.pending == 1 && finalCounts.forEditing == 1, "RAW/ and Para_Edicion/ intact after empty")
        print("[PASS] 11. Permanent Archive single delete, empty-all & path guard verified")
    }

    private static func testHelpSearchAndLiveViewDefaults() throws {
        let allTopics = HelpGuideCatalog.filter(query: "", category: .all)
        try assertTrue(allTopics.count >= 7, "Help catalog exposes all 7 topics")

        let gphotoHits = HelpGuideCatalog.filter(query: "gphoto2", category: .connectionsLive)
        try assertTrue(gphotoHits.count == 1 && gphotoHits.first?.id == "live-view-guide", "Keyword filter finds Live View limitations")

        let liveService = LiveViewCameraService()
        try assertTrue(liveService.showThirdsGrid && liveService.aspectGuide == .threeTwo, "Live View defaults configured")

        var mjpegBuffer = Data([0x00, 0xFF, 0xD8, 0xAA, 0xBB, 0xFF, 0xD9, 0xCC])
        let frame = NetworkMJPEGStreamService.extractNextJPEGFrame(from: &mjpegBuffer)
        try assertTrue(frame == Data([0xFF, 0xD8, 0xAA, 0xBB, 0xFF, 0xD9]) && mjpegBuffer == Data([0xCC]), "MJPEG SOI/EOI frame extractor parses cleanly")
        print("[PASS] 12. Help Center search/categories, LiveView & MJPEG stream extractor verified")
    }

    private static func testAndroidPermissionAndOffMainWriteQueueSafety() async throws {
        let androidState = DeviceConnectionStatus.androidPermissionRequired
        try assertTrue(!androidState.isLiveSessionOpen && androidState.label.contains("Android"), "Android permission status formatted")

        let capturedFilename: String? = await withCheckedContinuation { continuation in
            TetherCaptureService.dispatchWriteQueueCallbackForVerification { savedName, _ in
                Task { @MainActor in
                    continuation.resume(returning: savedName)
                }
            }
        }
        try assertTrue(capturedFilename == "verified_off_main.jpg", "Off-main ICDeviceWriteQueue callback completed without @MainActor SIGTRAP")
        print("[PASS] 13. Android permission state & off-main ICDeviceWriteQueue completion safety verified")
    }

    private static func testUSBValidatorIOSAndZeroLostShotShield(rootURL: URL) throws {
        try assertTrue(DeviceFingerprintMatcher.detectImagingHardware(vendorID: 0x04E8, productName: "SM-F966B", vendorName: "SAMSUNG") == .androidPTP, "Samsung phone classified as .androidPTP")
        try assertTrue(DeviceFingerprintMatcher.detectImagingHardware(vendorID: 0x18D1, productName: "Pixel 9", vendorName: "Google") == .androidPTP, "Pixel classified as .androidPTP")
        try assertTrue(DeviceFingerprintMatcher.detectImagingHardware(vendorID: 0x05AC, productName: "iPhone 16 Pro", vendorName: "Apple") == .iPhoneIOS, "iPhone classified as .iPhoneIOS")
        try assertTrue(DeviceFingerprintMatcher.detectImagingHardware(vendorID: 0x04A9, productName: "Canon EOS R5", vendorName: "Canon") == .dslrMirrorless, "Canon DSLR classified as .dslrMirrorless")
        try assertTrue(DeviceFingerprintMatcher.detectImagingHardware(vendorID: 0x054C, productName: "ILCE-7M4", vendorName: "Sony") == .dslrMirrorless, "Sony Alpha classified as .dslrMirrorless")
        try assertTrue(DeviceFingerprintMatcher.detectImagingHardware(vendorID: 0x05AC, productName: "Magic Keyboard", vendorName: "Apple") == nil, "Apple keyboard ignored")
        try assertTrue(DeviceFingerprintMatcher.detectImagingHardware(vendorID: 0x04E8, productName: "Portable SSD T7", vendorName: "Samsung") == nil, "Samsung SSD ignored")
        try assertTrue(DeviceFingerprintMatcher.detectImagingHardware(vendorID: 0x054C, productName: "DualSense Wireless Controller", vendorName: "Sony") == nil, "Sony DualSense ignored")

        let samsungUSB = PhysicalUSBDevice(
            id: "iokit:04e8:6865:demo", vendorID: 0x04E8, productID: 0x6865,
            vendorName: "SAMSUNG", productName: "SM-F966B", serialNumber: "demo", category: .androidPTP
        )
        let diag = DeviceConnectionDiagnostics.evaluate(physical: [samsungUSB], connected: [], conflictingApps: [])
        try assertTrue(diag.hasUnmountedHardware && diag.recommendedGuide == .samsungAndroid, "Validator flags unmounted Samsung hardware")

        var gate = TetherBaselineGate(connectedAtTimestamp: Date())
        gate.markCatalogComplete()
        let deadClockDate = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01
        let liveKey = TetherBaselineGate.itemKey(ptpHandle: 42, filename: "DSC00042.ARW", fileSize: 25_000_000)
        try assertTrue(gate.shouldDownloadLiveItem(key: liveKey, itemDate: deadClockDate, wasAddedAfterCatalog: true), "Dead-clock DSLR live shot accepted")

        let autoRoot = rootURL.appendingPathComponent("AutoQuickRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: autoRoot, withIntermediateDirectories: true)
        let suite = "com.kairosvisuals.photopic.verify.\(UUID().uuidString)"
        let defs = UserDefaults(suiteName: suite) ?? .standard
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let state = AppState(
            bookmarkManager: BookmarkManager(defaults: defs),
            knownDevicesStore: KnownDevicesStore(storageURL: autoRoot.appendingPathComponent("known.json")),
            performanceStore: PerformancePreferencesStore(defaults: defs),
            startDeviceBrowser: false
        )
        state.setRootFolderURL(autoRoot)
        let stageDNG = rootURL.appendingPathComponent("AUTO_01.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: stageDNG, width: 160, height: 120)
        let result = state.routeStagedCapture(
            stagedURL: stageDNG,
            originalFilename: "AUTO_01.DNG",
            deviceProfile: KnownDevice(id: "cam", displayName: "Canon EOS", alias: "Canon", category: .dslrMirrorless)
        )
        let savedInQuick = state.activeSessionViewModel?.session.rawFolderURL.appendingPathComponent("AUTO_01.DNG")
        try assertTrue(result != nil && savedInQuick.map { FileManager.default.fileExists(atPath: $0.path) } == true, "Auto-opened quick session preserved staged RAW")
        print("[PASS] 14. Physical USB validator, iOS/DSLR dead-clock shield & auto-session rescue verified")
    }
}
