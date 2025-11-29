import AVFoundation
import Combine
import CryptoKit
import Foundation
import ImageIO
import LocalAuthentication
import Photos
import SwiftUI

import UserNotifications
import CloudKit

// MARK: - Data Extensions

extension Data {
    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)
        var index = hexString.startIndex
        for _ in 0..<length {
            let nextIndex = hexString.index(index, offsetBy: 2)
            if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
    }
    
    /// Securely zeroes the contents of this Data buffer to prevent sensitive data from remaining in memory
    mutating func secureZero() {
        _ = withUnsafeMutableBytes { bytes in
            memset_s(bytes.baseAddress, bytes.count, 0, bytes.count)
        }
    }
    
    /// Creates a copy of the data and securely zeroes the original
    func secureCopy() -> Data {
        let copy = Data(self)
        var mutableSelf = self
        mutableSelf.secureZero()
        return copy
    }

}



// MARK: - Secure Memory Management

/// Provides secure memory management utilities for sensitive cryptographic data
class SecureMemory {
    /// Securely zeroes a buffer of bytes
    static func zero(_ buffer: UnsafeMutableRawBufferPointer) {
        memset_s(buffer.baseAddress, buffer.count, 0, buffer.count)
    }
    
    /// Securely zeroes a Data buffer
    static func zero(_ data: inout Data) {
        data.secureZero()
    }
    
    /// Allocates a secure buffer that attempts to avoid being swapped to disk
    static func allocateSecureBuffer(count: Int) -> UnsafeMutableRawBufferPointer? {
        // Use malloc to allocate memory
        let buffer = malloc(count)
        guard let ptr = buffer else { return nil }
        
        // Zero the buffer initially
        memset_s(ptr, count, 0, count)
        
        // Lock memory to prevent swapping
        if mlock(ptr, count) != 0 {
            AppLog.warning("mlock failed with error: \(errno)")
        }
        
        return UnsafeMutableRawBufferPointer(start: ptr, count: count)
    }
    
    /// Deallocates a secure buffer after zeroing it
    static func deallocateSecureBuffer(_ buffer: UnsafeMutableRawBufferPointer) {
        // Zero before deallocating
        zero(buffer)
        
        if let baseAddress = buffer.baseAddress {
            munlock(baseAddress, buffer.count)
            free(baseAddress)
        }
    }
    
}

// MARK: - Data Models

// (MediaType and MediaSource moved into SharedModels.swift)

// Restoration progress tracking
class RestorationProgress: ObservableObject {
    @Published var isRestoring = false
    @Published var totalItems = 0
    @Published var processedItems = 0
    @Published var successItems = 0
    @Published var failedItems = 0
    @Published var currentBytesProcessed: Int64 = 0
    @Published var currentBytesTotal: Int64 = 0
    @Published var statusMessage: String = ""
    @Published var detailMessage: String = ""
    @Published var cancelRequested = false
    
    var progress: Double {
        guard totalItems > 0 else { return 0 }
        return Double(processedItems) / Double(totalItems)
    }
    
    func reset() {
        isRestoring = false
        totalItems = 0
        processedItems = 0
        successItems = 0
        failedItems = 0
        currentBytesProcessed = 0
        currentBytesTotal = 0
        statusMessage = ""
        detailMessage = ""
        cancelRequested = false
    }
    
}

// Import progress tracking moved to ImportService.swift

// DirectImportProgress moved to SharedModels.swift

/// Tracks the state of file exports
@MainActor
class ExportProgress: ObservableObject {
    @Published var isExporting: Bool = false
    @Published var statusMessage: String = ""
    @Published var detailMessage: String = ""
    @Published var itemsProcessed: Int = 0
    @Published var itemsTotal: Int = 0
    @Published var bytesProcessed: Int64 = 0
    @Published var bytesTotal: Int64 = 0
    @Published var cancelRequested: Bool = false
    
    func reset(totalItems: Int) {
        isExporting = true
        statusMessage = "Preparing export…"
        detailMessage = "\(totalItems) item(s)"
        itemsProcessed = 0
        itemsTotal = totalItems
        bytesProcessed = 0
        bytesTotal = 0
        cancelRequested = false
    }
    
    func finish() {
        isExporting = false
        statusMessage = ""
        detailMessage = ""
        itemsProcessed = 0
        itemsTotal = 0
        bytesProcessed = 0
        bytesTotal = 0
        cancelRequested = false
    }
}

// (Moved shared model types into SharedModels.swift)

/// Lightweight progress tracker used by the viewer UI to expose short-lived
/// decrypting state so the toolbar/title bar can show a compact activity chip
/// while the photo/video is being decrypted for viewing.
@MainActor
class ViewerProgress: ObservableObject {
    @Published var isDecrypting: Bool = false
    @Published var statusMessage: String = ""
    @Published var bytesProcessed: Int64 = 0
    @Published var bytesTotal: Int64 = 0
    
    var percentComplete: Double {
        guard bytesTotal > 0 else { return 0 }
        return Double(bytesProcessed) / Double(bytesTotal)
    }
    
    func start(_ message: String, totalBytes: Int64 = 0) {
        isDecrypting = true
        statusMessage = message
        bytesProcessed = 0
        bytesTotal = totalBytes
    }
    
    func update(bytesProcessed: Int64) {
        self.bytesProcessed = max(0, bytesProcessed)
    }
    
    func finish() {
        isDecrypting = false
        statusMessage = ""
        bytesProcessed = 0
        bytesTotal = 0
    }
}

// MARK: - Album Manager

// Track suspension reasons used by AlbumManager and other UI code to explain why
// system sleep / auto-lock is being prevented. Placing this at module scope lets
// views (e.g. PhotoViewerSheet) refer to the cases without accessing a nested type.
public enum SleepPreventionReason: String, Hashable {
    case importing
    case viewing
    case prompt
    case other
    
    var displayName: String {
        switch self {
        case .importing: return "Importing"
        case .viewing: return "Viewing"
        case .prompt: return "Prompt"
        case .other: return "Active task"
        }
    }
}

public class AlbumManager: ObservableObject {
    @MainActor public static let shared = AlbumManager()
    
    // Services
    private let cryptoService: CryptoService
    private let fileService: FileService
    private let securityService: SecurityService
    private let passwordService: PasswordService
    private let journalService: PasswordChangeJournalService
    private let importService: ImportService
    private let albumState: AlbumState
    private let storage: AlbumStorage
    private var restorationProgressCancellable: AnyCancellable?
    private var importProgressCancellable: AnyCancellable?
    
    // Legacy properties for backward compatibility
    @Published var hiddenPhotos: [SecurePhoto] = []
    @Published var isUnlocked = false
    @Published var showUnlockPrompt = false
    /// Whether the app is currently preventing system sleep (iOS only)
    @Published var isSystemSleepPrevented: Bool = false
    
    /// Human-readable small label describing why the app is currently preventing system sleep.
    /// This is intentionally non-sensitive and kept short for UI display.
    var sleepPreventionReasonLabel: String? {
        if sleepPreventionCounts[.importing] ?? 0 > 0 { return SleepPreventionReason.importing.displayName }
        if sleepPreventionCounts[.viewing] ?? 0 > 0 { return SleepPreventionReason.viewing.displayName }
        if sleepPreventionCounts[.prompt] ?? 0 > 0 { return SleepPreventionReason.prompt.displayName }
        if sleepPreventionCounts[.other] ?? 0 > 0 { return SleepPreventionReason.other.displayName }
        // If no suspension reasons, but the unlocked preference keeps awake, indicate 'Unlocked'
        let keepAwakeWhileUnlocked = UserDefaults.standard.bool(forKey: "keepScreenAwakeWhileUnlocked")
        if isUnlocked && keepAwakeWhileUnlocked { return "Unlocked" }
        return nil
    }
    @Published var passwordHash: String = ""
    @Published var passwordSalt: String = ""  // Salt for password hashing
    @Published var securityVersion: Int = 1  // 1 = Legacy (Key as Hash), 2 = Secure (Verifier)
    @Published var restorationProgress = RestorationProgress()
    @Published var importProgress = ImportProgress()
    @MainActor let directImportProgress: DirectImportProgress
    @MainActor let exportProgress = ExportProgress()
    @MainActor let viewerProgress = ViewerProgress()
    private var directImportTask: Task<Void, Never>?
    var exportTask: Task<Void, Never>?
    
    // Album location is now fixed and managed by AlbumStorage
    var albumBaseURL: URL {
        return storage.baseURL
    }
    
    @Published var hideNotification: HideNotification? = nil
    @Published var lastActivity: Date = Date()
    @Published var viewRefreshId = UUID()  // Force view refresh when needed
    @Published var secureDeletionEnabled: Bool = true  // Default to true for security
    @Published var autoRemoveDuplicatesOnImport: Bool = true  // Default to true for convenience
    @Published var enableImportNotifications: Bool = true  // Default to true for user feedback
    @Published var autoLockTimeoutSeconds: Double = CryptoConstants.idleTimeout
    @Published var requirePasscodeOnLaunch: Bool = false
    @Published var biometricPolicy: String = "biometrics_preferred"
    @Published var appTheme: String = "default"
    @Published var compactLayoutEnabled: Bool = false
    @Published var accentColorName: String = "blue"
    
    /// Resolved accent color used by the UI. This maps the persisted name to a `Color` value
    /// that's safe to use from SwiftUI views. Use this value from top-level views to apply
    /// the user's chosen accent across the app.
    var accentColorResolved: Color {
        switch accentColorName.lowercased() {
        case "green":
            return Color.green
        case "pink":
            return Color.pink
        case "winamp":
            // Nostalgic Winamp-y accent tone
            return Color(red: 0.98, green: 0.6, blue: 0.07)
        case "system":
            // Defer to system / asset catalog accent where applicable
            return Color.accentColor
        default:
            // default to blue
            return Color.blue
        }
    }
    
    /// Machine-friendly identifier for the currently selected accent color.
    /// Useful for tests and logic that don't depend on SwiftUI `Color` equality.
    enum AccentColorId: String {
        case blue, green, pink, winamp, system
    }
    
    var accentColorId: AccentColorId {
        return AccentColorId(rawValue: accentColorName.lowercased()) ?? .blue
    }
    // NOTE: saving captures directly to the system Photos library from in-app
    // capture flows is not permitted by app policy. All captures must be
    // stored in the encrypted album or queued while locked. The old
    // `cameraSaveToAlbumDirectly` preference was removed for safety.
    @Published var cameraMaxQuality: Bool = true
    @Published var cameraAutoRemoveFromPhotos: Bool = false
    @Published var authenticationPromptActive: Bool = false
    @Published var isLoading: Bool = true
    @Published var isDecoyMode: Bool = false
    /// When true, do not auto-trigger biometric prompts for the next unlock screen—used to avoid
    /// immediately prompting biometrics right after the user manually locked the album.
    @Published var suppressAutoBiometricAfterManualLock: Bool = false
    // New settings implemented: security, backups, privacy and telemetry toggles
    @Published var autoWipeOnFailedAttemptsEnabled: Bool = false
    @Published var autoWipeFailedAttemptsThreshold: Int = 10
    @Published var requireReauthForExports: Bool = true
    @Published var backupSchedule: String = "manual" // manual | weekly | monthly
    @Published var encryptedCloudSyncEnabled: Bool = false
    @Published var lastCloudSync: Date? = nil
    
    enum CloudSyncStatus: String {
        case idle
        case syncing
        case failed
        case notAvailable
    }
    
    @Published var cloudSyncStatus: CloudSyncStatus = .idle
    @Published var cloudSyncErrorMessage: String? = nil
    
    @Published var lastCloudVerification: Date? = nil
    enum CloudVerificationStatus: String {
        case unknown
        case success
        case failed
        case notAvailable
    }
    @Published var cloudVerificationStatus: CloudVerificationStatus = .unknown
    @Published var thumbnailPrivacy: String = "blur" // none | blur | hide
    @Published var stripMetadataOnExport: Bool = true
    @Published var exportPasswordProtect: Bool = true
    @Published var exportExpiryDays: Int = 30
    @Published var enableVerboseLogging: Bool = false
    @Published var telemetryEnabled: Bool = false
    /// When enabled, 'Lockdown Mode' restricts network, import/export and other risky operations
    /// to minimize attack surface and data leakage.
    @Published var lockdownModeEnabled: Bool = false
    @Published var passphraseMinLength: Int = 8
    @Published var enableRecoveryKey: Bool = false
    
    // Queue for imports that arrive while the album is locked
    private var pendingImportURLs: [URL] = []
    // Queue for captures taken while the album is locked
    private struct PendingCapture: Codable {
        let url: URL
        let filename: String
        let dateTaken: Date?
        let sourceAlbum: String?
        let mediaType: MediaType
        let duration: TimeInterval?
        // location & isFavorite are intentionally omitted from persistence for now
    }
    
    private var pendingCapturedMedia: [PendingCapture] = []
    
    private var pendingCapturedFileURL: URL {
        return storage.baseURL.appendingPathComponent("pending_captures.json")
    }
    
