import Foundation

/// Centralizes sandbox-aware album file locations and relative-path helpers.
final class AlbumStorage {
    private let fileManager = FileManager.default
    private(set) var baseURL: URL
    private(set) var photosDirectory: URL
    private(set) var settingsFile: URL
    private(set) var metadataFile: URL

    init(customBaseURL: URL? = nil) {
        let resolvedBase = customBaseURL ?? AlbumStorage.defaultBaseURL()
        self.baseURL = resolvedBase
        self.photosDirectory = resolvedBase.appendingPathComponent(FileConstants.photosDirectoryName, isDirectory: true)
        self.settingsFile = resolvedBase.appendingPathComponent(FileConstants.settingsFileName)
        self.metadataFile = resolvedBase.appendingPathComponent(FileConstants.photosMetadataFileName)

        ensureDirectoryExists(resolvedBase)
        ensureDirectoryExists(photosDirectory)
    }

    func resolvePath(_ storedPath: String) -> URL {
        guard !storedPath.isEmpty else { return baseURL }
        if storedPath.hasPrefix("/") {
            return URL(fileURLWithPath: storedPath)
        }
        return baseURL.appendingPathComponent(storedPath)
    }

    func relativePath(for url: URL) -> String {
        let normalizedBase = baseURL.standardizedFileURL.path
        let normalized = url.standardizedFileURL.path
        if normalized.hasPrefix(normalizedBase) {
            var relative = normalized.dropFirst(normalizedBase.count)
            if relative.hasPrefix("/") {
                relative = relative.dropFirst()
            }
            return relative.isEmpty ? "" : String(relative)
        }
        return normalized
    }

    func normalizedStoredPath(_ storedPath: String) -> String {
        guard !storedPath.isEmpty else { return storedPath }
        if storedPath.hasPrefix("/") {
            return relativePath(for: URL(fileURLWithPath: storedPath))
        }
        return storedPath
    }

    private func ensureDirectoryExists(_ url: URL) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
                AppLog.error("AlbumStorage: Failed to ensure directory exists at \(url.path): \(error.localizedDescription)")
            #endif
        }
    }

    private static func defaultBaseURL() -> URL {
        #if os(iOS)
            let fm = FileManager.default
            // Always use the secure Application Support directory for the album
            // This is backed up by iCloud/iTunes backups but not accessible to user via Files app
            // unless we explicitly expose it (which we don't want for a encrypted album).
            // Note: Previous versions might have used Documents.
            // For a "Encrypted" album, Application Support is better than Documents.
            // However, if we want to be super strict, we can use the Library directory.
            // Let's stick to Application Support as it's standard for app data.

            guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                fatalError("Unable to locate application support directory")
            }
            return appSupport.appendingPathComponent("EncryptedAlbum", isDirectory: true)
        #else
            // macOS: Always use the App Sandbox Container's Application Support directory
            let appSupport =
                FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                    "Library/Application Support", isDirectory: true)
            return appSupport.appendingPathComponent("EncryptedAlbum", isDirectory: true)
        #endif
    }
}
