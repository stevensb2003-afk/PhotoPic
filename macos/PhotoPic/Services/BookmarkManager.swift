import AppKit
import Foundation

/// Manages permanent disk access to the user's Global Root Folder via
/// Security-Scoped Bookmarks persisted in UserDefaults.
@MainActor
package final class BookmarkManager {
    private enum StorageKey {
        static let rootBookmark = "com.kairosvisuals.photopic.rootFolderBookmark"
        static let rootPathFallback = "com.kairosvisuals.photopic.rootFolderPath"
    }

    private let defaults: UserDefaults
    private var activeScopedURL: URL?

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package var hasConfiguredRootFolder: Bool {
        defaults.data(forKey: StorageKey.rootBookmark) != nil
            || defaults.string(forKey: StorageKey.rootPathFallback) != nil
    }

    /// Presents a native macOS NSOpenPanel to select (or create) the Global Root Folder.
    package func presentRootFolderPicker(suggestedName: String = "Sesiones_Tether") -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Elegir Carpeta Raíz Global"
        panel.message = "PhotoPic creará subcarpetas por sesión (RAW, JPG, Para_Edicion, Archivadas) aquí."
        panel.prompt = "Usar esta carpeta"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            let suggested = pictures.appendingPathComponent(suggestedName, isDirectory: true)
            panel.directoryURL = FileManager.default.fileExists(atPath: suggested.path) ? suggested : pictures
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }

        saveBookmark(for: selectedURL)
        return resolveRootFolderURL() ?? selectedURL
    }

    /// Saves a Security-Scoped Bookmark (falling back gracefully to path persistence if unentitled).
    package func saveBookmark(for url: URL) {
        stopCurrentAccess()
        defaults.set(url.standardizedFileURL.path, forKey: StorageKey.rootPathFallback)

        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(data, forKey: StorageKey.rootBookmark)
        }
    }

    /// Resolves and activates security-scoped access to the persisted Global Root Folder.
    package func resolveRootFolderURL() -> URL? {
        if let activeScopedURL, FileManager.default.fileExists(atPath: activeScopedURL.path) {
            return activeScopedURL
        }

        if let bookmarkData = defaults.data(forKey: StorageKey.rootBookmark) {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if resolved.startAccessingSecurityScopedResource() {
                    activeScopedURL = resolved
                }
                if isStale {
                    saveBookmark(for: resolved)
                }
                if FileManager.default.fileExists(atPath: resolved.path) {
                    return resolved
                }
            }
        }

        if let fallbackPath = defaults.string(forKey: StorageKey.rootPathFallback) {
            let url = URL(fileURLWithPath: fallbackPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    package func clearRootFolder() {
        stopCurrentAccess()
        defaults.removeObject(forKey: StorageKey.rootBookmark)
        defaults.removeObject(forKey: StorageKey.rootPathFallback)
    }

    package func stopCurrentAccess() {
        activeScopedURL?.stopAccessingSecurityScopedResource()
        activeScopedURL = nil
    }
}