    private func loadPendingCapturedMedia() {
        albumQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? Data(contentsOf: self.pendingCapturedFileURL) else { return }
            do {
                let list = try JSONDecoder().decode([PendingCapture].self, from: data)
                self.pendingCapturedMedia = list
                AppLog.debugPrivate("Loaded \(list.count) pending captured media items from disk")
            } catch {
                AppLog.debugPrivate("Failed to decode pending captures: \(error.localizedDescription)")
            }
        }
    }
    
    private func savePendingCapturedMedia() {
        albumQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(self.pendingCapturedMedia)
                try data.write(to: self.pendingCapturedFileURL, options: .atomic)
                AppLog.debugPrivate("Saved \(self.pendingCapturedMedia.count) pending captured media items to disk")
            } catch {
                AppLog.error("Failed to save pending captured media: \(error.localizedDescription)")
            }
        }
    }
    
    var isBusy: Bool {
        return importProgress.isImporting || restorationProgress.isRestoring
    }
    
    /// Idle timeout in seconds before automatically locking the album when unlocked.
    /// Default is taken from `autoLockTimeoutSeconds` (initially CryptoConstants.idleTimeout).
    var idleTimeout: TimeInterval { return autoLockTimeoutSeconds }
    
    // Rate limiting for unlock attempts
    private var failedUnlockAttempts: Int = 0
    private var lastUnlockAttemptTime: Date?
    private var failedBiometricAttempts: Int = 0
    private let maxBiometricAttempts: Int = CryptoConstants.biometricMaxAttempts
    
    private var photosDirectoryURL: URL { storage.photosDirectory }
    private var photosMetadataFileURL: URL { storage.metadataFile }
    private var settingsFileURL: URL { storage.settingsFile }
    private func resolveURL(for storedPath: String) -> URL { storage.resolvePath(storedPath) }
    
    /// Public helper used by UI components to resolve stored paths to file URLs.
    func urlForStoredPath(_ storedPath: String) -> URL { resolveURL(for: storedPath) }
    private func relativePath(for absoluteURL: URL) -> String { storage.relativePath(for: absoluteURL) }
    private func normalizedStoredPath(_ storedPath: String) -> String { storage.normalizedStoredPath(storedPath) }
    private var idleTimer: Timer?
    private var idleTimerSuspendCount: Int = 0
    
    // Track suspension reasons used by AlbumManager and other UI code to explain why
    // system sleep / auto-lock is being prevented. This enum is intentionally at
    // module scope so views (e.g. PhotoViewerSheet) can refer to the cases.
    private var sleepPreventionCounts: [SleepPreventionReason: Int] = [:]
    
    // Serial queue for thread-safe operations
    private let albumQueue = DispatchQueue(label: "biz.front-end.encryptedalbum.albumQueue", qos: .userInitiated)
    
    // Derived keys cache (in-memory only, never persisted)
    private var cachedMasterKey: SymmetricKey?
    private var cachedEncryptionKey: SymmetricKey?
    private var cachedHMACKey: SymmetricKey?
    
    // Helper to detect if we are running unit tests
    private var isRunningUnitTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    @MainActor
    init(storage: AlbumStorage? = nil, importService: ImportService? = nil) {
        
        let progress = ImportProgress()
        self.directImportProgress = DirectImportProgress()
        // Allow tests to inject a mock ImportService when needed.
        if let importService = importService {
            self.importService = importService
        } else {
            self.importService = ImportService(progress: progress)
        }
        
        // Initialize services
        cryptoService = CryptoService()
        securityService = SecurityService(cryptoService: cryptoService)
        passwordService = PasswordService(cryptoService: cryptoService, securityService: securityService)
        journalService = PasswordChangeJournalService()
        fileService = FileService(cryptoService: cryptoService)
        albumState = AlbumState()
        self.storage = storage ?? AlbumStorage()
        
        self.importProgress = progress
        // Load any previously queued captured media that survived a restart
        loadPendingCapturedMedia()
        
        
        fileService.cleanupTemporaryArtifacts()
        // albumBaseURL is now computed from storage.baseURL
        
#if DEBUG
        AppLog.debugPrivate("DEBUG: CommandLine arguments: \(CommandLine.arguments)")
        let confirmEnv = ProcessInfo.processInfo.environment["ALLOW_DESTRUCTIVE_RESET"]
        if CommandLine.arguments.contains("--reset-state") && confirmEnv == "1" {
            AppLog.warning("Destructive reset requested … Proceeding to nuke all data.")
            self.nukeAllData()
        }
#endif
        
        
        AppLog.debugPrivate("Loading settings from: \(settingsFileURL.path)")
        
        // Register sensible defaults for runtime-only UI preferences so tests and fresh
        // installs have predictable behaviour. These mirror the defaults exposed in
        // PreferencesView.
        UserDefaults.standard.register(defaults: [
            "keepScreenAwakeWhileUnlocked": false,
            "keepScreenAwakeDuringSuspensions": true,
        ])
        
        // Load settings asynchronously to ensure state is ready before init completes
        Task {
            await self.loadSettings()
        }
        
        restorationProgressCancellable = restorationProgress.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        importProgressCancellable = importProgress.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Settings loaded, checking password status
        // Moved to loadSettings completion
    }
    
    // MARK: - Step-up Authentication
    
    /// Performs a step-up authentication check for sensitive album operations.
    /// Uses biometrics/device auth when available, otherwise falls back to password verification
    /// using the same salted-hash verification as the main unlock flow.
    func requireStepUpAuthentication(completion: @escaping (Bool) -> Void) {
        // If there is no password yet, no need for step-up auth.
        guard !passwordHash.isEmpty else {
            completion(true)
            return
        }
        
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Authenticate to perform a sensitive album operation."
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            // Fall back to password entry via a SwiftUI alert (platform-agnostic)
            DispatchQueue.main.async {
                // This will need to be handled by the UI layer
                // For now, we'll show a simple alert if possible
#if os(macOS)
                let alert = NSAlert()
                alert.messageText = "Authenticate to Continue"
                alert.informativeText =
                "Enter your EncryptedAlbum password to proceed with this sensitive operation."
                alert.alertStyle = .warning
                
                let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
                textField.placeholderString = "Album Password"
                alert.accessoryView = textField
                
                alert.addButton(withTitle: "Continue")
                alert.addButton(withTitle: "Cancel")
                
                let response = alert.runModal()
                guard response == .alertFirstButtonReturn else {
                    completion(false)
                    return
                }
                
                let enteredPassword = textField.stringValue
                
                // Reuse the same salted hashing logic as `unlock(password:)` so that
                // step-up authentication behaves identically to a normal unlock.
                guard let passwordData = enteredPassword.data(using: .utf8),
                      let saltData = Data(base64Encoded: self.passwordSalt)
                else {
                    completion(false)
                    return
                }
                
                var combinedData = Data()
                combinedData.append(passwordData)
                combinedData.append(saltData)
                let hash = SHA256.hash(data: combinedData)
                let enteredHash = hash.compactMap { String(format: "%02x", $0) }.joined()
                completion(enteredHash == self.passwordHash)
#else
                // On iOS, we'll need to use a different approach - perhaps a modal view
                // For now, just fail the authentication
                completion(false)
#endif
            }
        }
    }
    
    // MARK: - Password Management
    
    /// Sets up the album password with proper validation and secure hashing.
    /// - Parameter password: The password to set (must be 8-128 characters)
    /// - Returns: `true` on success, `false` if validation fails
    func setupPassword(_ password: String) async throws {
        // Verify system entropy before generating keys
        let health = try await securityService.performSecurityHealthCheck()
        guard health.randomGenerationHealthy else {
            throw AlbumError.securityHealthCheckFailed(reason: "Insufficient system entropy for secure key generation")
        }
        
        try passwordService.validatePassword(password)
        
        let (hash, salt) = try await passwordService.hashPassword(password)
        try await passwordService.storePasswordHash(hash, salt: salt)
        
        await MainActor.run {
            passwordHash = hash.map { String(format: "%02x", $0) }.joined()
            passwordSalt = salt.base64EncodedString()
            securityVersion = 2  // New setups are always V2
            
            cachedMasterKey = nil
            cachedEncryptionKey = nil
            cachedHMACKey = nil
            saveSettings()
            UserDefaults.standard.set(true, forKey: "biometricConfigured")
        }
        
        // Store password for biometric unlock
        await saveBiometricPassword(password)
        
#if os(iOS)
        // Respect lockdown state - do not attempt cloud/network operations.
        if lockdownModeEnabled {
            cloudSyncStatus = .failed
            lastCloudSync = Date()
            return
        }
        // On iOS, verify biometric storage by attempting to retrieve it
        // This triggers Face ID prompt immediately to confirm biometric works
        if !isRunningUnitTests {
            if await getBiometricPassword() == nil {
                throw AlbumError.biometricFailed
            }
        }
#endif
    }
    
    /// Attempts to unlock the album with the provided password.
    /// - Parameter password: The password to verify
    /// - Returns: `true` if unlock successful, `false` otherwise
    func unlock(password: String) async throws {
        // Rate limiting: exponential backoff on failed attempts
        if failedUnlockAttempts > 0, let lastAttempt = lastUnlockAttemptTime {
            let requiredDelay = calculateUnlockDelay()
            let elapsed = Date().timeIntervalSince(lastAttempt)
            
            if elapsed < requiredDelay {
                let remaining = Int(requiredDelay - elapsed)
                throw AlbumError.rateLimitExceeded(retryAfter: TimeInterval(remaining))
            }
        }
        
        lastUnlockAttemptTime = Date()
        
        // Check for Decoy Password first
        if let decoyHash = UserDefaults.standard.string(forKey: "decoyPasswordHash"), !decoyHash.isEmpty {
            let inputHash = SHA256.hash(data: password.data(using: .utf8)!).compactMap { String(format: "%02x", $0) }
                .joined()
            if inputHash == decoyHash {
                await MainActor.run {
                    isDecoyMode = true
                    isUnlocked = true
                    hiddenPhotos = generateFakePhotos()  // Populate with fake photos instead of empty
                    lastActivity = Date()
                }
                startIdleTimer()
                return
            }
        }
        
        // Verify password
        guard let (storedHash, storedSalt) = try await passwordService.retrievePasswordCredentials() else {
            failedUnlockAttempts += 1
            throw AlbumError.albumNotInitialized
        }
        
        // Check security version and verify accordingly
        let isValid: Bool
        if securityVersion < 2 {
            // Legacy verification (V1)
            isValid = try await passwordService.verifyLegacyPassword(password, against: storedHash, salt: storedSalt)
            
            if isValid {
                // MIGRATE TO V2
                let (newVerifier, _) = try await passwordService.hashPassword(password)  // Uses new verifier logic
                // Salt remains the same to avoid re-encrypting data (we just change the stored verifier)
                try await passwordService.storePasswordHash(newVerifier, salt: storedSalt)
                
                await MainActor.run {
                    self.passwordHash = newVerifier.map { String(format: "%02x", $0) }.joined()
                    self.securityVersion = 2
                }
                saveSettings()
            }
        } else {
            // Standard verification (V2)
            isValid = try await passwordService.verifyPassword(password, against: storedHash, salt: storedSalt)
        }
        
        if isValid {
            // Success - reset counters and derive keys
            failedUnlockAttempts = 0
            failedBiometricAttempts = 0
            
            // Derive keys for this session
            let (encryptionKey, hmacKey) = try await cryptoService.deriveKeys(password: password, salt: storedSalt)
            cachedEncryptionKey = encryptionKey
            cachedHMACKey = hmacKey
            
            // Self-healing: Ensure biometric password is saved if missing
            // This fixes issues where the biometric item might have been lost or not saved correctly
            // On iOS, checking if the password exists requires Face ID, so skip this check there
            // unless we believe it should be configured but isn't.
#if os(macOS)
            if await !securityService.biometricPasswordExists() {
                await saveBiometricPassword(password)
            }
#else
            // On iOS, avoid checking keychain (triggers prompt). Only save if we think it's not configured.
            if !UserDefaults.standard.bool(forKey: "biometricConfigured") {
                await saveBiometricPassword(password)
                UserDefaults.standard.set(true, forKey: "biometricConfigured")
            }
#endif
            
            await MainActor.run {
                isUnlocked = true
                
                // Process any queued imports
                if !pendingImportURLs.isEmpty {
                    AppLog.debugPublic("Processing \(pendingImportURLs.count) queued import items...")
                    let urlsToImport = pendingImportURLs
                    pendingImportURLs.removeAll()
                    // Small delay to ensure UI transition completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.startDirectImport(urls: urlsToImport)
                    }
                }
                
                if !pendingCapturedMedia.isEmpty {
                    AppLog.debugPublic("Processing \(pendingCapturedMedia.count) queued captured media items...")
                    let capturesToProcess = pendingCapturedMedia
                    pendingCapturedMedia.removeAll()
                    // Persist the cleared pending captures so a restart doesn't re-process stale entries
                    self.savePendingCapturedMedia()
                    
                    // Slight delay to ensure the unlock transition has completed in the UI
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let strong = self else { return }
                        Task {
                            for cap in capturesToProcess {
                                do {
                                    try await strong.hidePhoto(
                                        mediaSource: .fileURL(cap.url),
                                        filename: cap.filename,
                                        dateTaken: cap.dateTaken,
                                        sourceAlbum: cap.sourceAlbum,
                                        assetIdentifier: nil,
                                        mediaType: cap.mediaType,
                                        duration: cap.duration,
                                        location: nil,
                                        isFavorite: nil,
                                        progressHandler: nil
                                    )
                                } catch {
                                    AppLog.error("Failed to hide queued captured media \(cap.filename): \(error.localizedDescription)")
                                }
                                
                                // Attempt to remove the temp file regardless
                                try? FileManager.default.removeItem(at: cap.url)
                            }
                        }
                    }
                }
            }
            try await loadPhotos()
            await MainActor.run {
                lastActivity = Date()
            }
            startIdleTimer()
#if os(iOS)
            // After a successful unlock, recompute system idle state using consolidated logic.
            await updateSystemIdleState()
