import AppKit
import Foundation

@MainActor
private func runVerification() async {
    _ = NSApplication.shared
    NSApp.appearance = NSAppearance(named: .darkAqua)

    do {
        try await CorePipelineVerification.runAll()
        try await HardwareAndArchiveDeleteVerification.runAll()

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let snapshotDir = repoRoot.appendingPathComponent("assets/screenshots", isDirectory: true)
        try await UISnapshotVerification.renderAllSnapshots(to: snapshotDir)
        exit(0)
    } catch {
        fputs("VERIFICATION FAILED: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

await runVerification()
