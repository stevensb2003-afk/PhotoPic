import Foundation
import os

/// How files from an existing computer folder are placed inside the target PhotoPic session.
package enum FolderImportTransferMode: String, CaseIterable, Identifiable, Sendable {
    case copy
    case move

    package var id: String { rawValue }

    package var displayTitle: String {
        switch self {
        case .copy: return "Copiar archivos (seguro)"
        case .move: return "Mover originales"
        }
    }

    package var subtitle: String {
        switch self {
        case .copy: return "Conserva la carpeta original intacta y organiza copias segregadas dentro de la sesión"
        case .move: return "Traslada las fotos a la sesión sin duplicar espacio en disco"
        }
    }
}

package enum SessionImportError: LocalizedError, Sendable {
    case sourceFolderUnreadable(String)
    case sourceOverlapsSession(String)
    case noSupportedPhotosFound
    case transferFailed(String)

    package var errorDescription: String? {
        switch self {
        case .sourceFolderUnreadable(let path):
            return "No se pudo leer la carpeta seleccionada: \(path)"
        case .sourceOverlapsSession(let detail):
            return "La carpeta origen coincide o se superpone con la sesión de destino (\(detail)). Seleccioná otra carpeta."
        case .noSupportedPhotosFound:
            return "No se encontraron fotos compatibles (RAW, JPG, HEIC, PNG, TIFF o WebP) en esa carpeta."
        case .transferFailed(let detail):
            return "No se pudieron importar los archivos: \(detail)"
        }
    }
}

package struct FolderImportExtensionCount: Identifiable, Sendable, Hashable {
    package var id: String { ext }
    package let ext: String
    package let count: Int

    package init(ext: String, count: Int) {
        self.ext = ext
        self.count = count
    }
}

package struct PlannedImportUnit: Sendable, Hashable {
    package let primaryURL: URL
    package let companionURL: URL?
    package let formatKind: MediaFormatKind
    package let fileSizeBytes: Int64

    package init(
        primaryURL: URL,
        companionURL: URL?,
        formatKind: MediaFormatKind,
        fileSizeBytes: Int64
    ) {
        self.primaryURL = primaryURL
        self.companionURL = companionURL
        self.formatKind = formatKind
        self.fileSizeBytes = fileSizeBytes
    }
}

package struct FolderImportScanSummary: Sendable {
    package let sourceURL: URL
    package let includeSubfolders: Bool
    package let rawUnitsCount: Int
    package let pairedJpgCount: Int
    package let standaloneCompressedCount: Int
    package let totalBytes: Int64
    package let extensionBreakdown: [FolderImportExtensionCount]
    package let units: [PlannedImportUnit]

    package var totalPhotoUnitsCount: Int { units.count }
    package var totalFilesCount: Int { rawUnitsCount + pairedJpgCount + standaloneCompressedCount }

    package var formattedTotalBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    package init(
        sourceURL: URL,
        includeSubfolders: Bool,
        rawUnitsCount: Int,
        pairedJpgCount: Int,
        standaloneCompressedCount: Int,
        totalBytes: Int64,
        extensionBreakdown: [FolderImportExtensionCount],
        units: [PlannedImportUnit]
    ) {
        self.sourceURL = sourceURL
        self.includeSubfolders = includeSubfolders
        self.rawUnitsCount = rawUnitsCount
        self.pairedJpgCount = pairedJpgCount
        self.standaloneCompressedCount = standaloneCompressedCount
        self.totalBytes = totalBytes
        self.extensionBreakdown = extensionBreakdown
        self.units = units
    }
}

package struct FolderImportProgress: Sendable {
    package let completedUnits: Int
    package let totalUnits: Int
    package let currentFilename: String

    package var fractionCompleted: Double {
        guard totalUnits > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completedUnits) / Double(totalUnits)))
    }
}