#endif
            
            // Update legacy properties for backward compatibility
            await MainActor.run {
                // If we just migrated, passwordHash is already updated above.
                // If not, we update it here just in case.
                if securityVersion >= 2 {
                    // In V2, storedHash is the verifier, which is safe to expose to UI if needed (though ideally we wouldn't)
                }
                passwordSalt = storedSalt.base64EncodedString()
            }
            
            // Save updated settings to disk
            await MainActor.run {
                saveSettings()
            }
        } else {
            failedUnlockAttempts += 1
            throw AlbumError.invalidPassword
        }
    }
    
    /// Changes the album password and re-encrypts all data.
    /// - Parameters:
    ///   - currentPassword: Current password for verification
    ///   - newPassword: New password to set
    ///   - progressHandler: Optional callback with progress updates
    func changePassword(currentPassword: String, newPassword: String, progressHandler: ((String) -> Void)? = nil)
    async throws
    {
        await MainActor.run { lastActivity = Date() }
        
        // Verify system entropy before generating new keys
        let health = try await securityService.performSecurityHealthCheck()
        guard health.randomGenerationHealthy else {
            throw AlbumError.securityHealthCheckFailed(reason: "Insufficient system entropy for secure key generation")
        }
        
        // 1. Prepare: Verify old password and generate new keys
        progressHandler?("Verifying and generating keys...")
        let (newVerifier, newSalt, newEncryptionKey, newHMACKey) = try await passwordService.preparePasswordChange(
            currentPassword: currentPassword,
            newPassword: newPassword
        )
        
        guard let oldEncryptionKey = cachedEncryptionKey, let oldHMACKey = cachedHMACKey else {
            throw AlbumError.albumNotInitialized
        }
        
        // 2. Initialize or Resume Journal
        let photos = hiddenPhotos  // Capture current list
        let total = photos.count
        
        // Calculate hash prefixes for verification
        let oldHashPrefix = String(passwordHash.prefix(8))
        let newHashPrefix = String(newVerifier.map { String(format: "%02x", $0) }.joined().prefix(8))
        
        // Encrypt the new key with the old key for recovery
        let newKeyData = newEncryptionKey.withUnsafeBytes { Data($0) }
        // Use a simple seal (nonce + ciphertext + tag)
        let sealedBox = try AES.GCM.seal(newKeyData, using: oldEncryptionKey)
        let encryptedNewKey = sealedBox.combined!
        
        var journal: PasswordChangeJournal
        
        // Check for existing journal to resume
        if let existingJournal = try? journalService.readJournal(from: albumBaseURL),
           existingJournal.status != .completed,
           existingJournal.oldPasswordHashPrefix == oldHashPrefix,
           existingJournal.newPasswordHashPrefix == newHashPrefix
        {
            
            progressHandler?("Resuming interrupted password change...")
            journal = existingJournal
            
            // If we are resuming, we might have more files now than before, or fewer.
            // Ideally we should respect the journal's state, but for simplicity in this monolithic structure,
            // we'll just use the current list and skip what's marked as processed.
        } else {
            // Start fresh
            journal = PasswordChangeJournal(
                oldPasswordHashPrefix: oldHashPrefix,
                newPasswordHashPrefix: newHashPrefix,
                newSalt: newSalt,
                encryptedNewKey: encryptedNewKey,
                totalFiles: total
            )
            try journalService.writeJournal(journal, to: albumBaseURL)
        }
        
        // 3. Re-encrypt all photos
        do {
            for (index, photo) in photos.enumerated() {
                let encryptedURL = resolveURL(for: photo.encryptedDataPath)
                let filename = encryptedURL.lastPathComponent
                
                // Skip if already processed (in case of resume logic, though this is a fresh start)
                if journal.isProcessed(filename) {
                    continue
                }
                
                progressHandler?("Re-encrypting item \(index + 1) of \(total)...")
                
                let photosDir = photosDirectoryURL
                
                // Re-encrypt main file
                try await fileService.reEncryptFile(
                    filename: filename,
                    directory: photosDir,
                    mediaType: photo.mediaType,
                    oldEncryptionKey: oldEncryptionKey,
                    oldHMACKey: oldHMACKey,
                    newEncryptionKey: newEncryptionKey,
                    newHMACKey: newHMACKey
                )
                
                // Re-encrypt thumbnail
                let thumbSourcePath = photo.encryptedThumbnailPath ?? photo.thumbnailPath
                let thumbURL = resolveURL(for: thumbSourcePath)
                let thumbFilename = thumbURL.lastPathComponent
                // Check if it's actually an encrypted thumbnail (ends in .enc)
                if thumbFilename.hasSuffix(FileConstants.encryptedFileExtension) {
                    try await fileService.reEncryptFile(
                        filename: thumbFilename,
                        directory: photosDir,
                        mediaType: .photo,  // Thumbnails are always images
                        oldEncryptionKey: oldEncryptionKey,
                        oldHMACKey: oldHMACKey,
                        newEncryptionKey: newEncryptionKey,
                        newHMACKey: newHMACKey
                    )
                }
                
                // Update Journal
                journal.markProcessed(filename)
                try journalService.writeJournal(journal, to: albumBaseURL)
            }
        } catch {
            // If any error occurs during re-encryption, mark journal as failed so we can recover later
            journal.status = .failed
            try? journalService.writeJournal(journal, to: albumBaseURL)
            throw error
        }
        
        // 4. Commit: Store new password verifier and salt
        progressHandler?("Saving new password...")
        try await passwordService.storePasswordHash(newVerifier, salt: newSalt)
        
        // 5. Update local state
        await MainActor.run {
            self.passwordHash = newVerifier.map { String(format: "%02x", $0) }.joined()
            self.passwordSalt = newSalt.base64EncodedString()
            self.securityVersion = 2
        }
        
        // 6. Update cached keys & Save settings
        await MainActor.run {
            cachedEncryptionKey = newEncryptionKey
            cachedHMACKey = newHMACKey
            
            saveSettings()
        }
        
        // 7. Update biometric password
        await saveBiometricPassword(newPassword)
        
        // 8. Cleanup Journal
        try journalService.deleteJournal(from: albumBaseURL)
        
        progressHandler?("Password changed successfully")
    }
    
    /// Checks if a password change operation was interrupted and needs recovery.
    /// - Returns: The journal if an interrupted operation exists, nil otherwise.
    func checkForInterruptedPasswordChange() -> PasswordChangeJournal? {
        guard let journal = try? journalService.readJournal(from: albumBaseURL) else {
            return nil
        }
        
        // Only return if it's in progress or failed
        if journal.status == .inProgress || journal.status == .failed {
            return journal
        }
        
        return nil
    }
    
    func hasPassword() -> Bool {
        return !passwordHash.isEmpty
    }
    
    /// Calculates the required delay before allowing another unlock attempt based on failed attempts
    private func calculateUnlockDelay() -> TimeInterval {
        let baseDelay = CryptoConstants.rateLimitBaseDelay
        let maxDelay = CryptoConstants.rateLimitMaxDelay
        
        // Exponential backoff: baseDelay ^ failedAttempts, capped at maxDelay
        let delay = min(pow(baseDelay, Double(failedUnlockAttempts)), maxDelay)
        return delay
    }
    
    /// Locks the album by clearing cached keys and resetting state
    /// Locks the album. If `userInitiated` is true, we set a suppression flag that prevents
    /// the unlock UI from auto-triggering biometrics (Face ID/Touch ID) until the user performs
    /// an explicit unlock action. Automatic/idle locks do not set this flag.
    func lock(userInitiated: Bool = false) {
        // Set suppression flag synchronously on main thread so UI sees it immediately.
        if userInitiated {
            // Ensure the suppression flag is set synchronously so the unlock screen
            // will immediately see it and avoid auto-triggering biometrics.
            // This ensures the flag is set before any UI updates.
            if Thread.isMainThread {
                self.suppressAutoBiometricAfterManualLock = true
            } else {
                DispatchQueue.main.sync {
                    self.suppressAutoBiometricAfterManualLock = true
                }
            }
        }
        
        if Thread.isMainThread {
            performLock()
        } else {
            DispatchQueue.main.async {
                self.performLock()
            }
        }
    }
    
    private func performLock() {
        cachedMasterKey = nil
        cachedEncryptionKey = nil
        cachedHMACKey = nil
        isUnlocked = false
        isDecoyMode = false
        startIdleTimer()
#if os(iOS)
        // Respect lockdown state - do not attempt cloud/network operations.
        if lockdownModeEnabled {
            cloudVerificationStatus = .failed
            lastCloudVerification = Date()
            return
        }
        // Recompute system idle state when locking — prefer centralized logic.
        // performLock may be called from non-main contexts; ensure the MainActor runs the update.
        Task { @MainActor in self.updateSystemIdleState() }
#endif
    }
    
    /// After user performs a deliberate unlock action (biometric or password attempt), clear
    /// the suppression so subsequent unlock screens may auto-attempt biometrics again.
    func clearSuppressAutoBiometric() {
        // Mirror the synchronous behaviour used in `lock(userInitiated:)` so callers
        // that expect an immediate change (for example tests running on the main actor)
        // observe the flag change synchronously.
        if Thread.isMainThread {
            self.suppressAutoBiometricAfterManualLock = false
        } else {
            DispatchQueue.main.sync { self.suppressAutoBiometricAfterManualLock = false }
        }
    }
    
    /// Clears transient UI state and temporary files when the app is heading into the background.
    func prepareForBackground() {
        albumQueue.async { [weak self] in
            self?.fileService.cleanupTemporaryArtifacts()
        }
        
        DispatchQueue.main.async {
            self.hideNotification = nil
            self.viewRefreshId = UUID()
        }
    }
    
    /// Starts or restarts the idle timer that auto-locks after `idleTimeout`.
    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            guard self.isUnlocked else {
                timer.invalidate()
                self.idleTimer = nil
                return
            }
            
            // Skip idle check if timer is suspended (e.g., during imports)
            if self.idleTimerSuspendCount > 0 {
                AppLog.debugPublic("Idle timer check skipped (suspended)")
                return
            }
            
            let elapsed = Date().timeIntervalSince(self.lastActivity)
            if elapsed > self.idleTimeout {
                AppLog.debugPublic("Auto-locking album after \(Int(elapsed))s of inactivity")
                self.lock()
            }
        }
        if let idleTimer = idleTimer {
            RunLoop.main.add(idleTimer, forMode: .common)
        }
    }
    
    /// Suspends the idle timer to prevent auto-lock during long operations (e.g., imports)
    /// A reason may be supplied so the UI can surface why the device is being kept awake.
    @MainActor
    func suspendIdleTimer(reason: SleepPreventionReason = .other) {
        idleTimerSuspendCount += 1
        sleepPreventionCounts[reason, default: 0] += 1
        if idleTimerSuspendCount == 1 {
            AppLog.debugPublic("Idle timer SUSPENDED - album will not auto-lock")
        } else {
            AppLog.debugPublic("Idle timer suspension depth now \(idleTimerSuspendCount)")
        }
        
        // Recompute system idle policy given current reasons and user preferences
        updateSystemIdleState()
    }
    
    /// Resumes the idle timer after long operations complete
    @MainActor
    func resumeIdleTimer(reason: SleepPreventionReason = .other) {
        guard idleTimerSuspendCount > 0 else {
            AppLog.warning("resumeIdleTimer called with no active suspensions")
            return
        }
        idleTimerSuspendCount -= 1
        if let current = sleepPreventionCounts[reason], current > 1 {
            sleepPreventionCounts[reason] = current - 1
        } else {
            sleepPreventionCounts.removeValue(forKey: reason)
        }
        
        if idleTimerSuspendCount == 0 {
            lastActivity = Date()  // Reset activity timestamp
            AppLog.debugPublic("Idle timer RESUMED - album will auto-lock after \(Int(idleTimeout))s of inactivity")
            // Recompute system idle policy now that one suspension ended
            updateSystemIdleState()
        } else {
            AppLog.debugPublic("Idle timer suspension depth decreased to \(idleTimerSuspendCount)")
        }
    }
    
    @MainActor
    func updateSystemIdleState() {
#if os(iOS)
        let keepAwakeWhileUnlocked = UserDefaults.standard.bool(forKey: "keepScreenAwakeWhileUnlocked")
        let keepDuringSuspensions = UserDefaults.standard.bool(forKey: "keepScreenAwakeDuringSuspensions")
        
        let suspensionActive = idleTimerSuspendCount > 0 && keepDuringSuspensions
        let unlockedActive = self.isUnlocked && keepAwakeWhileUnlocked
        
        let newValue = suspensionActive || unlockedActive
        let oldValue = isSystemSleepPrevented
        UIApplication.shared.isIdleTimerDisabled = newValue
        isSystemSleepPrevented = newValue
        
        if newValue {
            // pick a visible reason, prefer import/viewing/prompt/other
            let reason: SleepPreventionReason? = {
                if sleepPreventionCounts[.importing] ?? 0 > 0 { return .importing }
                if sleepPreventionCounts[.viewing] ?? 0 > 0 { return .viewing }
                if sleepPreventionCounts[.prompt] ?? 0 > 0 { return .prompt }
                if sleepPreventionCounts[.other] ?? 0 > 0 { return .other }
                if unlockedActive { return .other }
                return nil
            }()
            if let r = reason {
                AppLog.info("System sleep prevented: \(r.displayName)")
            } else {
                AppLog.info("System sleep prevented")
            }
        } else {
            AppLog.info("System sleep allowed")
        }
        // If state changed, emit a small in-app notification when verbose logging is enabled
        if oldValue != newValue, enableVerboseLogging {
            if newValue {
                hideNotification = HideNotification(message: "Device will remain awake", type: .info, photos: nil)
            } else {
                hideNotification = HideNotification(message: "Device may sleep now", type: .info, photos: nil)
            }
        }
#endif
    }
    
    /// Public wrapper for the UI / app life-cycle to ensure idle state sync is recalculated
    /// without exposing internal implementation details.
    @MainActor
    func refreshIdleState() {
        updateSystemIdleState()
    }
    
    /// Encrypts and stores a photo or video in the album using either in-memory data or a file URL.
    func hidePhoto(
        mediaSource: MediaSource, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil,
        assetIdentifier: String? = nil, mediaType: MediaType = .photo, duration: TimeInterval? = nil,
        location: SecurePhoto.Location? = nil, isFavorite: Bool? = nil, progressHandler: ((Int64) async -> Void)? = nil
    ) async throws {
        // Restore operations write out of the album — block during Lockdown Mode
        if lockdownModeEnabled {
            throw AlbumError.operationDeniedByLockdown
        }
        
        await MainActor.run {
            lastActivity = Date()
        }
        
        // Respect Lockdown Mode: prevent additions while lockdown is active
        if lockdownModeEnabled {
            throw AlbumError.operationDeniedByLockdown
        }
        
        // In decoy mode, don't actually add photos to avoid affecting the real album
        guard !isDecoyMode else {
            return
        }
        
        guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey else {
            throw AlbumError.albumNotInitialized
        }
        
        try ensurePhotosDirectoryExists()
        let photosURL = photosDirectoryURL
        
        // Determine media size without duplicating memory usage
        let fileSize: Int64
        switch mediaSource {
        case .data(let data):
            fileSize = Int64(data.count)
        case .fileURL(let url):
            fileSize = try fileService.getFileSize(at: url)
        }
        
        guard fileSize > 0 && fileSize < CryptoConstants.maxMediaFileSize else {
            throw AlbumError.fileTooLarge(size: fileSize, maxSize: CryptoConstants.maxMediaFileSize)
        }
        
        var isDuplicate = false
        if let assetId = assetIdentifier {
            // Access hiddenPhotos on MainActor to avoid race conditions
            isDuplicate = await MainActor.run {
                hiddenPhotos.contains(where: { $0.originalAssetIdentifier == assetId })
            }
            
            if isDuplicate {
                AppLog.debugPrivate("Media already hidden: \(filename) (assetId: \(assetId))")
                return
            }
        }
        
        let photoId = UUID()
        let encryptedPath = photosURL.appendingPathComponent("\(photoId.uuidString).enc")
        let thumbnailPath = photosURL.appendingPathComponent("\(photoId.uuidString)_thumb.jpg")
        let encryptedThumbnailPath = photosURL.appendingPathComponent("\(photoId.uuidString)_thumb.enc")
        
        var thumbnail = await generateThumbnailData(from: mediaSource, mediaType: mediaType)
        if thumbnail.isEmpty {
            thumbnail = fallbackThumbnail(for: mediaType)
        }
        
        guard !thumbnail.isEmpty else {
            throw AlbumError.thumbnailGenerationFailed(
                reason: "Thumbnail generation returned empty data even after fallback")
        }
        
        try thumbnail.write(to: thumbnailPath, options: .atomic)
        
        let thumbnailFilename = "\(photoId.uuidString)_thumb.enc"
        try await fileService.saveEncryptedFile(
            data: thumbnail, filename: thumbnailFilename, to: photosURL, encryptionKey: encryptionKey,
            hmacKey: hmacKey)
        
        let encryptedFilename = "\(photoId.uuidString).enc"
        
        // Create metadata for SVF2
        let metadataLocation: FileService.EmbeddedMetadata.Location?
        if let loc = location {
            metadataLocation = FileService.EmbeddedMetadata.Location(latitude: loc.latitude, longitude: loc.longitude)
        } else {
            metadataLocation = nil
        }
        
        let metadata = FileService.EmbeddedMetadata(
            filename: filename,
            dateCreated: dateTaken ?? Date(),
            originalAssetIdentifier: assetIdentifier,
            duration: duration,
            location: metadataLocation,
            isFavorite: isFavorite
        )
        
        switch mediaSource {
        case .data(let data):
            try await fileService.saveEncryptedFile(
                data: data, filename: encryptedFilename, to: photosURL, encryptionKey: encryptionKey,
                hmacKey: hmacKey, mediaType: mediaType, metadata: metadata)
        case .fileURL(let url):
            try await fileService.saveStreamEncryptedFile(
                from: url, filename: encryptedFilename, mediaType: mediaType,
                metadata: metadata,
                to: photosURL,
                encryptionKey: encryptionKey, hmacKey: hmacKey, progressHandler: progressHandler)
        }
        
        let photo = SecurePhoto(
            encryptedDataPath: relativePath(for: encryptedPath),
            thumbnailPath: relativePath(for: thumbnailPath),
            encryptedThumbnailPath: relativePath(for: encryptedThumbnailPath),
            filename: filename,
            dateTaken: dateTaken,
            sourceAlbum: sourceAlbum,
            fileSize: fileSize,
            originalAssetIdentifier: assetIdentifier,
            mediaType: mediaType,
            duration: duration,
            location: location,
            isFavorite: isFavorite
        )
        
        DispatchQueue.main.async {
            if let assetId = assetIdentifier,
               self.hiddenPhotos.contains(where: { $0.originalAssetIdentifier == assetId })
            {
                AppLog.debugPrivate("Duplicate detected in final check, skipping: \(filename)")
                return
            }
            
            self.hiddenPhotos.append(photo)
            self.albumQueue.async {
                self.savePhotos()
            }
        }
    }
    
    /// High-level helper for camera capture handling. Centralises the logic that used to
    /// live in camera UI components so that the behaviour can be tested and mocked.
    /// If `cameraSaveToAlbumDirectly` is enabled, this will encrypt into the album.
    /// Otherwise it will attempt to save the captured media into the system Photos library
    /// using the `PhotosLibraryService.shared` instance (which is protocol-typed for mocking).
    @MainActor
    func handleCapturedMedia(
        mediaSource: MediaSource,
        filename: String,
        dateTaken: Date? = nil,
        sourceAlbum: String? = "Captured to Album",
        assetIdentifier: String? = nil,
        mediaType: MediaType = .photo,
        duration: TimeInterval? = nil,
        location: SecurePhoto.Location? = nil,
        isFavorite: Bool? = nil
    ) async throws {
        // Always encrypt captures from in-app camera flows into the app's encrypted album.
        // Do not save directly to the system Photos library — that would trigger an OS
        // permission prompt and is not allowed for in-app captures.
        do {
            try await hidePhoto(
                mediaSource: mediaSource,
                filename: filename,
                dateTaken: dateTaken,
                sourceAlbum: sourceAlbum,
                assetIdentifier: assetIdentifier,
                mediaType: mediaType,
                duration: duration,
                location: location,
                isFavorite: isFavorite,
                progressHandler: nil
            )
            return
        } catch AlbumError.albumNotInitialized {
            // Album is locked / keys not derived; queue this capture so it will be
            // processed automatically when the user unlocks the album.
            AppLog.info("Album locked - queuing captured media for later processing: \(filename)")
            
            // Materialize to a temp file so we can process after unlock. Use explicit
            // file extension derived from filename if present.
            let ext = (filename as NSString).pathExtension.isEmpty ? "jpg" : (filename as NSString).pathExtension
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            
            switch mediaSource {
            case .data(let data):
                do {
                    try data.write(to: tempURL)
                    // Persist pending capture on albumQueue to avoid race conditions
                    albumQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.pendingCapturedMedia.append(PendingCapture(url: tempURL, filename: filename, dateTaken: dateTaken, sourceAlbum: sourceAlbum, mediaType: mediaType, duration: duration))
                        self.savePendingCapturedMedia()
                    }
                } catch {
                    AppLog.error("Failed to write queued capture to temp file: \(error.localizedDescription)")
                }
            case .fileURL(let url):
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    albumQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.pendingCapturedMedia.append(PendingCapture(url: tempURL, filename: filename, dateTaken: dateTaken, sourceAlbum: sourceAlbum, mediaType: mediaType, duration: duration))
                        self.savePendingCapturedMedia()
                    }
                } catch {
                    AppLog.error("Failed to copy queued capture to temp file: \(error.localizedDescription)")
                }
            }
            
            return
        }
    }
    
    private func ensurePhotosDirectoryExists() throws {
        let photosURL = photosDirectoryURL
        if !FileManager.default.fileExists(atPath: photosURL.path) {
            try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        }
    }
    
    /// Backward-compatible helper that encrypts in-memory data by wrapping it in a MediaSource.
    func hidePhoto(
        imageData: Data, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil,
        assetIdentifier: String? = nil, mediaType: MediaType = .photo, duration: TimeInterval? = nil,
        location: SecurePhoto.Location? = nil, isFavorite: Bool? = nil
    ) async throws {
        try await hidePhoto(
            mediaSource: .data(imageData),
            filename: filename,
            dateTaken: dateTaken,
            sourceAlbum: sourceAlbum,
            assetIdentifier: assetIdentifier,
            mediaType: mediaType,
            duration: duration,
            location: location,
            isFavorite: isFavorite,
            progressHandler: nil
        )
    }
    
    /// Decrypts a photo or video from the album.
    /// - Parameter photo: The SecurePhoto record to decrypt
    /// - Returns: Decrypted media data
    /// - Throws: Error if file reading or decryption fails
    func decryptPhoto(_ photo: SecurePhoto) async throws -> Data {
        // Use FileService to load and decrypt the encrypted file
        guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey else {
            throw AlbumError.albumNotInitialized
        }
        let encryptedURL = resolveURL(for: photo.encryptedDataPath)
        return try await fileService.loadEncryptedFile(
            filename: encryptedURL.lastPathComponent,
            from: encryptedURL.deletingLastPathComponent(),
            encryptionKey: encryptionKey, hmacKey: hmacKey)
    }
    
    func decryptPhotoToTemporaryURL(_ photo: SecurePhoto, progressHandler: ((Int64) -> Void)? = nil) async throws -> URL
    {
        guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey else {
            throw AlbumError.albumNotInitialized
        }
        let encryptedURL = resolveURL(for: photo.encryptedDataPath)
        let filename = encryptedURL.lastPathComponent
        let directory = encryptedURL.deletingLastPathComponent()
        let originalExtension = URL(fileURLWithPath: photo.filename).pathExtension
        let preferredExtension = originalExtension.isEmpty ? nil : originalExtension
        return try await fileService.decryptEncryptedFileToTemporaryURL(
            filename: filename,
            originalExtension: preferredExtension,
            from: directory,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey,
            progressHandler: progressHandler
        )
    }
    
    public func decryptThumbnail(for photo: SecurePhoto) async throws -> Data {
        guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey else {
            throw AlbumError.albumNotInitialized
        }
        // Option 1: be resilient to missing thumbnail files and fall back gracefully.
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            let url = resolveURL(for: encryptedThumbnailPath)
            if !FileManager.default.fileExists(atPath: url.path) {
                AppLog.debugPrivate("[AlbumManager] decryptThumbnail: encrypted thumbnail missing for id=\(photo.id).")
                
            } else {
                do {
                    // Use FileService to load and decrypt the encrypted thumbnail
                    let filename = url.lastPathComponent
                    return try await fileService.loadEncryptedFile(
                        filename: filename,
                        from: url.deletingLastPathComponent(),
                        encryptionKey: encryptionKey, hmacKey: hmacKey)
                } catch {
                    AppLog.debugPrivate("[AlbumManager] decryptThumbnail: error reading encrypted thumbnail for id=\(photo.id): \(error.localizedDescription)")
                }
            }
        }
        
        // As a last resort, return empty Data so the UI can show a placeholder.
        return Data()
    }
    
    /// Permanently deletes a photo or video from the album.
    /// - Parameter photo: The SecurePhoto to delete
    func deletePhoto(_ photo: SecurePhoto) {
        Task { @MainActor in
            lastActivity = Date()
        }
        // Securely delete files (overwrite before deletion)
        secureDeleteFile(at: resolveURL(for: photo.encryptedDataPath))
        secureDeleteFile(at: resolveURL(for: photo.thumbnailPath))
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            secureDeleteFile(at: resolveURL(for: encryptedThumbnailPath))
        }
        
        // Remove from list on main thread
        DispatchQueue.main.async {
            self.hiddenPhotos.removeAll { $0.id == photo.id }
            self.savePhotos()
        }
    }
    
    /// Securely deletes a file by overwriting it before removal.
    /// - Parameter url: URL of the file to delete
    private func secureDeleteFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        // If secure deletion is disabled, just remove the file
        guard secureDeletionEnabled else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        
        do {
            // Get file size
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let fileSize = attributes[.size] as? Int64 else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            
            // Limit overwrite to reasonable size (100MB max)
            let sizeToOverwrite = min(fileSize, 100 * 1024 * 1024)
            
            // Multiple pass secure deletion (Gutmann method inspired)
            // Pass 1: Random data
            try overwriteFile(at: url, with: .random, size: sizeToOverwrite)
            // Pass 2: Complement of random data
            try overwriteFile(at: url, with: .complementRandom, size: sizeToOverwrite)
            // Pass 3: Random data again
            try overwriteFile(at: url, with: .random, size: sizeToOverwrite)
            
            // Now delete the file
            try FileManager.default.removeItem(at: url)
        } catch {
            AppLog.error("Secure deletion failed, using standard deletion: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    /// Overwrite patterns for secure file deletion
    private enum OverwritePattern {
        case random
        case complementRandom
        case zeros
        case ones
    }
    
    /// Overwrites a file with the specified pattern
    private func overwriteFile(at url: URL, with pattern: OverwritePattern, size: Int64) throws {
        var overwriteData = Data(count: Int(size))
        
        switch pattern {
        case .random:
            // Fill with cryptographically secure random data
            _ = overwriteData.withUnsafeMutableBytes { bytes in
                SecRandomCopyBytes(kSecRandomDefault, Int(size), bytes.baseAddress!)
            }
        case .complementRandom:
            // Fill with random data, then complement each byte
            _ = overwriteData.withUnsafeMutableBytes { bytes in
                SecRandomCopyBytes(kSecRandomDefault, Int(size), bytes.baseAddress!)
            }
            overwriteData = Data(overwriteData.map { ~$0 })
        case .zeros:
            // Fill with zeros
            overwriteData.resetBytes(in: 0..<Int(size))
        case .ones:
            // Fill with 0xFF
            overwriteData = Data(repeating: 0xFF, count: Int(size))
        }
        
        try overwriteData.write(to: url, options: .atomic)
        
        // Securely zero the overwrite data
        overwriteData.secureZero()
    }
    
    /// Restores a single photo or video by delegating to the batch restore workflow so that
    /// users get consistent progress reporting and cancellation support.
    /// - Parameter photo: The SecurePhoto to restore
    public func restorePhotoToLibrary(_ photo: SecurePhoto) async throws {
        try await batchRestorePhotos([photo], restoreToSourceAlbum: true)
    }
    
    /// Helper method to save a temporary file to Photos library and delete the photo from album on success.
    /// - Parameters:
    ///   - tempURL: The temporary URL of the decrypted media file
    ///   - photo: The SecurePhoto record
    ///   - targetAlbum: The target album name (optional)
    private func saveTempFileToLibraryAndDeletePhoto(tempURL: URL, photo: SecurePhoto, targetAlbum: String?)
    async throws
    {
        try await withCheckedThrowingContinuation { continuation in
            PhotosLibraryService.shared.saveMediaFileToLibrary(
                tempURL,
                filename: photo.filename,
                mediaType: photo.mediaType,
                toAlbum: targetAlbum,
                creationDate: photo.dateTaken,
                location: photo.location,
                isFavorite: photo.isFavorite
            ) { success, libraryError in
                if success {
                    AppLog.debugPrivate("Media restored to library with metadata: \(photo.filename)")
                    self.deletePhoto(photo)
                    continuation.resume(returning: ())
                } else {
                    let reason = libraryError?.localizedDescription ?? "Photos refused to import this item"
                    AppLog.error("Failed to restore media to library: \(photo.filename) – \(reason)")
                    continuation.resume(throwing: AlbumError.fileWriteFailed(path: photo.filename, reason: reason))
                }
            }
        }
    }
    
    /// Restores multiple photos/videos from the album to the Photos library.
    /// - Parameters:
    ///   - photos: Array of SecurePhoto items to restore
    ///   - restoreToSourceAlbum: Whether to restore to original album
    ///   - toNewAlbum: Optional new album name for all items
    func batchRestorePhotos(_ photos: [SecurePhoto], restoreToSourceAlbum: Bool = false, toNewAlbum: String? = nil)
    async throws
    {
        await MainActor.run {
            lastActivity = Date()
        }
        guard !photos.isEmpty else { return }
        
        await MainActor.run {
            self.restorationProgress.isRestoring = true
            self.restorationProgress.totalItems = photos.count
            self.restorationProgress.processedItems = 0
            self.restorationProgress.successItems = 0
            self.restorationProgress.failedItems = 0
            self.restorationProgress.currentBytesProcessed = 0
            self.restorationProgress.currentBytesTotal = 0
            self.restorationProgress.statusMessage = "Preparing restore…"
            self.restorationProgress.detailMessage = "\(photos.count) item(s)"
            self.restorationProgress.cancelRequested = false
        }
        
        // Group photos by target album to batch them efficiently
        var albumGroups: [String?: [SecurePhoto]] = [:]
        
        for photo in photos {
            var targetAlbum: String? = nil
            if let newAlbum = toNewAlbum {
                targetAlbum = newAlbum
            } else if restoreToSourceAlbum {
                targetAlbum = photo.sourceAlbum
            }
            
            if albumGroups[targetAlbum] == nil {
                albumGroups[targetAlbum] = []
            }
            albumGroups[targetAlbum]?.append(photo)
        }
        
        AppLog.debugPublic("Starting batch restore of \(photos.count) items grouped into \(albumGroups.count) albums")
        var wasCancelled = false
        
        do {
            for (targetAlbum, photosInGroup) in albumGroups {
                try Task.checkCancellation()
                AppLog.debugPublic("Processing group: \(targetAlbum ?? "Library") with \(photosInGroup.count) items")
                try await self.processRestoreGroup(photosInGroup, targetAlbum: targetAlbum)
            }
        } catch is CancellationError {
            wasCancelled = true
        }
        
        let restoreCancelled = wasCancelled
        await MainActor.run {
            self.restorationProgress.isRestoring = false
            self.restorationProgress.cancelRequested = false
            self.restorationProgress.currentBytesProcessed = 0
            self.restorationProgress.currentBytesTotal = 0
            let total = self.restorationProgress.totalItems
            let success = self.restorationProgress.successItems
            let failed = self.restorationProgress.failedItems
            let summary = "\(success)/\(total) restored" + (failed > 0 ? " • \(failed) failed" : "")
            self.restorationProgress.statusMessage = restoreCancelled ? "Restore canceled" : "Restore complete"
            self.restorationProgress.detailMessage = summary
            AppLog.debugPublic("Restoration complete: \(success)/\(total) successful, \(failed) failed (successful items already removed from album)")
        }
        
        if restoreCancelled {
            throw CancellationError()
        }
    }
    
    private func processRestoreGroup(_ photos: [SecurePhoto], targetAlbum: String?) async throws {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        let albumLabel = targetAlbum ?? "Library"
        for photo in photos {
            try Task.checkCancellation()
            
            let sizeDescription = formattedSizeString(for: photo.fileSize, formatter: formatter)
            await MainActor.run {
                self.restorationProgress.statusMessage = "Decrypting \(photo.filename)…"
                self.restorationProgress.detailMessage = self.restorationDetailText(
                    for: photo.filename,
                    albumName: albumLabel,
                    sizeDescription: sizeDescription)
                self.restorationProgress.currentBytesTotal = max(photo.fileSize, 0)
                self.restorationProgress.currentBytesProcessed = 0
            }
            
            do {
                let tempURL = try await self.decryptPhotoToTemporaryURL(photo) { bytesRead in
                    Task { @MainActor in
                        self.restorationProgress.currentBytesProcessed = bytesRead
                    }
                }
                
                defer { try? FileManager.default.removeItem(at: tempURL) }
                
                let detectedSize = photo.fileSize > 0 ? photo.fileSize : self.fileSize(at: tempURL)
                await MainActor.run {
                    if detectedSize > 0 {
                        self.restorationProgress.currentBytesTotal = detectedSize
                    }
                }
                
                try Task.checkCancellation()
                
                await MainActor.run {
                    self.restorationProgress.statusMessage = "Saving \(photo.filename) to Photos…"
                    self.restorationProgress.currentBytesProcessed = self.restorationProgress.currentBytesTotal
                }
                
                try await self.saveTempFileToLibraryAndDeletePhoto(
                    tempURL: tempURL, photo: photo, targetAlbum: targetAlbum)
                
                await MainActor.run {
                    self.restorationProgress.processedItems += 1
                    self.restorationProgress.successItems += 1
                }
                
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLog.error("Failed to process \(photo.filename): \(error.localizedDescription)")
                await MainActor.run {
                    self.restorationProgress.processedItems += 1
                    self.restorationProgress.failedItems += 1
                    self.restorationProgress.statusMessage = "Failed \(photo.filename)"
                    self.restorationProgress.detailMessage = error.localizedDescription
                    self.restorationProgress.currentBytesProcessed = 0
                    self.restorationProgress.currentBytesTotal = 0
                }
            }
        }
    }
    
    private func formattedSizeString(for size: Int64, formatter: ByteCountFormatter) -> String? {
        guard size > 0 else { return nil }
        return formatter.string(fromByteCount: size)
    }
    
    private func restorationDetailText(for filename: String, albumName: String?, sizeDescription: String?) -> String {
        var parts: [String] = [filename]
        if let sizeDescription {
            parts.append(sizeDescription)
        }
        if let albumName {
            parts.append(albumName)
        }
        return parts.joined(separator: " • ")
    }
    
    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }
    
    /// Removes duplicate photos from the album based on asset identifiers.
    func removeDuplicates() {
        DispatchQueue.global(qos: .userInitiated).async {
            var seen = Set<String>()
            var uniquePhotos: [SecurePhoto] = []
            var duplicatesToDelete: [SecurePhoto] = []
            
            // Access hiddenPhotos on main thread first
            let currentPhotos = DispatchQueue.main.sync {
                return self.hiddenPhotos
            }
            
            for photo in currentPhotos {
                if let assetId = photo.originalAssetIdentifier {
                    if seen.contains(assetId) {
                        duplicatesToDelete.append(photo)
                    } else {
                        seen.insert(assetId)
                        uniquePhotos.append(photo)
                    }
                } else {
                    // Keep photos without asset identifier
                    uniquePhotos.append(photo)
                }
            }
            
            // Delete duplicate files
            for photo in duplicatesToDelete {
                try? FileManager.default.removeItem(at: self.resolveURL(for: photo.encryptedDataPath))
                try? FileManager.default.removeItem(at: self.resolveURL(for: photo.thumbnailPath))
                if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
                    try? FileManager.default.removeItem(at: self.resolveURL(for: encryptedThumbnailPath))
                }
            }
            
            DispatchQueue.main.async {
                self.hiddenPhotos = uniquePhotos
                self.savePhotos()
                self.objectWillChange.send()
                AppLog.debugPublic("Removed \(duplicatesToDelete.count) duplicate photos")
            }
        }
    }
    
    /// Generates a thumbnail from media data asynchronously.
    /// - Parameters:
    ///   - mediaData: Raw media data
    ///   - mediaType: Type of media (.photo or .video)
    ///   - completion: Called with thumbnail data when ready
    private func generateThumbnail(from mediaData: Data, mediaType: MediaType, completion: @escaping (Data) -> Void) {
        // Check input data size
        guard mediaData.count > 0 && mediaData.count < 100 * 1024 * 1024 else {  // 100MB limit for thumbnails
            completion(Data())  // Return empty data to indicate failure
            return
        }
        
        Task {
            let thumbnailData = await self.generateThumbnailData(from: .data(mediaData), mediaType: mediaType)
            await MainActor.run {
                completion(thumbnailData)
            }
        }
    }
    
    private func generateThumbnailData(from source: MediaSource, mediaType: MediaType) async -> Data {
        switch (mediaType, source) {
        case (.video, .data(let data)):
            return await generateVideoThumbnail(from: data)
        case (.video, .fileURL(let url)):
            return await generateVideoThumbnail(fromFileURL: url)
        case (.photo, .data(let data)):
            return await generatePhotoThumbnail(from: data)
        case (.photo, .fileURL(let url)):
            return await generatePhotoThumbnail(fromFileURL: url)
        }
    }
    
    /// Generates a thumbnail from photo data (asynchronous).
    private func generatePhotoThumbnail(from mediaData: Data) async -> Data {
        return await Task.detached(priority: .userInitiated) {
            // Use ImageIO to downsample directly from data without loading full image
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 300,
            ]
            
            guard let source = CGImageSourceCreateWithData(mediaData as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else {
                return Data()
            }
            
#if os(macOS)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            guard let tiffData = image.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            else {
                return Data()
            }
            return jpegData
#else
            let image = UIImage(cgImage: cgImage)
            return image.jpegData(compressionQuality: 0.8) ?? Data()
#endif
        }.value
    }
    
    private func generatePhotoThumbnail(fromFileURL url: URL) async -> Data {
        return await Task.detached(priority: .userInitiated) {
            // Use ImageIO to downsample directly from file without loading full image
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 300,
            ]
            
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else {
                return Data()
            }
            
#if os(macOS)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            guard let tiffData = image.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            else {
                return Data()
            }
            return jpegData
