import Foundation
import PhotoPicKit

/// Verifies Master Category Groups, project tags, Home search/filtering,
/// shooting timer auto-start on 1st photo timestamp, backward compatibility,
/// and guarded permanent project deletion on macOS.
@MainActor
package enum SessionGroupsTimerAndInspectorVerification {
    package static func runAll() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicV25Verify_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try testLegacyDecodingCompatibility()
        try testMasterGroupsTagsAndHomeFiltering(root: root)
        try testSessionTimerAutoStartAndManualControls(root: root)
        try testPermanentSessionDeletionAndSafetyGuard(root: root)

        print("[PASS] 6. Master Groups, Tags, Shooting Timer & Safe Project Delete passed (macOS)")
    }

    private static func testLegacyDecodingCompatibility() throws {
        // Old v2.x JSON without autoStartSessionTimerOnFirstShot must still default to true
        let legacyJSON = """
        {
          "tier": "balancedAI",
          "enableVisionAutoTagging": true,
          "detectBodyPoses": false,
          "viewportMaxDimension": 1920,
          "hasCompletedGuidedSetup": true
        }
        """
        let decoded = try JSONDecoder().decode(PerformancePreferences.self, from: Data(legacyJSON.utf8))
        guard decoded.tier == .balancedAI,
              decoded.hasCompletedGuidedSetup == true,
              decoded.autoStartSessionTimerOnFirstShot == true else {
            throw VerifyError("Legacy PerformancePreferences JSON did not preserve defaults")
        }

        // Empty legacy session directory without .photopic_session.json loads defaults cleanly
        let partialMeta = SessionMetadataStore.load(for: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        guard partialMeta.tags.isEmpty, partialMeta.hasNeverStartedTimer, partialMeta.formattedDuration() == "00:00:00" else {
            throw VerifyError("SessionMetadataStore fallback failed")
        }
    }

    private static func testMasterGroupsTagsAndHomeFiltering(root: URL) throws {
        let vm = HomeViewModel()
        // Pre-existing flat session on disk without .photopic_session.json (backward compatibility)
        let flat = try SessionFileManager.createSession(named: "Sesion_Plana_Legacy", in: root)
        // Grouped session inside a Master Folder created via v2.5 API
        let grouped = try SessionFileManager.createSession(
            named: "Nimrod_Y_Katherine",
            groupName: "Sesiones Navidenas 2026",
            initialTags: ["Navidad", "Familia"],
            in: root
        )

        vm.reloadSessions(in: root)
        guard vm.sessions.count == 2,
              vm.masterGroups == ["Sesiones Navidenas 2026"],
              vm.sessions.contains(where: { $0.id == flat.id && $0.groupName == nil }),
              vm.sessions.contains(where: { $0.id == grouped.id && $0.groupName == "Sesiones Navidenas 2026" }) else {
            throw VerifyError("2-level Master Group + flat session retrocompatible loading failed")
        }

        vm.groupFilter = .group("Sesiones Navidenas 2026")
        guard vm.filteredSessions.count == 1, vm.filteredSessions.first?.id == grouped.id else {
            throw VerifyError("Master Group filter failed")
        }

        vm.groupFilter = .ungrouped
        guard vm.filteredSessions.count == 1, vm.filteredSessions.first?.id == flat.id else {
            throw VerifyError("Ungrouped filter failed")
        }

        vm.groupFilter = .all
        vm.selectedTagFilter = "navidad"
        guard vm.filteredSessions.count == 1, vm.filteredSessions.first?.id == grouped.id else {
            throw VerifyError("Case-insensitive project tag filter failed")
        }

        vm.selectedTagFilter = nil
        vm.searchQuery = "Katherine"
        guard vm.filteredSessions.count == 1, vm.filteredSessions.first?.id == grouped.id else {
            throw VerifyError("Search query matching session name failed")
        }

        vm.searchQuery = "Navidenas"
        guard vm.filteredSessions.count == 1, vm.filteredSessions.first?.id == grouped.id else {
            throw VerifyError("Search query matching Master Group name failed")
        }

        vm.addTag("VIP", to: flat)
        vm.searchQuery = "vip"
        guard vm.filteredSessions.count == 1, vm.filteredSessions.first?.id == flat.id else {
            throw VerifyError("Search query matching newly added tag failed")
        }

        // Move flat session into Master Group
        vm.searchQuery = ""
        vm.moveSession(flat, toGroup: "Sesiones Navidenas 2026", in: root)
        guard vm.sessions.allSatisfy({ $0.groupName == "Sesiones Navidenas 2026" }) else {
            throw VerifyError("Moving session into Master Group failed")
        }
    }

    private static func testSessionTimerAutoStartAndManualControls(root: URL) throws {
        let timerSession = try SessionFileManager.createSession(
            named: "Timer_Auto_Test",
            groupName: "Bodas_2026",
            in: root
        )
        let stage = root.appendingPathComponent("StageTimer", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

        // Inject photo with a capture date 125 seconds in the past to verify timer anchors to 1st photo timestamp
        let dng1 = stage.appendingPathComponent("SHOT_001.DNG")
        let dng2 = stage.appendingPathComponent("SHOT_002.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: dng1, width: 320, height: 240)
        try SyntheticDNGGenerator.writeSyntheticDNG(to: dng2, width: 320, height: 240)
        let anchoredStart = Date().addingTimeInterval(-125)
        try FileManager.default.setAttributes([.creationDate: anchoredStart, .modificationDate: anchoredStart], ofItemAtPath: dng1.path)

        var prefs = PerformancePreferences.preset(for: .lightweightNoAI, completedSetup: true, autoStartTimer: true)
        let vm = CullingSessionViewModel(session: timerSession, performancePreferences: prefs)
        let profile = KnownDevice(
            id: "dev:timer",
            displayName: "Camera Test",
            alias: "Camera Test",
            category: .dslrMirrorless,
            allowJpgWhenNoRaw: false
        )

        _ = vm.handleCapturedFileStaged(stagedURL: dng1, originalFilename: "SHOT_001.DNG", deviceProfile: profile)
        guard vm.session.metadata.isTimerRunning else {
            throw VerifyError("Timer should auto-start when first live photo arrives")
        }
        let elapsed = vm.session.metadata.elapsedSeconds(at: Date())
        guard elapsed >= 120 && elapsed <= 140 else {
            throw VerifyError("Timer did not anchor to 1st photo timestamp (elapsed=\(elapsed))")
        }

        // Second shot must NOT overwrite firstShotEpoch
        let savedFirstEpoch = vm.session.metadata.firstShotEpoch
        _ = vm.handleCapturedFileStaged(stagedURL: dng2, originalFilename: "SHOT_002.DNG", deviceProfile: profile)
        guard vm.session.metadata.firstShotEpoch == savedFirstEpoch else {
            throw VerifyError("Second shot modified firstShotEpoch")
        }

        // Stop & persist
        vm.stopAndFinishSessionTimer()
        let reloaded = SessionMetadataStore.load(for: timerSession.directoryURL)
        guard !reloaded.isTimerRunning, reloaded.isTimerFinished, reloaded.accumulatedSeconds >= 120 else {
            throw VerifyError("Stopped session timer did not persist duration")
        }

        // Now verify disabling auto-start in preferences prevents automatic timer start
        let disabledSession = try SessionFileManager.createSession(named: "Timer_Manual_Only", in: root)
        prefs.autoStartSessionTimerOnFirstShot = false
        let manualVm = CullingSessionViewModel(session: disabledSession, performancePreferences: prefs)
        let dng3 = stage.appendingPathComponent("SHOT_003.DNG")
        try SyntheticDNGGenerator.writeSyntheticDNG(to: dng3, width: 320, height: 240)
        _ = manualVm.handleCapturedFileStaged(stagedURL: dng3, originalFilename: "SHOT_003.DNG", deviceProfile: profile)
        guard !manualVm.session.metadata.isTimerRunning, manualVm.session.metadata.hasNeverStartedTimer else {
            throw VerifyError("Timer started even though autoStartSessionTimerOnFirstShot was disabled")
        }
        manualVm.startSessionTimerManual()
        guard manualVm.session.metadata.isTimerRunning else {
            throw VerifyError("Manual timer start failed")
        }
    }

    private static func testPermanentSessionDeletionAndSafetyGuard(root: URL) throws {
        // Guard 1: refusing deletion of rootFolderURL itself
        let rootTrap = PhotoSession(name: "RootTrap", directoryURL: root)
        do {
            try SessionFileManager.permanentlyDeleteSession(rootTrap, in: root)
            throw VerifyError("Safety guard allowed deleting rootFolderURL!")
        } catch SessionFileManager.SessionFileError.unsafeDeleteTarget {
            // Expected
        }

        // Guard 2: refusing deletion of a path outside rootFolderURL
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoPicOutside_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDir.appendingPathComponent("RAW"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let outsideTrap = PhotoSession(name: "OutsideTrap", directoryURL: outsideDir)
        do {
            try SessionFileManager.permanentlyDeleteSession(outsideTrap, in: root)
            throw VerifyError("Safety guard allowed deleting directory outside rootFolderURL!")
        } catch SessionFileManager.SessionFileError.unsafeDeleteTarget {
            // Expected
        }

        // Guard 3: refusing deletion of a Master Group directory itself (no RAW/ child)
        let groupName = try SessionFileManager.createMasterGroup(named: "GrupoProtegido", in: root)
        let groupTrap = PhotoSession(name: groupName, directoryURL: root.appendingPathComponent(groupName))
        do {
            try SessionFileManager.permanentlyDeleteSession(groupTrap, in: root)
            throw VerifyError("Safety guard allowed deleting Master Group folder lacking RAW/!")
        } catch SessionFileManager.SessionFileError.unsafeDeleteTarget {
            // Expected
        }

        // Valid permanent deletion of a session containing photos removes everything from disk
        let target = try SessionFileManager.createSession(named: "Borrar_Completo", groupName: groupName, in: root)
        try Data("raw".utf8).write(to: target.rawFolderURL.appendingPathComponent("IMG_1.DNG"))
        try SessionFileManager.permanentlyDeleteSession(target, in: root)
        if FileManager.default.fileExists(atPath: target.directoryURL.path) {
            throw VerifyError("permanentlyDeleteSession did not remove directory from disk")
        }
    }
}

private struct VerifyError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
