import Foundation

/// Centralizes sandbox-aware vault file locations and relative-path helpers.
final class VaultStorage {
    private let fileManager = FileManager.default
    private(set) var baseURL: URL {
        didSet { configureDerivedPaths() }
    }

    private(set) var photosDirectory: URL
    private(set) var settingsFile: URL
    private(set) var metadataFile: URL

    init(baseURL: URL? = nil) {
        let resolvedBase = baseURL ?? VaultStorage.defaultBaseURL()
        self.baseURL = resolvedBase
        self.photosDirectory = resolvedBase.appendingPathComponent(FileConstants.photosDirectoryName, isDirectory: true)
        self.settingsFile = resolvedBase.appendingPathComponent(FileConstants.settingsFileName)
        self.metadataFile = resolvedBase.appendingPathComponent(FileConstants.photosMetadataFileName)

        ensureDirectoryExists(resolvedBase)
        ensureDirectoryExists(photosDirectory)

        if baseURL == nil {
            migrateLegacyVaultIfPossible()
        }
    }

    func updateBaseURL(_ newURL: URL) {
        baseURL = newURL
        ensureDirectoryExists(baseURL)
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

    private func configureDerivedPaths() {
        photosDirectory = baseURL.appendingPathComponent(FileConstants.photosDirectoryName, isDirectory: true)
        settingsFile = baseURL.appendingPathComponent(FileConstants.settingsFileName)
        metadataFile = baseURL.appendingPathComponent(FileConstants.photosMetadataFileName)
    }

    private func ensureDirectoryExists(_ url: URL) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
                print("VaultStorage: Failed to ensure directory exists at \(url.path): \(error)")
            #endif
        }
    }

    private func migrateLegacyVaultIfPossible() {
        guard let legacyURL = VaultStorage.locateLegacyVault(),
              legacyURL.standardizedFileURL.path != baseURL.standardizedFileURL.path else {
            return
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: legacyURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        do {
            let legacyContents = try fileManager.contentsOfDirectory(at: legacyURL, includingPropertiesForKeys: nil)
            for item in legacyContents {
                let destination = baseURL.appendingPathComponent(item.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) { continue }
                try fileManager.copyItem(at: item, to: destination)
            }
            #if DEBUG
                print("VaultStorage: Copied legacy vault from \(legacyURL.path) to \(baseURL.path)")
            #endif
        } catch {
            #if DEBUG
                print("VaultStorage: Failed to migrate legacy data: \(error)")
            #endif
        }
    }

    private static func defaultBaseURL() -> URL {
        #if os(iOS)
            let fm = FileManager.default
            if let iCloudURL = fm.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
                return iCloudURL.appendingPathComponent("SecretVault", isDirectory: true)
            }
            guard let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                fatalError("Unable to locate documents directory")
            }
            return documentsURL.appendingPathComponent("SecretVault", isDirectory: true)
        #else
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            return appSupport.appendingPathComponent("SecretVault", isDirectory: true)
        #endif
    }

    private static func locateLegacyVault() -> URL? {
        if let stored = storedLegacyBaseURL() {
            return stored
        }

        #if os(macOS)
            let home = FileManager.default.homeDirectoryForCurrentUser
            let candidates = [
                home.appendingPathComponent("Library/Application Support/SecretVault", isDirectory: true),
                home.appendingPathComponent("Documents/SecretVault", isDirectory: true)
            ]
        #else
            var candidates: [URL] = []
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                candidates.append(docs.appendingPathComponent("SecretVault", isDirectory: true))
            }
            if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
                candidates.append(library.appendingPathComponent("SecretVault", isDirectory: true))
            }
        #endif

        for url in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }

        return nil
    }

    private static func storedLegacyBaseURL() -> URL? {
        guard let settingsURL = legacySettingsFileURL(),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode([String: String].self, from: data),
              let basePath = settings["vaultBaseURL"], !basePath.isEmpty else {
            return nil
        }

        let candidate = URL(fileURLWithPath: basePath, isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        return nil
    }

    private static func legacySettingsFileURL() -> URL? {
        #if os(macOS)
            let home = FileManager.default.homeDirectoryForCurrentUser
            let base = home.appendingPathComponent("Library/Application Support/SecretVault", isDirectory: true)
            return base.appendingPathComponent(FileConstants.settingsFileName)
        #else
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            let base = documentsURL.appendingPathComponent("SecretVault", isDirectory: true)
            return base.appendingPathComponent(FileConstants.settingsFileName)
        #endif
    }
}