#else
            let image = UIImage(cgImage: cgImage)
            return image.jpegData(compressionQuality: 0.8) ?? Data()
#endif
        }.value
    }
    
    /// Generates a thumbnail from video data (synchronous, call from background queue).
    private func generateVideoThumbnail(from videoData: Data) async -> Data {
        guard videoData.count > 0 && videoData.count <= CryptoConstants.maxMediaFileSize else {
            AppLog.debugPrivate("Video data size invalid: \(videoData.count) bytes")
            return Data()
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        
        do {
            try videoData.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            let asset = AVAsset(url: tempURL)
            return await generateVideoThumbnail(fromAsset: asset)
        } catch {
            AppLog.error("Failed to generate video thumbnail: \(error.localizedDescription)")
        }
        
        return Data()
    }
    
    private func generateVideoThumbnail(fromFileURL url: URL) async -> Data {
        let asset = AVAsset(url: url)
        return await generateVideoThumbnail(fromAsset: asset)
    }
    
    private func generateVideoThumbnail(fromAsset asset: AVAsset) async -> Data {
        do {
            let tracks = try await asset.load(.tracks)
            guard tracks.contains(where: { $0.mediaType == .video }) else {
                AppLog.debugPublic("No video tracks found in asset")
                return Data()
            }
            
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 300, height: 300)
            
            let duration = try await asset.load(.duration)
            let time = CMTimeMinimum(CMTime(seconds: 1, preferredTimescale: 60), duration)
            
            let (cgImage, _) = try await imageGenerator.image(at: time)
            
#if os(macOS)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            let maxSize: CGFloat = 300
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            
            guard width > 0 && height > 0 else { return Data() }
            
            let scale = min(maxSize / width, maxSize / height, 1.0)
            let newSize = NSSize(width: width * scale, height: height * scale)
            
            let thumbnail = NSImage(size: newSize)
            thumbnail.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            thumbnail.unlockFocus()
            
            guard let tiffData = thumbnail.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            else {
                return Data()
            }
            
            return jpegData
#else
            let image = UIImage(cgImage: cgImage)
            
            let maxSize: CGFloat = 300
            let size = image.size
            
            guard size.width > 0 && size.height > 0 else { return Data() }
            
            let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            
            image.draw(in: CGRect(origin: .zero, size: newSize))
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext(),
                  let jpegData = resizedImage.jpegData(compressionQuality: 0.8)
            else {
                return Data()
            }
            
            return jpegData
#endif
        } catch {
            AppLog.error("Failed to generate video thumbnail: \(error.localizedDescription)")
            return Data()
        }
    }
    
    /// Generates a generic placeholder thumbnail when we cannot derive one from the media data.
    private func fallbackThumbnail(for mediaType: MediaType) -> Data {
#if os(macOS)
        let size = NSSize(width: 280, height: 280)
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Background gradient for quick visual differentiation
        let background = NSGradient(colors: [
            NSColor(calibratedRed: 0.21, green: 0.24, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.34, green: 0.37, blue: 0.42, alpha: 1),
        ])
        background?.draw(in: NSBezierPath(rect: NSRect(origin: .zero, size: size)), angle: 90)
        
        let symbolName = mediaType == .video ? "play.circle" : "photo"
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let symbolRect = NSRect(x: (size.width - 96) / 2, y: (size.height - 96) / 2, width: 96, height: 96)
            NSColor.white.set()
            symbol.draw(in: symbolRect)
        }
        
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else {
            return Data()
        }
        return jpegData