package struct FolderImportResult: Sendable {
    package let session: PhotoSession
    package let importedUnitsCount: Int
    package let rawCount: Int
    package let pairedJpgCount: Int
    package let standaloneCompressedCount: Int
    package let skippedFilesCount: Int
}

/// Scans an existing photo directory on disk, segregates RAW vs compressed/JPG pairs across
/// flat or nested folders, allocates collision-free filenames, and copies/moves `.xmp` sidecars
/// into a managed PhotoPic session ready for culling and batch Vision AI analysis.
package enum SessionFolderImporter {
    private static let logger = Logger(subsystem: "com.kairosvisuals.photopic", category: "FolderImporter")

    private struct DirectoryStemKey: Hashable {
        let directoryPath: String
        let baseStem: String
    }

    package static func scanFolder(
        at sourceURL: URL,
        includeSubfolders: Bool
    ) throws -> FolderImportScanSummary {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SessionImportError.sourceFolderUnreadable(sourceURL.path)
        }

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let imageURLs = try collectSupportedImages(in: sourceURL, includeSubfolders: includeSubfolders)
        var rawFiles: [URL] = []
        var compressedFiles: [URL] = []
        var extensionCounts: [String: Int] = [:]

        for url in imageURLs {
            guard let kind = MediaFormatClassifier.classify(filename: url.lastPathComponent) else { continue }
            let ext = url.pathExtension.uppercased()
            extensionCounts[ext, default: 0] += 1
            switch kind {
            case .raw:
                rawFiles.append(url)
            case .compressed:
                compressedFiles.append(url)
            }
        }

        let units = pairImagesTwoPass(rawFiles: rawFiles, compressedFiles: compressedFiles)
        var rawUnitsCount = 0
        var pairedJpgCount = 0
        var standaloneCompressedCount = 0
        var totalBytes: Int64 = 0

        for unit in units {
            totalBytes += unit.fileSizeBytes
            if unit.formatKind == .raw {
                rawUnitsCount += 1
                if unit.companionURL != nil {
                    pairedJpgCount += 1
                }
            } else {
                standaloneCompressedCount += 1
            }
        }

        let breakdown = extensionCounts
            .map { FolderImportExtensionCount(ext: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.ext < rhs.ext }
                return lhs.count > rhs.count
            }

        return FolderImportScanSummary(
            sourceURL: sourceURL,
            includeSubfolders: includeSubfolders,
            rawUnitsCount: rawUnitsCount,
            pairedJpgCount: pairedJpgCount,
            standaloneCompressedCount: standaloneCompressedCount,
            totalBytes: totalBytes,
            extensionBreakdown: breakdown,
            units: units
        )
    }

    package static func importAsNewSession(
        from summary: FolderImportScanSummary,
        sessionName: String,
        groupName: String?,
        initialTags: [String],
        transferMode: FolderImportTransferMode,
        in rootURL: URL,
        onProgress: (@Sendable (FolderImportProgress) -> Void)? = nil
    ) async throws -> FolderImportResult {
        guard !summary.units.isEmpty else {
            throw SessionImportError.noSupportedPhotosFound
        }

        let trimmedName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = trimmedName.isEmpty ? summary.sourceURL.lastPathComponent : trimmedName
        let createdSession = try SessionFileManager.createSession(
            named: effectiveName,
            groupName: groupName,
            initialTags: initialTags,
            in: rootURL
        )

        do {
            return try await importIntoExistingSession(
                from: summary,
                into: createdSession,
                transferMode: transferMode,
                onProgress: onProgress
            )
        } catch {
            // Roll back empty newly created folder when import cannot proceed (e.g. overlap guard).
            let counts = SessionFileManager.readDiskCounts(for: createdSession)
            if counts.totalAllImages == 0 && counts.companionJpgs == 0 {
                try? FileManager.default.removeItem(at: createdSession.directoryURL)
            }
            throw error
        }
    }

    package static func importIntoExistingSession(
        from summary: FolderImportScanSummary,
        into session: PhotoSession,
        transferMode: FolderImportTransferMode,
        onProgress: (@Sendable (FolderImportProgress) -> Void)? = nil
    ) async throws -> FolderImportResult {
        guard !summary.units.isEmpty else {
            throw SessionImportError.noSupportedPhotosFound
        }

        try validateNoOverlap(sourceURL: summary.sourceURL, sessionURL: session.directoryURL, transferMode: transferMode)
        try SessionFileManager.ensureSubfoldersExist(for: session)

        return try await Task.detached(priority: .userInitiated) {
            try transferUnits(
                summary.units,
                sourceURL: summary.sourceURL,
                into: session,
                transferMode: transferMode,
                onProgress: onProgress
            )
        }.value
    }

    // MARK: - Collection & Two-Pass Pairing

    private static func collectSupportedImages(in sourceURL: URL, includeSubfolders: Bool) throws -> [URL] {
        let fm = FileManager.default
        var collected: [URL] = []

        if includeSubfolders {
            guard let enumerator = fm.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    logger.warning("Skipping unreadable entry during scan (\(url.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                    return true
                }
            ) else {
                throw SessionImportError.sourceFolderUnreadable(sourceURL.path)
            }

            while let nextObject = enumerator.nextObject() {
                guard let entryURL = nextObject as? URL else { continue }
                let resourceValues = try? entryURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    let markerURL = entryURL.appendingPathComponent(".photopic_session.json", isDirectory: false)
                    if fm.fileExists(atPath: markerURL.path) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard resourceValues?.isRegularFile != false,
                      MediaFormatClassifier.isSupportedImage(url: entryURL) else {
                    continue
                }
                collected.append(entryURL)
            }
        } else {
            let entries: [URL]
            do {
                entries = try fm.contentsOfDirectory(
                    at: sourceURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw SessionImportError.sourceFolderUnreadable(sourceURL.path)
            }
            for entryURL in entries {
                let resourceValues = try? entryURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues?.isRegularFile != false,
                      MediaFormatClassifier.isSupportedImage(url: entryURL) else {
                    continue
                }
                collected.append(entryURL)
            }
        }

        return collected.sorted {
            $0.standardizedFileURL.path.localizedStandardCompare($1.standardizedFileURL.path) == .orderedAscending
        }
    }

    private static func pairImagesTwoPass(rawFiles: [URL], compressedFiles: [URL]) -> [PlannedImportUnit] {
        var remainingCompressed = Set(compressedFiles)

        var sameDirLookup: [DirectoryStemKey: [URL]] = [:]
        var globalStemLookup: [String: [URL]] = [:]

        let prioritizedCompressed = compressedFiles.sorted { lhs, rhs in
            let lPriority = compressedPairingPriority(for: lhs)
            let rPriority = compressedPairingPriority(for: rhs)
            if lPriority != rPriority { return lPriority < rPriority }
            return lhs.standardizedFileURL.path < rhs.standardizedFileURL.path
        }

        for url in prioritizedCompressed {
            let stem = MediaFormatClassifier.baseFilename(for: url)
            let dirKey = DirectoryStemKey(
                directoryPath: url.deletingLastPathComponent().standardizedFileURL.path,
                baseStem: stem
            )
            sameDirLookup[dirKey, default: []].append(url)
            globalStemLookup[stem, default: []].append(url)
        }

        var pairedCompanionByRaw: [URL: URL] = [:]

        // Pass 1: exact same-directory stem match (e.g. `Shoot/IMG_001.CR2` + `Shoot/IMG_001.JPG`).
        for rawURL in rawFiles {
            let dirKey = DirectoryStemKey(
                directoryPath: rawURL.deletingLastPathComponent().standardizedFileURL.path,
                baseStem: MediaFormatClassifier.baseFilename(for: rawURL)
            )
            if let candidates = sameDirLookup[dirKey],
               let match = candidates.first(where: { remainingCompressed.contains($0) }) {
                pairedCompanionByRaw[rawURL] = match
                remainingCompressed.remove(match)
            }
        }

        // Pass 2: cross-subdirectory stem match (e.g. `RAW/IMG_001.CR2` + `JPG/IMG_001.JPG`).
        for rawURL in rawFiles where pairedCompanionByRaw[rawURL] == nil {
            let stem = MediaFormatClassifier.baseFilename(for: rawURL)
            if let candidates = globalStemLookup[stem],
               let match = candidates.first(where: { remainingCompressed.contains($0) }) {
                pairedCompanionByRaw[rawURL] = match
                remainingCompressed.remove(match)
            }
        }

        var units: [PlannedImportUnit] = []
        units.reserveCapacity(rawFiles.count + remainingCompressed.count)

        for rawURL in rawFiles {
            let companion = pairedCompanionByRaw[rawURL]
            let bytes = fileSize(for: rawURL) + (companion.map(fileSize(for:)) ?? 0)
            units.append(
                PlannedImportUnit(
                    primaryURL: rawURL,
                    companionURL: companion,
                    formatKind: .raw,
                    fileSizeBytes: bytes
                )
            )
        }

        // Pass 3: standalone compressed images stay eligible for `Filtrar` culling and Vision AI.
        for compURL in remainingCompressed {
            units.append(
                PlannedImportUnit(
                    primaryURL: compURL,
                    companionURL: nil,
                    formatKind: .compressed,
                    fileSizeBytes: fileSize(for: compURL)
                )
            )
        }

        return units.sorted { lhs, rhs in
            let lName = lhs.primaryURL.lastPathComponent.lowercased()
            let rName = rhs.primaryURL.lastPathComponent.lowercased()
            if lName != rName { return lName < rName }
            return lhs.primaryURL.standardizedFileURL.path < rhs.primaryURL.standardizedFileURL.path
        }
    }

    private static func compressedPairingPriority(for url: URL) -> Int {
        switch url.pathExtension.uppercased() {
        case "JPG", "JPEG": return 0
        case "HEIC", "HEIF": return 1
        default: return 2
        }
    }

    private static func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: - Transfer & Collision-Free Allocation

    private static func validateNoOverlap(
        sourceURL: URL,
        sessionURL: URL,
        transferMode: FolderImportTransferMode
    ) throws {
        let sourcePath = sourceURL.standardizedFileURL.path
        let sessionPath = sessionURL.standardizedFileURL.path

        if sourcePath == sessionPath || sourcePath.hasPrefix(sessionPath + "/") {
            throw SessionImportError.sourceOverlapsSession(sessionURL.lastPathComponent)
        }
        if transferMode == .move && sessionPath.hasPrefix(sourcePath + "/") {
            throw SessionImportError.sourceOverlapsSession(sourceURL.lastPathComponent)
        }
    }

    private static func transferUnits(
        _ units: [PlannedImportUnit],
        sourceURL: URL,
        into session: PhotoSession,
        transferMode: FolderImportTransferMode,
        onProgress: (@Sendable (FolderImportProgress) -> Void)?
    ) throws -> FolderImportResult {
        let fm = FileManager.default
        let didAccessSource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSource { sourceURL.stopAccessingSecurityScopedResource() }
        }

        var importedUnits = 0
        var rawCount = 0
        var pairedJpgCount = 0
        var standaloneCompressedCount = 0
        var skippedCount = 0
        var lastErrorDescription: String?

        let totalUnits = units.count
        for (index, unit) in units.enumerated() {
            onProgress?(
                FolderImportProgress(
                    completedUnits: index,
                    totalUnits: totalUnits,
                    currentFilename: unit.primaryURL.lastPathComponent
                )
            )

            let targets = allocateTargetURLs(for: unit, in: session, fileManager: fm)
            do {
                try performFileTransfer(
                    from: unit.primaryURL,
                    to: targets.primaryTarget,
                    mode: transferMode,
                    fileManager: fm
                )
                transferXMPSidecarIfPresent(
                    from: unit.primaryURL,
                    to: targets.primaryTarget,
                    mode: transferMode,
                    fileManager: fm
                )

                if let companionURL = unit.companionURL, let companionTarget = targets.companionTarget {
                    try performFileTransfer(
                        from: companionURL,
                        to: companionTarget,
                        mode: transferMode,
                        fileManager: fm
                    )
                    pairedJpgCount += 1
                }

                importedUnits += 1
                if unit.formatKind == .raw {
                    rawCount += 1
                } else {
                    standaloneCompressedCount += 1
                }
            } catch {
                skippedCount += 1
                lastErrorDescription = error.localizedDescription
                logger.error("Failed to import \(unit.primaryURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        onProgress?(
            FolderImportProgress(
                completedUnits: totalUnits,
                totalUnits: totalUnits,
                currentFilename: ""
            )
        )

        if importedUnits == 0, let lastErrorDescription {
            throw SessionImportError.transferFailed(lastErrorDescription)
        }

        var updatedSession = session
        updatedSession.counts = SessionFileManager.readDiskCounts(for: session)

        return FolderImportResult(
            session: updatedSession,
            importedUnitsCount: importedUnits,
            rawCount: rawCount,
            pairedJpgCount: pairedJpgCount,
            standaloneCompressedCount: standaloneCompressedCount,
            skippedFilesCount: skippedCount
        )
    }

    private static func allocateTargetURLs(
        for unit: PlannedImportUnit,
        in session: PhotoSession,
        fileManager fm: FileManager
    ) -> (primaryTarget: URL, companionTarget: URL?) {
        let primaryName = unit.primaryURL.lastPathComponent
        let primaryExt = unit.primaryURL.pathExtension
        let primaryStem = (primaryName as NSString).deletingPathExtension

        let companionExt = unit.companionURL?.pathExtension ?? ""

        var suffix = 1
        while true {
            let resolvedStem = suffix == 1 ? primaryStem : "\(primaryStem)_\(suffix)"
            let primaryFilename = primaryExt.isEmpty ? resolvedStem : "\(resolvedStem).\(primaryExt)"
            let primaryTarget = session.rawFolderURL.appendingPathComponent(primaryFilename, isDirectory: false)
            let primaryBusy = fm.fileExists(atPath: primaryTarget.path)

            if let _ = unit.companionURL {
                let companionFilename = companionExt.isEmpty ? resolvedStem : "\(resolvedStem).\(companionExt)"
                let companionTarget = session.jpgFolderURL.appendingPathComponent(companionFilename, isDirectory: false)
                if !primaryBusy && !fm.fileExists(atPath: companionTarget.path) {
                    return (primaryTarget, companionTarget)
                }
            } else if !primaryBusy {
                return (primaryTarget, nil)
            }

            suffix += 1
        }
    }

    private static func performFileTransfer(
        from sourceURL: URL,
        to destinationURL: URL,
        mode: FolderImportTransferMode,
        fileManager fm: FileManager
    ) throws {
        switch mode {
        case .copy:
            try fm.copyItem(at: sourceURL, to: destinationURL)
        case .move:
            try fm.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func transferXMPSidecarIfPresent(
        from sourcePrimary: URL,
        to destinationPrimary: URL,
        mode: FolderImportTransferMode,
        fileManager fm: FileManager
    ) {
        let sourceXMP = PhotoTagStore.xmpSidecarURL(for: sourcePrimary)
        guard fm.fileExists(atPath: sourceXMP.path) else { return }
        let destXMP = PhotoTagStore.xmpSidecarURL(for: destinationPrimary)
        try? fm.removeItem(at: destXMP)
        try? performFileTransfer(from: sourceXMP, to: destXMP, mode: mode, fileManager: fm)
    }
}