#else
        let size = CGSize(width: 280, height: 280)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()
        let colors = [
            UIColor(red: 0.21, green: 0.24, blue: 0.28, alpha: 1).cgColor,
            UIColor(red: 0.34, green: 0.37, blue: 0.42, alpha: 1).cgColor,
        ]
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])
        context?.drawLinearGradient(
            gradient!, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        
        let symbolName = mediaType == .video ? "play.circle" : "photo"
        if let image = UIImage(systemName: symbolName) {
            let rect = CGRect(x: (size.width - 96) / 2, y: (size.height - 96) / 2, width: 96, height: 96)
            UIColor.white.set()
            image.draw(in: rect)
        }
        
        guard let rendered = UIGraphicsGetImageFromCurrentImageContext(),
              let data = rendered.jpegData(compressionQuality: 0.85)
        else {
            return Data()
        }
        return data
#endif
    }
    
    /// Generates fake photos for decoy mode to make the album appear populated
    private func generateFakePhotos() -> [SecurePhoto] {
        var fakePhotos: [SecurePhoto] = []
        let fakeFilenames = [
            "IMG_0001.jpg", "IMG_0002.jpg", "IMG_0003.jpg", "IMG_0004.jpg", "IMG_0005.jpg",
            "VID_0001.mov", "VID_0002.mov", "IMG_0006.jpg", "IMG_0007.jpg", "IMG_0008.jpg"
        ]
        let fakeDates = [
            Date().addingTimeInterval(-86400 * 7), // 1 week ago
            Date().addingTimeInterval(-86400 * 5),
            Date().addingTimeInterval(-86400 * 3),
            Date().addingTimeInterval(-86400 * 2),
            Date().addingTimeInterval(-86400 * 1),
            Date().addingTimeInterval(-3600 * 12), // 12 hours ago
            Date().addingTimeInterval(-3600 * 6),
            Date().addingTimeInterval(-3600 * 2),
            Date().addingTimeInterval(-1800), // 30 min ago
            Date().addingTimeInterval(-300) // 5 min ago
        ]
        
        for (index, filename) in fakeFilenames.enumerated() {
            let mediaType: MediaType = filename.hasSuffix(".mov") ? .video : .photo
            _ = fallbackThumbnail(for: mediaType)
            let fakeId = UUID()
            let fakeEncryptedPath = "fake/\(fakeId.uuidString).enc"
            let fakeThumbnailPath = "fake/\(fakeId.uuidString)_thumb.jpg"
            let fakeEncryptedThumbnailPath = "fake/\(fakeId.uuidString)_thumb.enc"
            
            let photo = SecurePhoto(
                id: fakeId,
                encryptedDataPath: fakeEncryptedPath,
                thumbnailPath: fakeThumbnailPath,
                encryptedThumbnailPath: fakeEncryptedThumbnailPath,
                filename: filename,
                dateTaken: fakeDates[index % fakeDates.count],
                sourceAlbum: "Camera Roll",
                albumAlbum: nil,
                fileSize: Int64(1024 * 1024 * (index + 1)), // Fake sizes 1MB, 2MB, etc.
                originalAssetIdentifier: "fake_\(index)",
                mediaType: mediaType,
                duration: mediaType == .video ? TimeInterval(30 + index * 10) : nil,
                location: nil,
                isFavorite: index % 3 == 0 // Some marked as favorite
            )
            fakePhotos.append(photo)
        }
        
        return fakePhotos
    }
    
    private func savePhotos() {
        guard let data = try? JSONEncoder().encode(hiddenPhotos) else { return }
        AppLog.debugPrivate("savePhotos: writing \(hiddenPhotos.count) items to \(photosMetadataFileURL.path)")
        try? data.write(to: photosMetadataFileURL)
    }
    
    func saveSettings() {
        // Capture values on the current thread (Main Thread) to avoid race conditions
        // when accessing @Published properties inside the background queue block
        let version = String(securityVersion)
        let secureDelete = String(secureDeletionEnabled)
        let autoRemoveDuplicates = String(autoRemoveDuplicatesOnImport)
        let importNotifications = String(enableImportNotifications)
        
        albumQueue.sync {
            // Ensure album directory exists before saving
            do {
                try FileManager.default.createDirectory(at: albumBaseURL, withIntermediateDirectories: true)
            } catch {
                AppLog.error("Failed to create album directory: \(error.localizedDescription)")
                return
            }
            
            let settings: [String: String] = [
                "securityVersion": version,
                "secureDeletionEnabled": secureDelete,
                "autoRemoveDuplicatesOnImport": autoRemoveDuplicates,
                "enableImportNotifications": importNotifications,
                "autoLockTimeoutSeconds": String(autoLockTimeoutSeconds),
                "requirePasscodeOnLaunch": String(requirePasscodeOnLaunch),
                "biometricPolicy": biometricPolicy,
                "appTheme": appTheme,
                "compactLayoutEnabled": String(compactLayoutEnabled),
                "accentColorName": accentColorName,
                "cameraMaxQuality": String(cameraMaxQuality),
                "cameraAutoRemoveFromPhotos": String(cameraAutoRemoveFromPhotos),
                // New settings
                "autoWipeOnFailedAttemptsEnabled": String(autoWipeOnFailedAttemptsEnabled),
                "autoWipeFailedAttemptsThreshold": String(autoWipeFailedAttemptsThreshold),
                "requireReauthForExports": String(requireReauthForExports),
                "backupSchedule": backupSchedule,
                "encryptedCloudSyncEnabled": String(encryptedCloudSyncEnabled),
                "thumbnailPrivacy": thumbnailPrivacy,
                "stripMetadataOnExport": String(stripMetadataOnExport),
                "exportPasswordProtect": String(exportPasswordProtect),
                "exportExpiryDays": String(exportExpiryDays),
                "enableVerboseLogging": String(enableVerboseLogging),
                "telemetryEnabled": String(telemetryEnabled),
                "passphraseMinLength": String(passphraseMinLength),
                "enableRecoveryKey": String(enableRecoveryKey),
                "lockdownModeEnabled": String(lockdownModeEnabled),
            ]
            
            do {
                let data = try JSONEncoder().encode(settings)
                try data.write(to: settingsFileURL, options: .atomic)
                AppLog.debugPrivate("Successfully saved settings to: \(settingsFileURL.path)")
                // Also write a lightweight representation to the App Group so extensions
                // and other processes can observe lockdown state. This is best-effort.
                if let suite = UserDefaults(suiteName: FileConstants.appGroupIdentifier) {
                    suite.set(lockdownModeEnabled, forKey: "lockdownModeEnabled")
                    suite.synchronize()
                }
                
                // Create or remove a sentinel file in the App Group container for file-system based checks
                if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FileConstants.appGroupIdentifier) {
                    let sentinel = container.appendingPathComponent("lockdown.enabled")
                    if lockdownModeEnabled {
                        // touch the file
                        try? Data().write(to: sentinel, options: .atomic)
                    } else {
                        try? FileManager.default.removeItem(at: sentinel)
                    }
                }
                // Respect the telemetry flag: enable/disable the TelemetryService on save
                TelemetryService.shared.setEnabled(telemetryEnabled)
            } catch {
                AppLog.error("Failed to save settings: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadSettings() async {
        // We use the albumQueue to ensure thread safety
        // But since we are async, we can just run on the queue?
        // Actually, loadSettings accesses @Published properties, so it should run on MainActor eventually?
        // But it reads from disk/keychain.
        
        AppLog.debugPrivate("Attempting to load settings from: \(settingsFileURL.path)")
        
        // Load credentials from Keychain
        if let credentials = try? await passwordService.retrievePasswordCredentials() {
            await MainActor.run {
                passwordHash = credentials.hash.map { String(format: "%02x", $0) }.joined()
                passwordSalt = credentials.salt.base64EncodedString()
            }
            AppLog.debugPublic("Loaded credentials from Keychain")
        } else {
            AppLog.debugPublic("No credentials found in Keychain")
        }
        
        guard let data = try? Data(contentsOf: settingsFileURL),
              let settings = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            AppLog.debugPublic("No settings file found or failed to decode")
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        AppLog.debugPublic("Loaded settings: [REDACTED]")
        
        await MainActor.run {
            if let versionString = settings["securityVersion"], let version = Int(versionString) {
                securityVersion = version
            } else {
                // Default to 1 (Legacy) if missing
                securityVersion = 1
            }
            
            if let secureDeleteString = settings["secureDeletionEnabled"], let secureDelete = Bool(secureDeleteString) {
                secureDeletionEnabled = secureDelete
            } else {
                secureDeletionEnabled = true
            }
            
            if let autoRemoveString = settings["autoRemoveDuplicatesOnImport"], let autoRemove = Bool(autoRemoveString) {
                autoRemoveDuplicatesOnImport = autoRemove
            } else {
                autoRemoveDuplicatesOnImport = true
            }
            
            if let notificationsString = settings["enableImportNotifications"], let notifications = Bool(notificationsString) {
                enableImportNotifications = notifications
            } else {
                enableImportNotifications = true
            }
            
            if let autoLockString = settings["autoLockTimeoutSeconds"], let autoLock = Double(autoLockString) {
                autoLockTimeoutSeconds = autoLock
            }
            
            if let requirePass = settings["requirePasscodeOnLaunch"], let require = Bool(requirePass) {
                requirePasscodeOnLaunch = require
            }
            
            if let policy = settings["biometricPolicy"] {
                biometricPolicy = policy
            }
            
            if let theme = settings["appTheme"] {
                appTheme = theme
            }
            
            if let compactString = settings["compactLayoutEnabled"], let compact = Bool(compactString) {
                compactLayoutEnabled = compact
            }
            
            if let accent = settings["accentColorName"] {
                accentColorName = accent
            }
            
            // cameraSaveToAlbumDirectly setting removed — in-app captures always go into the encrypted album
            
            if let maxQualityString = settings["cameraMaxQuality"], let maxQ = Bool(maxQualityString) {
                cameraMaxQuality = maxQ
            }
            
            if let autoRemoveString = settings["cameraAutoRemoveFromPhotos"], let autoRemove = Bool(autoRemoveString) {
                cameraAutoRemoveFromPhotos = autoRemove
            }
            
            // New settings mapping (provide safe defaults when missing)
            if let awString = settings["autoWipeOnFailedAttemptsEnabled"], let aw = Bool(awString) {
                autoWipeOnFailedAttemptsEnabled = aw
            } else {
                autoWipeOnFailedAttemptsEnabled = false
            }
            
            if let awThreshold = settings["autoWipeFailedAttemptsThreshold"], let t = Int(awThreshold) {
                autoWipeFailedAttemptsThreshold = t
            } else {
                autoWipeFailedAttemptsThreshold = 10
            }
            
            if let reauthString = settings["requireReauthForExports"], let reauth = Bool(reauthString) {
                requireReauthForExports = reauth
            } else {
                requireReauthForExports = true
            }
            
            if let schedule = settings["backupSchedule"] {
                backupSchedule = schedule
            } else {
                backupSchedule = "manual"
            }
            
            if let cloudSyncString = settings["encryptedCloudSyncEnabled"], let cloudSync = Bool(cloudSyncString) {
                encryptedCloudSyncEnabled = cloudSync
            } else {
                encryptedCloudSyncEnabled = false
            }
            
            if let thumbPrivacy = settings["thumbnailPrivacy"] {
                thumbnailPrivacy = thumbPrivacy
            } else {
                thumbnailPrivacy = "blur"
            }
            
            if let stripMetaString = settings["stripMetadataOnExport"], let stripMeta = Bool(stripMetaString) {
                stripMetadataOnExport = stripMeta
            } else {
                stripMetadataOnExport = true
            }
            
            if let exportProtectString = settings["exportPasswordProtect"], let exportProtect = Bool(exportProtectString) {
                exportPasswordProtect = exportProtect
            } else {
                exportPasswordProtect = true
            }
            
            if let expiryString = settings["exportExpiryDays"], let expiry = Int(expiryString) {
                exportExpiryDays = expiry
            } else {
                exportExpiryDays = 30
            }
            
            if let verboseString = settings["enableVerboseLogging"], let verbose = Bool(verboseString) {
                enableVerboseLogging = verbose
            } else {
                enableVerboseLogging = false
            }
            
            if let telemetryString = settings["telemetryEnabled"], let telemetry = Bool(telemetryString) {
                telemetryEnabled = telemetry
            } else {
                // Respect user preference: default to disabled
                telemetryEnabled = false
            }
            
            if let passMinString = settings["passphraseMinLength"], let passMin = Int(passMinString) {
                passphraseMinLength = passMin
            } else {
                passphraseMinLength = 8
            }
            
            if let recoveryString = settings["enableRecoveryKey"], let recovery = Bool(recoveryString) {
                enableRecoveryKey = recovery
            } else {
                enableRecoveryKey = false
            }
            
            if let lockdownString = settings["lockdownModeEnabled"], let lockdown = Bool(lockdownString) {
                lockdownModeEnabled = lockdown
            } else {
                lockdownModeEnabled = false
            }
            
            if !passwordHash.isEmpty {
                showUnlockPrompt = true
            }
            
            isLoading = false
        }
    }
    
    /// Public wrapper to reload settings (tests and UI can call this to refresh state)
    func reloadSettings() async {
        await loadSettings()
    }
    
    // MARK: - Album Location Management
    
    // Album location is now fixed to the App Sandbox Container.
    // Legacy moveAlbum functionality has been removed to ensure security and data integrity.
    
    // MARK: - Biometric Authentication Helpers
    
    func saveBiometricPassword(_ password: String) async {
#if DEBUG
        // Saving biometric password
#endif
        do {
            try await securityService.storeBiometricPassword(password)
        } catch {
            AppLog.error("Failed to store biometric password: \(error.localizedDescription)")
        }
    }
    
    func getBiometricPassword() async -> String? {
        return try? await securityService.retrieveBiometricPassword()
    }
    
    /// Retrieves the biometric password, throwing an error if authentication fails or is cancelled.
    /// This allows the UI to distinguish between "not found" and "user cancelled".
    func authenticateAndRetrievePassword() async throws -> String {
        let setPromptState: (Bool) -> Void = { value in
            if Thread.isMainThread {
                self.authenticationPromptActive = value
            } else {
                DispatchQueue.main.async {
                    self.authenticationPromptActive = value
                }
            }
        }
        
        setPromptState(true)
        defer { setPromptState(false) }
        
        guard let password = try await securityService.retrieveBiometricPassword() else {
            throw AlbumError.biometricNotAvailable
        }
        return password
    }
    
    /// Validates crypto operations by performing encryption/decryption round-trip test.
    /// - Returns: `true` if validation successful, `false` otherwise
    func validateCryptoOperations() async -> Bool {
        let testData = "EncryptedAlbum crypto validation test data".data(using: .utf8)!
        
        // Test encryption
        do {
            let (encryptedData, nonce, hmac) = try await cryptoService.encryptDataWithIntegrity(
                testData, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
            guard !encryptedData.isEmpty else {
                AppLog.error("Crypto validation failed: encryption returned empty data")
                return false
            }
            
            // Test decryption
            let decrypted = try await cryptoService.decryptDataWithIntegrity(
                encryptedData, nonce: nonce, hmac: hmac, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
            guard !decrypted.isEmpty else {
                AppLog.error("Crypto validation failed: decryption returned empty data")
                return false
            }
            
            // Verify round-trip integrity
            guard decrypted == testData else {
                AppLog.error("Crypto validation failed: decrypted data doesn't match original")
                return false
            }
        } catch {
            AppLog.error("Crypto validation failed: \(error.localizedDescription)")
            return false
        }
        
        // Test key derivation consistency
        guard await validateKeyDerivationConsistency() else {
            AppLog.error("Crypto validation failed: key derivation consistency check")
            return false
        }
        
        AppLog.debugPublic("Crypto validation successful")
        return true
    }
    
    /// Validates that cached keys are available and valid
    private func validateKeyDerivationConsistency() async -> Bool {
        // Check that we have cached keys
        guard cachedEncryptionKey != nil && cachedHMACKey != nil else {
            AppLog.error("Key validation failed: cached keys not available")
            return false
        }
        
        // Test that cached keys work for basic crypto operations
        let testData = "key validation test".data(using: .utf8)!
        do {
            let (encryptedData, nonce, hmac) = try await cryptoService.encryptDataWithIntegrity(
                testData, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
            let decrypted = try await cryptoService.decryptDataWithIntegrity(
                encryptedData, nonce: nonce, hmac: hmac, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
            guard decrypted == testData else {
                AppLog.error("Key validation failed: round-trip test failed")
                return false
            }
        } catch {
            AppLog.error("Key validation failed: crypto operation failed - \(error.localizedDescription)")
            return false
        }
        
        return true
    }
    
    // MARK: - New Refactored Methods
    
    /// Validates the integrity of stored album data including settings and photo metadata
    /// - Returns: Array of validation errors, empty if all checks pass
    func validateAlbumIntegrity() async throws {
        try await securityService.validateAlbumIntegrity(
            albumURL: albumBaseURL, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!, expectedMetadata: nil)
    }
    
    /// Performs comprehensive security health checks on the album
    /// - Returns: Security health report
    func performSecurityHealthCheck() async throws -> SecurityHealthReport {
        return try await securityService.performSecurityHealthCheck()
    }
    
    /// Exports the in-memory session keys (encryption + HMAC) into an encrypted backup file.
    /// The backup is protected by a password provided by the caller. The returned file is a JSON
    /// container written to the temporary directory and must be handled securely by the caller.
    func exportMasterKeyBackup(backupPassword: String) async throws -> URL {
        // Prevent exporting keys during Lockdown Mode
        guard !lockdownModeEnabled else { throw AlbumError.operationDeniedByLockdown }
        
        guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey else {
            throw AlbumError.albumNotInitialized
        }
        
        // Extract raw key bytes
        let encData = encryptionKey.withUnsafeBytes { Data($0) }
        let hmacData = hmacKey.withUnsafeBytes { Data($0) }
        var combined = Data()
        combined.append(encData)
        combined.append(hmacData)
        
        // Generate salt for backup key derivation
        let salt = try await cryptoService.generateSalt()
        
        // Derive a pair of keys from the backup password -- use the derived encryption key + hmac key
        let (backupEncKey, backupHmacKey) = try await cryptoService.deriveKeys(password: backupPassword, salt: salt)
        
        // Encrypt the combined key material and compute integrity HMAC
        let (encryptedData, nonce) = try await cryptoService.encryptData(combined, key: backupEncKey)
        let integrity = await cryptoService.generateHMAC(for: encryptedData, key: backupHmacKey)
        
        // Build JSON container
        let container: [String: String] = [
            "version": "1",
            "salt": salt.base64EncodedString(),
            "nonce": nonce.base64EncodedString(),
            "encrypted": encryptedData.base64EncodedString(),
            "hmac": integrity.base64EncodedString()
        ]
        
        let jsonData = try JSONEncoder().encode(container)
        
        let filename = "encrypted-key-backup-\(ISO8601DateFormatter().string(from: Date())).backup"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try jsonData.write(to: url, options: .atomic)
        
        return url
    }
    
    /// Performs biometric authentication
    func authenticateWithBiometrics(reason: String) async throws {
        try await securityService.authenticateWithBiometrics(reason: reason)
    }
    
    /// Loads photos from disk
    private func loadPhotos() async throws {
        guard let data = try? Data(contentsOf: photosMetadataFileURL) else {
            await MainActor.run {
                hiddenPhotos = []
            }
            return
        }
        
        let decodedPhotos = try JSONDecoder().decode([SecurePhoto].self, from: data)
        let normalizedPhotos = decodedPhotos.map { photo in
            var updated = photo
            updated.encryptedDataPath = normalizedStoredPath(photo.encryptedDataPath)
            updated.thumbnailPath = normalizedStoredPath(photo.thumbnailPath)
            if let encryptedThumb = photo.encryptedThumbnailPath {
                updated.encryptedThumbnailPath = normalizedStoredPath(encryptedThumb)
            }
            return updated
        }
        await MainActor.run {
            hiddenPhotos = normalizedPhotos
        }
    }
}


// MARK: - Direct File Import

extension AlbumManager {
    /// Starts encrypting files directly from disk into the album
    func startDirectImport(urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        // Prevent imports during lockdown (UI updates dispatched to main actor)
        if lockdownModeEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hideNotification = HideNotification(message: "Import blocked while Lockdown Mode is enabled.", type: .failure, photos: nil)
                self.importProgress.isImporting = false
                self.importProgress.statusMessage = "Import blocked"
            }
            return
        }
        
        guard isUnlocked, cachedEncryptionKey != nil, cachedHMACKey != nil else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                AppLog.debugPublic("Album locked, queuing \(urls.count) items for import after unlock.")
                self.pendingImportURLs.append(contentsOf: urls)
                self.hideNotification = HideNotification(
                    message: "Items queued. Unlock to complete import.",
                    type: .info,
                    photos: nil
                )
            }
            return
        }
        
        Task { @MainActor [weak self] in
            self?.directImportProgress.reset(totalItems: urls.count)
        }
        
        directImportTask?.cancel()
        directImportTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runDirectImport(urls: urls)
        }
    }
    
    /// Signals cancellation for the active direct import task
    func cancelDirectImport() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.directImportProgress.isImporting, !self.directImportProgress.cancelRequested else { return }
            self.directImportProgress.cancelRequested = true
            self.directImportProgress.statusMessage = "Canceling import…"
            self.directImportProgress.detailMessage = "Finishing current file"
        }
        directImportTask?.cancel()
    }
    
    private func runDirectImport(urls: [URL]) async {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        
        await MainActor.run {
            suspendIdleTimer(reason: .importing)
        }
        
        defer {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.directImportProgress.finish()
                self.resumeIdleTimer(reason: .importing)
                self.directImportTask = nil
            }
        }
        
        var successCount = 0
        var failureCount = 0
        var firstError: String?
        var wasCancelled = false
        let fileManager = FileManager.default
        
        for (index, url) in urls.enumerated() {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            
            let cancelRequested = await MainActor.run { directImportProgress.cancelRequested }
            if cancelRequested {
                wasCancelled = true
                break
            }
            
            await MainActor.run {
                lastActivity = Date()
            }
            
            let filename = url.lastPathComponent
            let sizeText = fileSizeString(for: url, formatter: formatter)
            let detail = buildDirectImportDetailText(index: index + 1, total: urls.count, sizeDescription: sizeText)
            
            var fileSizeValue: Int64 = 0
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let fileSizeNumber = attributes[.size] as? NSNumber
            {
                fileSizeValue = fileSizeNumber.int64Value
            }
            
            if fileSizeValue > CryptoConstants.maxMediaFileSize {
                failureCount += 1
                let limitString = formatter.string(fromByteCount: CryptoConstants.maxMediaFileSize)
                if firstError == nil {
                    let humanSize = formatter.string(fromByteCount: fileSizeValue)
                    firstError = "\(filename) exceeds the \(limitString) limit (\(humanSize))."
                }
                let processedCount = index + 1
                let totalItems = urls.count
                let sizeForProgress = fileSizeValue
                await MainActor.run {
                    directImportProgress.statusMessage = "Skipping \(filename)…"
                    directImportProgress.detailMessage = "File exceeds \(limitString) limit"
                    directImportProgress.itemsProcessed = processedCount
                    directImportProgress.itemsTotal = totalItems
                    directImportProgress.bytesTotal = sizeForProgress
                    directImportProgress.forceUpdateBytesProcessed(sizeForProgress)
                }
                continue
            }
            
            let totalItems = urls.count
            let sizeForProgress = fileSizeValue
            await MainActor.run {
                directImportProgress.statusMessage = "Encrypting \(filename)…"
                directImportProgress.detailMessage = detail
                directImportProgress.itemsProcessed = index
                directImportProgress.itemsTotal = totalItems
                directImportProgress.bytesTotal = sizeForProgress
                directImportProgress.forceUpdateBytesProcessed(0)
            }
            
            do {
                try Task.checkCancellation()
                let mediaType: MediaType = isVideoFile(url) ? .video : .photo
                try await hidePhoto(
                    mediaSource: .fileURL(url),
                    filename: filename,
                    dateTaken: nil,
                    sourceAlbum: "Captured to Album",
                    assetIdentifier: nil,
                    mediaType: mediaType,
                    duration: nil,
                    location: nil,
                    isFavorite: nil,
                    progressHandler: { [weak self] bytesRead in
                        guard let self else { return }
                        await MainActor.run {
                            self.directImportProgress.throttledUpdateBytesProcessed(bytesRead)
                        }
                    }
                )
                successCount += 1
            } catch is CancellationError {
                wasCancelled = true
                break
            } catch {
                failureCount += 1
                if firstError == nil {
                    firstError = "\(filename): \(error.localizedDescription)"
                }
                await MainActor.run {
                    directImportProgress.statusMessage = "Failed \(filename)"
                    directImportProgress.detailMessage = error.localizedDescription
                }
            }
            
            let completedItems = index + 1
            await MainActor.run {
                directImportProgress.itemsProcessed = completedItems
                directImportProgress.forceUpdateBytesProcessed(directImportProgress.bytesTotal)
            }
        }
        
        if Task.isCancelled {
            wasCancelled = true
        }
        
        let finalSuccessCount = successCount
        let finalFailureCount = failureCount
        let finalErrorMessage = firstError
        let priorWasCancelled = wasCancelled
        
        let cancelRequestedAtCompletion = await MainActor.run { [weak self] () -> Bool in
            guard let self else { return false }
            let cancelRequested = self.directImportProgress.cancelRequested
            self.publishDirectImportSummary(
                successCount: finalSuccessCount,
                failureCount: finalFailureCount,
                canceled: cancelRequested || priorWasCancelled,
                errorMessage: finalErrorMessage
            )
            return cancelRequested
        }
        
        if cancelRequestedAtCompletion {
            wasCancelled = true
        }
    }
    
    private func buildDirectImportDetailText(index: Int, total: Int, sizeDescription: String?) -> String {
        var parts: [String] = ["Item \(index) of \(total)"]
        if let sizeDescription = sizeDescription {
            parts.append(sizeDescription)
        }
        return parts.joined(separator: " • ")
    }
    
    private func fileSizeString(for url: URL, formatter: ByteCountFormatter) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSizeNumber = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return formatter.string(fromByteCount: fileSizeNumber.int64Value)
    }
    
    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "mpg", "mpeg", "hevc", "webm"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }
    
    @MainActor
    private func publishDirectImportSummary(successCount: Int, failureCount: Int, canceled: Bool, errorMessage: String?)
    {
        let message: String
        let notificationType: HideNotificationType
        
        if canceled {
            message = "Import canceled. Encrypted \(successCount) item(s) before canceling."
            notificationType = .info
        } else if failureCount == 0 {
            message = "Import complete. Encrypted \(successCount) item(s) into the album."
            notificationType = .success
        } else if successCount == 0 {
            message = errorMessage ?? "Import failed. Unable to import the selected files."
            notificationType = .failure
        } else {
            var summary = "Import completed with issues. Imported \(successCount) item(s); \(failureCount) failed."
            if let errorMessage = errorMessage, !errorMessage.isEmpty {
                summary += " \(errorMessage)"
            }
            message = summary
            notificationType = .info
        }
        
        hideNotification = HideNotification(
            message: message,
            type: notificationType,
            photos: nil
        )
        
        // Post system notification if enabled
        if enableImportNotifications && !canceled && (successCount > 0 || failureCount > 0) {
            postImportCompletionNotification(title: "Import Complete", body: message)
        }
    }
    
    private func postImportCompletionNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLog.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
    
#if DEBUG
    /// Development-only helper that wipes the app storage, user defaults and some
    /// keychain entries. This is only compiled into DEBUG builds and should NOT
    /// be present in production releases.
    ///
    /// Usage (from the Xcode debug console while running a DEBUG build):
    ///   expr -l Swift -- AlbumManager.shared.nukeAllData()
    /// or use the Swift REPL / `po` variant if you prefer.
    ///
    /// WARNING: This is destructive and irreversible. Only use in development.
    func nukeAllData() {
        AppLog.warning("Nuking all data (DEBUG only).")
        try? FileManager.default.removeItem(at: storage.baseURL)
        // Reset defaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // Reset keychain (simplified)
        let secItemClasses = [
            kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey,
            kSecClassIdentity,
        ]
        for itemClass in secItemClasses {
            let spec: [String: Any] = [kSecClass as String: itemClass]
            SecItemDelete(spec as CFDictionary)
        }
        // Re-init storage to recreate directories
        _ = AlbumStorage()
}
#endif
}

// MARK: - Import Operations

extension AlbumManager {
    /// Imports assets from Photo Library into the album
    func importAssets(_ assets: [PHAsset]) async {
        guard isUnlocked, cachedEncryptionKey != nil, cachedHMACKey != nil else {
            await MainActor.run {
                hideNotification = HideNotification(
                    message: "Unlock the album before importing from Photos.",
                    type: .failure,
                    photos: nil
                )
                importProgress.isImporting = false
                importProgress.statusMessage = "Import cancelled"
            }
            return
        }
        
        let successfulAssets = await importService.importAssets(assets) {
            [weak self]
            mediaSource, filename, dateTaken, sourceAlbum, assetIdentifier, mediaType, duration, location, isFavorite,
            progressHandler in
            guard let self = self else { throw AlbumError.albumNotInitialized }
            try await self.hidePhoto(
                mediaSource: mediaSource,
                filename: filename,
                dateTaken: dateTaken,
                sourceAlbum: sourceAlbum,
                assetIdentifier: assetIdentifier,
                mediaType: mediaType,
                duration: duration,
                location: location,
                isFavorite: isFavorite,
                progressHandler: progressHandler
            )
        }
        
        // Batch delete successfully albumed photos
        if !successfulAssets.isEmpty {
            await MainActor.run {
                importProgress.statusMessage = "Cleaning up library…"
            }
            
            // Deduplicate assets
            let uniqueAssets = Array(Set(successfulAssets))
            
            if cameraAutoRemoveFromPhotos {
                await withCheckedContinuation { continuation in
                    PhotosLibraryService.shared.batchDeleteAssets(uniqueAssets) { success in
                        if success {
                            AppLog.debugPublic("Successfully deleted \(uniqueAssets.count) photos from library")
                        } else {
                            AppLog.error("Failed to delete some photos from library")
                        }
                        continuation.resume()
                    }
                }
            } else {
                AppLog.debugPublic("Skipping library cleanup: auto-remove-from-Photos is disabled")
         }
            
            // Notify UI
            let ids = Set(uniqueAssets.map { $0.localIdentifier })
            let newlyHidden = hiddenPhotos.filter { photo in
                if let original = photo.originalAssetIdentifier {
                    return ids.contains(original)
                }
                return false
            }
            
            await MainActor.run {
                hideNotification = HideNotification(
                    message: "Hidden \(uniqueAssets.count) item(s). Moved to Recently Deleted.",
                    type: .success,
                    photos: newlyHidden
                )
            }
        }
        
        await MainActor.run {
            importProgress.isImporting = false
            importProgress.statusMessage = "Import complete"
        }
    }
    
    /// Checks the App Group "ImportInbox" for files shared via the Share Extension
    func checkAppGroupInbox() {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: FileConstants.appGroupIdentifier)
        else {
            return
        }
        
        let inboxURL = containerURL.appendingPathComponent(FileConstants.appGroupInboxName)
        guard FileManager.default.fileExists(atPath: inboxURL.path) else { return }
        
        // Performing directory/listing/move operations on the main thread can trigger
        // Xcode's Main Thread Checker because they may be blocking I/O. Run the heavy
        // work on a detached background Task and only call back to the album manager
        // for UI-related updates.
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil)
                guard !contents.isEmpty else { return }
                
                AppLog.debugPublic("Found \(contents.count) items in App Group inbox")
                
                // Move files to a temporary location to process them. Doing this on a
                // background task prevents blocking the UI during potentially large I/O.
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "InboxImport-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                var tempURLs: [URL] = []
                
                for url in contents {
                    let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.moveItem(at: url, to: destURL)
                    tempURLs.append(destURL)
                }
                
                // Kick off the import. startDirectImport itself schedules its heavy
                // work off the actor/Main thread as needed, so calling it from the
                // background task here is safe.
                self.startDirectImport(urls: tempURLs)
            } catch {
                AppLog.error("Error reading App Group inbox: \(error.localizedDescription)")
            }
        }
        // End checkAppGroupInbox background work
        
    }
        
        /// Performs a minimal manual iCloud/CloudKit check.
        /// Verifies that the user's iCloud account is available and that CloudKit
        /// can be accessed for the app's private container. This is a lightweight
        /// verification and not a full sync implementation.
    @MainActor public func performManualCloudSync() async throws -> Bool {
#if os(iOS)
    cloudSyncStatus = .syncing
    // Respect Lockdown Mode first — deny network/cloud operations while lockdown is active
    if lockdownModeEnabled {
        cloudSyncStatus = .failed
        lastCloudSync = Date()
        return false
    }
    
    // Check CloudKit account status for the configured container
    let ckContainer = CKContainer(identifier: FileConstants.iCloudContainerIdentifier)
    do {
        let status = try await ckContainer.accountStatus()
        guard status == .available else {
            cloudSyncStatus = .notAvailable
            cloudSyncErrorMessage = "iCloud account not available: \(status) — ensure user is signed into iCloud and CloudKit is permitted."
            return false
        }
    } catch {
        cloudSyncStatus = .notAvailable
        cloudSyncErrorMessage = "iCloud / CloudKit check failed: \(error.localizedDescription)"
        return false
    }
    
    // If the feature is disabled we report the check but do not proceed to a real upload
    if !encryptedCloudSyncEnabled {
        cloudSyncStatus = .failed
        cloudSyncErrorMessage = "Encrypted iCloud Sync is turned off in Preferences."
        lastCloudSync = Date()
        return false
    }
    
    // We're not performing a full sync here; the account check above is
    // a reasonable quick verification that CloudKit usage is possible.
    cloudSyncStatus = .idle
    cloudSyncErrorMessage = nil
    lastCloudSync = Date()
    return true
#else
    cloudSyncStatus = .notAvailable
    cloudSyncErrorMessage = "Encrypted iCloud sync is not available on this platform."
    return false
#endif
    // guard statement in case other platforms need to use same return path
        }
        
        /// Quick verification: write a small encrypted test record to the app's iCloud container
        /// then read it back and verify decryption. This is non-destructive and removes the
        /// temporary file after verification. Returns true on success.
    @MainActor public func performQuickEncryptedCloudVerification() async throws -> Bool {
#if os(iOS)
    // Respect Lockdown Mode first — deny verification while lockdown is active
    if lockdownModeEnabled {
        cloudVerificationStatus = .failed
        lastCloudVerification = Date()
        return false
    }
    
    cloudVerificationStatus = .failed
    
    // Must have CloudKit available (user signed in)
    let ckContainer = CKContainer(identifier: FileConstants.iCloudContainerIdentifier)
    do {
        let status = try await ckContainer.accountStatus()
        if status != .available {
            cloudVerificationStatus = .notAvailable
            cloudSyncErrorMessage = "iCloud account not available: \(status) — ensure user is signed into iCloud and CloudKit is permitted."
            lastCloudVerification = Date()
            return false
        }
    } catch {
        cloudVerificationStatus = .notAvailable
        cloudSyncErrorMessage = "iCloud / CloudKit check failed: \(error.localizedDescription)"
        lastCloudVerification = Date()
        return false
    }
    
    // Must have iCloud sync enabled to proceed
    guard encryptedCloudSyncEnabled else {
        cloudVerificationStatus = .failed
        cloudSyncErrorMessage = "Encrypted iCloud Sync is turned off in Preferences."
        lastCloudVerification = Date()
        return false
    }
    
    // Must be unlocked and have keys available
    guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey, isUnlocked else {
        cloudVerificationStatus = .failed
        lastCloudVerification = Date()
        return false
    }
    
    cloudVerificationStatus = .unknown
    
    // Use CloudKit private database for ephemeral verification files
    let privateDB = ckContainer.privateCloudDatabase
    
    let testPayload = ("EncryptedAlbum sync verification \(Date()) \(UUID().uuidString)").data(using: .utf8)!
    
    do {
        let (encryptedData, nonce, hmac) = try await cryptoService.encryptDataWithIntegrity(testPayload, encryptionKey: encryptionKey, hmacKey: hmacKey)
        
        // Build JSON container so it's easy to inspect in cloud and to read back
        let container: [String: String] = [
            "version": "1",
            "nonce": nonce.base64EncodedString(),
            "hmac": hmac.base64EncodedString(),
            "payload": encryptedData.base64EncodedString()
        ]
        
        let jsonData = try JSONEncoder().encode(container)
        
        // Create a CloudKit record with a data field for verification.
        let record = CKRecord(recordType: "EncryptedAlbumVerification")
        record["payload"] = jsonData as NSData
        
        // Save the record into the private database
        let saved = try await privateDB.save(record)
        // Immediately read it back
        let fetched = try await privateDB.record(for: saved.recordID)
        guard let fetchedData = fetched["payload"] as? Data else {
            throw AlbumError.encryptionFailed(reason: "Verification record missing payload")
        }
        let decoded = try JSONDecoder().decode([String: String].self, from: fetchedData)
        
        guard let nonceB64 = decoded["nonce"], let payloadB64 = decoded["payload"], let hmacB64 = decoded["hmac"],
              let nonceData = Data(base64Encoded: nonceB64), let payloadData = Data(base64Encoded: payloadB64), let hmacData = Data(base64Encoded: hmacB64)
        else {
            throw AlbumError.encryptionFailed(reason: "Invalid verification container format")
        }
        
        // Verify and decrypt
        let verified = try await cryptoService.decryptDataWithIntegrity(payloadData, nonce: nonceData, hmac: hmacData, encryptionKey: encryptionKey, hmacKey: hmacKey)
        
        // Clean up created record
        try? await privateDB.deleteRecord(withID: saved.recordID)
        
        // Compare payloads
        if verified == testPayload {
            cloudVerificationStatus = .success
            lastCloudVerification = Date()
            return true
        } else {
            cloudVerificationStatus = .failed
            lastCloudVerification = Date()
            return false
        }
    } catch {
        AppLog.error("iCloud verification failed: \(error.localizedDescription)")
        cloudVerificationStatus = .failed
        cloudSyncErrorMessage = "iCloud verification failed: \(error.localizedDescription)"
        lastCloudVerification = Date()
        return false
    }
#else
    cloudVerificationStatus = .notAvailable
    cloudSyncErrorMessage = "Encrypted iCloud sync is not available on this platform."
    lastCloudVerification = Date()
    return false
#endif
        }
        
    // MARK: - Decoy Password Management
        
    /// Sets the decoy password hash in UserDefaults
    public func setDecoyPassword(_ password: String) {
        let hash = SHA256.hash(data: password.data(using: .utf8)!).compactMap { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hash, forKey: "decoyPasswordHash")
    }

    /// Clears the decoy password from UserDefaults
    public func clearDecoyPassword() {
        UserDefaults.standard.removeObject(forKey: "decoyPasswordHash")
    }

}
