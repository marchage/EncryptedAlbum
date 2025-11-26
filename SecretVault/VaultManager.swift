import AVFoundation
import Combine
import CryptoKit
import Foundation
import LocalAuthentication
import SwiftUI
import Photos
import ImageIO

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
            #if DEBUG
            print("Warning: mlock failed with error: \(errno)")
            #endif
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

enum MediaType: String, Codable {
    case photo
    case video
}

/// Describes how raw media should be read when encrypting into the vault.
enum MediaSource {
    case data(Data)
    case fileURL(URL)
}

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

/// Tracks the state of direct file imports triggered from macOS file picker
@MainActor
class DirectImportProgress: ObservableObject {
    @Published var isImporting: Bool = false
    @Published var statusMessage: String = ""
    @Published var detailMessage: String = ""
    @Published var itemsProcessed: Int = 0
    @Published var itemsTotal: Int = 0
    @Published var bytesProcessed: Int64 = 0
    @Published var bytesTotal: Int64 = 0
    @Published var cancelRequested: Bool = false
    private var lastBytesUpdateTime: CFAbsoluteTime = 0
    private var lastReportedBytes: Int64 = 0

    func reset(totalItems: Int) {
        isImporting = true
        statusMessage = "Preparing import…"
        detailMessage = "\(totalItems) item(s)"
        itemsProcessed = 0
        itemsTotal = totalItems
        bytesProcessed = 0
        bytesTotal = 0
        cancelRequested = false
        lastBytesUpdateTime = 0
        lastReportedBytes = 0
    }

    func finish() {
        isImporting = false
        statusMessage = ""
        detailMessage = ""
        itemsProcessed = 0
        itemsTotal = 0
        bytesProcessed = 0
        bytesTotal = 0
        cancelRequested = false
        lastBytesUpdateTime = 0
        lastReportedBytes = 0
    }

    func throttledUpdateBytesProcessed(_ value: Int64) {
        let clampedValue = max(0, value)
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastBytesUpdateTime
        let byteDelta = abs(clampedValue - lastReportedBytes)

        let minimumInterval: CFTimeInterval = 0.05
        let minimumByteDelta = max(bytesTotal / 200, Int64(128 * 1024))

        if lastBytesUpdateTime == 0
            || elapsed >= minimumInterval
            || byteDelta >= minimumByteDelta
            || clampedValue >= bytesTotal
        {
            bytesProcessed = min(clampedValue, bytesTotal > 0 ? bytesTotal : clampedValue)
            lastReportedBytes = clampedValue
            lastBytesUpdateTime = now
        }
    }

    func forceUpdateBytesProcessed(_ value: Int64) {
        let clampedValue = max(0, value)
        bytesProcessed = min(clampedValue, bytesTotal > 0 ? bytesTotal : clampedValue)
        lastReportedBytes = clampedValue
        lastBytesUpdateTime = CFAbsoluteTimeGetCurrent()
    }
}


// Notification types for hide/restore operations
enum HideNotificationType {
    case success
    case failure
    case info
}

/// Lightweight notification model published by `VaultManager` to inform the UI
struct HideNotification {
    let message: String
    let type: HideNotificationType
    let photos: [SecurePhoto]?
}

struct SecurePhoto: Identifiable, Codable {
    let id: UUID
    var encryptedDataPath: String
    var thumbnailPath: String
    var encryptedThumbnailPath: String?
    var filename: String
    var dateAdded: Date
    var dateTaken: Date?
    var sourceAlbum: String?
    var vaultAlbum: String?  // Custom album within the vault
    var fileSize: Int64
    var originalAssetIdentifier: String?  // To track the original Photos library asset
    var mediaType: MediaType  // Photo or video
    var duration: TimeInterval?  // For videos

    // Metadata preservation
    var location: Location?
    var isFavorite: Bool?

    struct Location: Codable {
        let latitude: Double
        let longitude: Double
    }

    init(
        id: UUID = UUID(), encryptedDataPath: String, thumbnailPath: String, encryptedThumbnailPath: String? = nil,
        filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, vaultAlbum: String? = nil,
        fileSize: Int64 = 0, originalAssetIdentifier: String? = nil, mediaType: MediaType = .photo,
        duration: TimeInterval? = nil, location: Location? = nil, isFavorite: Bool? = nil
    ) {
        self.id = id
        self.encryptedDataPath = encryptedDataPath
        self.thumbnailPath = thumbnailPath
        self.encryptedThumbnailPath = encryptedThumbnailPath
        self.filename = filename
        self.dateAdded = Date()
        self.dateTaken = dateTaken
        self.sourceAlbum = sourceAlbum
        self.vaultAlbum = vaultAlbum
        self.fileSize = fileSize
        self.originalAssetIdentifier = originalAssetIdentifier
        self.mediaType = mediaType
        self.duration = duration
        self.location = location
        self.isFavorite = isFavorite
    }
}

// MARK: - Vault Manager

class VaultManager: ObservableObject {
    @MainActor static let shared = VaultManager()

    // Services
    private let cryptoService: CryptoService
    private let fileService: FileService
    private let securityService: SecurityService
    private let passwordService: PasswordService
    private let journalService: PasswordChangeJournalService
    private let importService: ImportService
    private let vaultState: VaultState
    private let storage: VaultStorage
    private var restorationProgressCancellable: AnyCancellable?
    private var importProgressCancellable: AnyCancellable?

    // Legacy properties for backward compatibility
    @Published var hiddenPhotos: [SecurePhoto] = []
    @Published var isUnlocked = false
    @Published var showUnlockPrompt = false
    @Published var passwordHash: String = ""
    @Published var passwordSalt: String = ""  // Salt for password hashing
    @Published var securityVersion: Int = 1   // 1 = Legacy (Key as Hash), 2 = Secure (Verifier)
    @Published var restorationProgress = RestorationProgress()
    @Published var importProgress = ImportProgress()
    @MainActor let directImportProgress: DirectImportProgress
    private var directImportTask: Task<Void, Never>?
    
    // Vault location is now fixed and managed by VaultStorage
    var vaultBaseURL: URL {
        return storage.baseURL
    }
    
    @Published var hideNotification: HideNotification? = nil
    @Published var lastActivity: Date = Date()
    @Published var viewRefreshId = UUID()  // Force view refresh when needed
    @Published var secureDeletionEnabled: Bool = true // Default to true for security
    @Published var authenticationPromptActive: Bool = false

    var isBusy: Bool {
        return importProgress.isImporting || restorationProgress.isRestoring
    }

    /// Idle timeout in seconds before automatically locking the vault when unlocked.
    /// Default is 600 seconds (10 minutes).
    let idleTimeout: TimeInterval = CryptoConstants.idleTimeout

    // Rate limiting for unlock attempts
    private var failedUnlockAttempts: Int = 0
    private var lastUnlockAttemptTime: Date?
    private var failedBiometricAttempts: Int = 0
    private let maxBiometricAttempts: Int = CryptoConstants.biometricMaxAttempts

    private var photosDirectoryURL: URL { storage.photosDirectory }
    private var photosMetadataFileURL: URL { storage.metadataFile }
    private var settingsFileURL: URL { storage.settingsFile }
    private func resolveURL(for storedPath: String) -> URL { storage.resolvePath(storedPath) }
    private func relativePath(for absoluteURL: URL) -> String { storage.relativePath(for: absoluteURL) }
    private func normalizedStoredPath(_ storedPath: String) -> String { storage.normalizedStoredPath(storedPath) }
    private var idleTimer: Timer?
    private var idleTimerSuspendCount: Int = 0

    // Serial queue for thread-safe operations
    private let vaultQueue = DispatchQueue(label: "biz.front-end.secretvault.vaultQueue", qos: .userInitiated)

    // Derived keys cache (in-memory only, never persisted)
    private var cachedMasterKey: SymmetricKey?
    private var cachedEncryptionKey: SymmetricKey?
    private var cachedHMACKey: SymmetricKey?

    // Helper to detect if we are running unit tests
    private var isRunningUnitTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @MainActor
    init(storage: VaultStorage? = nil) {
        let progress = ImportProgress()
        self.directImportProgress = DirectImportProgress()
        importService = ImportService(progress: progress)

        // Initialize services
        cryptoService = CryptoService()
        securityService = SecurityService(cryptoService: cryptoService)
        passwordService = PasswordService(cryptoService: cryptoService, securityService: securityService)
        journalService = PasswordChangeJournalService()
        fileService = FileService(cryptoService: cryptoService)
        vaultState = VaultState()
        self.storage = storage ?? VaultStorage()
        
        self.importProgress = progress
        
        fileService.cleanupTemporaryArtifacts()
        // vaultBaseURL is now computed from storage.baseURL

        #if DEBUG
        // Handle Test Mode Reset
        print("DEBUG: CommandLine arguments: \(CommandLine.arguments)")
        if CommandLine.arguments.contains("--reset-state") {
            nukeAllData()
        }
        #endif

        #if DEBUG
            print("Loading settings from: \(settingsFileURL.path)")
        #endif
        
        // Load settings synchronously to ensure state is ready before init completes
        // We use the vaultQueue to ensure thread safety, though in init we are unique.
        // However, loadSettings is also called elsewhere, so the method itself handles sync.
        self.loadSettings()
        
        restorationProgressCancellable = restorationProgress.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        importProgressCancellable = importProgress.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Settings loaded, checking password status
        if !passwordHash.isEmpty {
            showUnlockPrompt = true
        }
    }

    // MARK: - Step-up Authentication

    /// Performs a step-up authentication check for sensitive vault operations.
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
            let reason = "Authenticate to perform a sensitive vault operation."
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
                    alert.informativeText = "Enter your SecretVault password to proceed with this sensitive operation."
                    alert.alertStyle = .warning

                    let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
                    textField.placeholderString = "Vault Password"
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

    /// Sets up the vault password with proper validation and secure hashing.
    /// - Parameter password: The password to set (must be 8-128 characters)
    /// - Returns: `true` on success, `false` if validation fails
    func setupPassword(_ password: String) async throws {
        // Verify system entropy before generating keys
        let health = try await securityService.performSecurityHealthCheck()
        guard health.randomGenerationHealthy else {
            throw VaultError.securityHealthCheckFailed(reason: "Insufficient system entropy for secure key generation")
        }

        try passwordService.validatePassword(password)

        let (hash, salt) = try await passwordService.hashPassword(password)
        try passwordService.storePasswordHash(hash, salt: salt)

        await MainActor.run {
            passwordHash = hash.map { String(format: "%02x", $0) }.joined()
            passwordSalt = salt.base64EncodedString()
            securityVersion = 2 // New setups are always V2

            cachedMasterKey = nil
            cachedEncryptionKey = nil
            cachedHMACKey = nil
            saveSettings()

            // Store password for biometric unlock
            saveBiometricPassword(password)
            UserDefaults.standard.set(true, forKey: "biometricConfigured")
        }
        
        #if os(iOS)
        // On iOS, verify biometric storage by attempting to retrieve it
        // This triggers Face ID prompt immediately to confirm biometric works
        if !isRunningUnitTests {
            if await getBiometricPassword() == nil {
                throw VaultError.biometricFailed
            }
        }
        #endif
    }

    /// Attempts to unlock the vault with the provided password.
    /// - Parameter password: The password to verify
    /// - Returns: `true` if unlock successful, `false` otherwise
    func unlock(password: String) async throws {
        // Rate limiting: exponential backoff on failed attempts
        if failedUnlockAttempts > 0, let lastAttempt = lastUnlockAttemptTime {
            let requiredDelay = calculateUnlockDelay()
            let elapsed = Date().timeIntervalSince(lastAttempt)

            if elapsed < requiredDelay {
                let remaining = Int(requiredDelay - elapsed)
                throw VaultError.rateLimitExceeded(retryAfter: TimeInterval(remaining))
            }
        }

        lastUnlockAttemptTime = Date()

        // Verify password
        guard let (storedHash, storedSalt) = try passwordService.retrievePasswordCredentials() else {
            failedUnlockAttempts += 1
            throw VaultError.vaultNotInitialized
        }

        // Check security version and verify accordingly
        let isValid: Bool
        if securityVersion < 2 {
            // Legacy verification (V1)
            isValid = try await passwordService.verifyLegacyPassword(password, against: storedHash, salt: storedSalt)
            
            if isValid {
                // MIGRATE TO V2
                let (newVerifier, _) = try await passwordService.hashPassword(password) // Uses new verifier logic
                // Salt remains the same to avoid re-encrypting data (we just change the stored verifier)
                try passwordService.storePasswordHash(newVerifier, salt: storedSalt)
                
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
                saveBiometricPassword(password)
            }
            #else
            // On iOS, avoid checking keychain (triggers prompt). Only save if we think it's not configured.
            if !UserDefaults.standard.bool(forKey: "biometricConfigured") {
                 saveBiometricPassword(password)
                 UserDefaults.standard.set(true, forKey: "biometricConfigured")
            }
            #endif

            await MainActor.run {
                isUnlocked = true
            }
            try await loadPhotos()
            await MainActor.run {
                lastActivity = Date()
            }
            startIdleTimer()

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
            throw VaultError.invalidPassword
        }
    }

    /// Changes the vault password and re-encrypts all data.
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
            throw VaultError.securityHealthCheckFailed(reason: "Insufficient system entropy for secure key generation")
        }

        // 1. Prepare: Verify old password and generate new keys
        progressHandler?("Verifying and generating keys...")
        let (newVerifier, newSalt, newEncryptionKey, newHMACKey) = try await passwordService.preparePasswordChange(
            currentPassword: currentPassword,
            newPassword: newPassword
        )
        
        guard let oldEncryptionKey = cachedEncryptionKey, let oldHMACKey = cachedHMACKey else {
            throw VaultError.vaultNotInitialized
        }
        
        // 2. Initialize or Resume Journal
        let photos = hiddenPhotos // Capture current list
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
        if let existingJournal = try? journalService.readJournal(from: vaultBaseURL),
           existingJournal.status != .completed,
           existingJournal.oldPasswordHashPrefix == oldHashPrefix,
           existingJournal.newPasswordHashPrefix == newHashPrefix {
            
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
            try journalService.writeJournal(journal, to: vaultBaseURL)
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
                        mediaType: .photo, // Thumbnails are always images
                        oldEncryptionKey: oldEncryptionKey,
                        oldHMACKey: oldHMACKey,
                        newEncryptionKey: newEncryptionKey,
                        newHMACKey: newHMACKey
                    )
                }
                
                // Update Journal
                journal.markProcessed(filename)
                try journalService.writeJournal(journal, to: vaultBaseURL)
            }
        } catch {
            // If any error occurs during re-encryption, mark journal as failed so we can recover later
            journal.status = .failed
            try? journalService.writeJournal(journal, to: vaultBaseURL)
            throw error
        }
        
        // 4. Commit: Store new password verifier and salt
        progressHandler?("Saving new password...")
        try passwordService.storePasswordHash(newVerifier, salt: newSalt)
        
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
            
            // 7. Update biometric password
            saveBiometricPassword(newPassword)
        }
        
        // 8. Cleanup Journal
        try journalService.deleteJournal(from: vaultBaseURL)
        
        progressHandler?("Password changed successfully")
    }

    /// Checks if a password change operation was interrupted and needs recovery.
    /// - Returns: The journal if an interrupted operation exists, nil otherwise.
    func checkForInterruptedPasswordChange() -> PasswordChangeJournal? {
        guard let journal = try? journalService.readJournal(from: vaultBaseURL) else {
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

    /// Locks the vault by clearing cached keys and resetting state
    func lock() {
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
        startIdleTimer()
    }

    /// Clears transient UI state and temporary files when the app is heading into the background.
    func prepareForBackground() {
        vaultQueue.async { [weak self] in
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
                #if DEBUG
                print("⏸️  Idle timer check skipped (suspended)")
                #endif
                return
            }

            let elapsed = Date().timeIntervalSince(self.lastActivity)
            if elapsed > self.idleTimeout {
                #if DEBUG
                print("🔐 Auto-locking vault after \(Int(elapsed))s of inactivity")
                #endif
                self.lock()
            }
        }
        if let idleTimer = idleTimer {
            RunLoop.main.add(idleTimer, forMode: .common)
        }
    }

    /// Suspends the idle timer to prevent auto-lock during long operations (e.g., imports)
    @MainActor
    func suspendIdleTimer() {
        idleTimerSuspendCount += 1
        #if DEBUG
        if idleTimerSuspendCount == 1 {
            print("🔒 Idle timer SUSPENDED - vault will not auto-lock")
        } else {
            print("🔒 Idle timer suspension depth now \(idleTimerSuspendCount)")
        }
        #endif
    }

    /// Resumes the idle timer after long operations complete
    @MainActor
    func resumeIdleTimer() {
        guard idleTimerSuspendCount > 0 else {
            #if DEBUG
                print("⚠️ resumeIdleTimer called with no active suspensions")
            #endif
            return
        }

        idleTimerSuspendCount -= 1
        if idleTimerSuspendCount == 0 {
            lastActivity = Date() // Reset activity timestamp
            #if DEBUG
                print("🔓 Idle timer RESUMED - vault will auto-lock after \(Int(idleTimeout))s of inactivity")
            #endif
        } else {
            #if DEBUG
                print("🔐 Idle timer suspension depth decreased to \(idleTimerSuspendCount)")
            #endif
        }
    }

    /// Encrypts and stores a photo or video in the vault using either in-memory data or a file URL.
    func hidePhoto(
        mediaSource: MediaSource, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil,
        assetIdentifier: String? = nil, mediaType: MediaType = .photo, duration: TimeInterval? = nil,
        location: SecurePhoto.Location? = nil, isFavorite: Bool? = nil, progressHandler: ((Int64) async -> Void)? = nil
    ) async throws {
        await MainActor.run {
            lastActivity = Date()
        }

        guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey else {
            throw VaultError.vaultNotInitialized
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
            throw VaultError.fileTooLarge(size: fileSize, maxSize: CryptoConstants.maxMediaFileSize)
        }

        var isDuplicate = false
        if let assetId = assetIdentifier {
            // Access hiddenPhotos on MainActor to avoid race conditions
            isDuplicate = await MainActor.run {
                hiddenPhotos.contains(where: { $0.originalAssetIdentifier == assetId })
            }
            
            if isDuplicate {
                #if DEBUG
                    print("Media already hidden: \(filename) (assetId: \(assetId))")
                #endif
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
            throw VaultError.thumbnailGenerationFailed(
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
                #if DEBUG
                    print("Duplicate detected in final check, skipping: \(filename)")
                #endif
                return
            }

            self.hiddenPhotos.append(photo)
            self.vaultQueue.async {
                self.savePhotos()
            }
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

    /// Decrypts a photo or video from the vault.
    /// - Parameter photo: The SecurePhoto record to decrypt
    /// - Returns: Decrypted media data
    /// - Throws: Error if file reading or decryption fails
    func decryptPhoto(_ photo: SecurePhoto) async throws -> Data {
        // Use FileService to load and decrypt the encrypted file
        guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey else {
            throw VaultError.vaultNotInitialized
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
            throw VaultError.vaultNotInitialized
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

    func decryptThumbnail(for photo: SecurePhoto) async throws -> Data {
        guard let encryptionKey = cachedEncryptionKey, let hmacKey = cachedHMACKey else {
            throw VaultError.vaultNotInitialized
        }
        // Option 1: be resilient to missing thumbnail files and fall back gracefully.
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            let url = resolveURL(for: encryptedThumbnailPath)
            if !FileManager.default.fileExists(atPath: url.path) {
                print(
                    "[VaultManager] decryptThumbnail: encrypted thumbnail missing for id=\(photo.id)."
                )
            } else {
                do {
                    // Use FileService to load and decrypt the encrypted thumbnail
                    let filename = url.lastPathComponent
                    return try await fileService.loadEncryptedFile(
                        filename: filename,
                        from: url.deletingLastPathComponent(),
                        encryptionKey: encryptionKey, hmacKey: hmacKey)
                } catch {
                    #if DEBUG
                    print(
                        "[VaultManager] decryptThumbnail: error reading encrypted thumbnail for id=\(photo.id): \(error)."
                    )
                    #endif
                }
            }
        }

        // As a last resort, return empty Data so the UI can show a placeholder.
        return Data()
    }

    /// Permanently deletes a photo or video from the vault.
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
            #if DEBUG
                print("Secure deletion failed, using standard deletion: \(error)")
            #endif
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
    func restorePhotoToLibrary(_ photo: SecurePhoto) async throws {
        try await batchRestorePhotos([photo], restoreToSourceAlbum: true)
    }

    /// Helper method to save a temporary file to Photos library and delete the photo from vault on success.
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
                    print("Media restored to library with metadata: \(photo.filename)")
                    self.deletePhoto(photo)
                    continuation.resume(returning: ())
                } else {
                    let reason = libraryError?.localizedDescription ?? "Photos refused to import this item"
                    print("Failed to restore media to library: \(photo.filename) – \(reason)")
                    continuation.resume(throwing: VaultError.fileWriteFailed(path: photo.filename, reason: reason))
                }
            }
        }
    }

    /// Restores multiple photos/videos from the vault to the Photos library.
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

        print("🔄 Starting batch restore of \(photos.count) items grouped into \(albumGroups.count) albums")
        var wasCancelled = false

        do {
            for (targetAlbum, photosInGroup) in albumGroups {
                try Task.checkCancellation()
                print("📁 Processing group: \(targetAlbum ?? "Library") with \(photosInGroup.count) items")
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
            print(
                "📊 Restoration complete: \(success)/\(total) successful, \(failed) failed (successful items already removed from vault)"
            )
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
                print("  ❌ Failed to process \(photo.filename): \(error)")
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

    /// Removes duplicate photos from the vault based on asset identifiers.
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
                print("Removed \(duplicatesToDelete.count) duplicate photos")
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
                kCGImageSourceThumbnailMaxPixelSize: 300
            ]
            
            guard let source = CGImageSourceCreateWithData(mediaData as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return Data()
            }
            
            #if os(macOS)
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
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
                kCGImageSourceThumbnailMaxPixelSize: 300
            ]
            
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return Data()
            }
            
            #if os(macOS)
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
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
            #if DEBUG
                print("Video data size invalid: \(videoData.count) bytes")
            #endif
            return Data()
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")

        do {
            try videoData.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let asset = AVAsset(url: tempURL)
            return await generateVideoThumbnail(fromAsset: asset)
        } catch {
            #if DEBUG
                print("Failed to generate video thumbnail: \(error)")
            #endif
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
                #if DEBUG
                    print("No video tracks found in asset")
                #endif
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
            #if DEBUG
                print("Failed to generate video thumbnail: \(error)")
            #endif
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

    private func savePhotos() {
        guard let data = try? JSONEncoder().encode(hiddenPhotos) else { return }
        #if DEBUG
            print("savePhotos: writing \(hiddenPhotos.count) items to \(photosMetadataFileURL.path)")
        #endif
        try? data.write(to: photosMetadataFileURL)
    }

    func saveSettings() {
        // Capture values on the current thread (Main Thread) to avoid race conditions
        // when accessing @Published properties inside the background queue block
        let version = String(securityVersion)
        let secureDelete = String(secureDeletionEnabled)

        vaultQueue.sync {
            // Ensure vault directory exists before saving
            do {
                try FileManager.default.createDirectory(at: vaultBaseURL, withIntermediateDirectories: true)
            } catch {
                #if DEBUG
                    print("Failed to create vault directory: \(error)")
                #endif
                return
            }

            let settings: [String: String] = [
                "securityVersion": version,
                "secureDeletionEnabled": secureDelete
            ]

            do {
                let data = try JSONEncoder().encode(settings)
                try data.write(to: settingsFileURL, options: .atomic)
                #if DEBUG
                    print("Successfully saved settings to: \(settingsFileURL.path)")
                #endif
            } catch {
                #if DEBUG
                    print("Failed to save settings: \(error)")
                #endif
            }
        }
    }

    private func loadSettings() {
        vaultQueue.sync {
            #if DEBUG
                print("Attempting to load settings from: \(settingsFileURL.path)")
            #endif
            
            // Load credentials from Keychain
            if let credentials = try? passwordService.retrievePasswordCredentials() {
                passwordHash = credentials.hash.map { String(format: "%02x", $0) }.joined()
                passwordSalt = credentials.salt.base64EncodedString()
                #if DEBUG
                    print("Loaded credentials from Keychain")
                #endif
            } else {
                #if DEBUG
                    print("No credentials found in Keychain")
                #endif
            }

            guard let data = try? Data(contentsOf: settingsFileURL),
                let settings = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                #if DEBUG
                    print("No settings file found or failed to decode")
                #endif
                return
            }

            #if DEBUG
                print("Loaded settings: [REDACTED]")
            #endif
            
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
        }
    }

    // MARK: - Vault Location Management

    // Vault location is now fixed to the App Sandbox Container.
    // Legacy moveVault functionality has been removed to ensure security and data integrity.

    // MARK: - Biometric Authentication Helpers

    func saveBiometricPassword(_ password: String) {
        #if DEBUG
            // Saving biometric password
        #endif
        do {
            try securityService.storeBiometricPassword(password)
        } catch {
            #if DEBUG
                print("Failed to store biometric password: \(error)")
            #endif
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
            throw VaultError.biometricNotAvailable
        }
        return password
    }

    /// Validates crypto operations by performing encryption/decryption round-trip test.
    /// - Returns: `true` if validation successful, `false` otherwise
    func validateCryptoOperations() async -> Bool {
        let testData = "SecretVault crypto validation test data".data(using: .utf8)!

        // Test encryption
        do {
            let (encryptedData, nonce, hmac) = try await cryptoService.encryptDataWithIntegrity(
                testData, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
            guard !encryptedData.isEmpty else {
                #if DEBUG
                    print("Crypto validation failed: encryption returned empty data")
                #endif
                return false
            }

            // Test decryption
            let decrypted = try await cryptoService.decryptDataWithIntegrity(
                encryptedData, nonce: nonce, hmac: hmac, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
            guard !decrypted.isEmpty else {
                #if DEBUG
                    print("Crypto validation failed: decryption returned empty data")
                #endif
                return false
            }

            // Verify round-trip integrity
            guard decrypted == testData else {
                #if DEBUG
                    print("Crypto validation failed: decrypted data doesn't match original")
                #endif
                return false
            }
        } catch {
            #if DEBUG
                print("Crypto validation failed: \(error)")
            #endif
            return false
        }

        // Test key derivation consistency
        guard await validateKeyDerivationConsistency() else {
            #if DEBUG
                print("Crypto validation failed: key derivation consistency check")
            #endif
            return false
        }

        #if DEBUG
            print("Crypto validation successful")
        #endif
        return true
    }

    /// Validates that cached keys are available and valid
    private func validateKeyDerivationConsistency() async -> Bool {
        // Check that we have cached keys
        guard cachedEncryptionKey != nil && cachedHMACKey != nil else {
            #if DEBUG
                print("Key validation failed: cached keys not available")
            #endif
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
                #if DEBUG
                    print("Key validation failed: round-trip test failed")
                #endif
                return false
            }
        } catch {
            #if DEBUG
                print("Key validation failed: crypto operation failed - \(error)")
            #endif
            return false
        }

        return true
    }

    // MARK: - New Refactored Methods

    /// Validates the integrity of stored vault data including settings and photo metadata
    /// - Returns: Array of validation errors, empty if all checks pass
    func validateVaultIntegrity() async throws {
        try await securityService.validateVaultIntegrity(
            vaultURL: vaultBaseURL, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!, expectedMetadata: nil)
    }

    /// Performs comprehensive security health checks on the vault
    /// - Returns: Security health report
    func performSecurityHealthCheck() async throws -> SecurityHealthReport {
        return try await securityService.performSecurityHealthCheck()
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

// MARK: - Direct File Import (macOS)

extension VaultManager {
    #if os(macOS)
        /// Starts encrypting files directly from disk into the vault
        func startDirectImport(urls: [URL]) {
            guard !urls.isEmpty else { return }

            guard isUnlocked, cachedEncryptionKey != nil, cachedHMACKey != nil else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.hideNotification = HideNotification(
                        message: "Unlock the vault before importing files.",
                        type: .failure,
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
                suspendIdleTimer()
            }

            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.directImportProgress.finish()
                    self.resumeIdleTimer()
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
                        sourceAlbum: "Captured to Vault",
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
        private func publishDirectImportSummary(successCount: Int, failureCount: Int, canceled: Bool, errorMessage: String?) {
            let message: String
            let notificationType: HideNotificationType

            if canceled {
                message = "Import canceled. Encrypted \(successCount) item(s) before canceling."
                notificationType = .info
            } else if failureCount == 0 {
                message = "Import complete. Encrypted \(successCount) item(s) into the vault."
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
        }
    #endif
}

// MARK: - Import Operations

extension VaultManager {
    /// Imports assets from Photo Library into the vault
    func importAssets(_ assets: [PHAsset]) async {
        guard isUnlocked, cachedEncryptionKey != nil, cachedHMACKey != nil else {
            await MainActor.run {
                hideNotification = HideNotification(
                    message: "Unlock the vault before importing from Photos.",
                    type: .failure,
                    photos: nil
                )
                importProgress.isImporting = false
                importProgress.statusMessage = "Import cancelled"
            }
            return
        }

        let successfulAssets = await importService.importAssets(assets) { [weak self] mediaSource, filename, dateTaken, sourceAlbum, assetIdentifier, mediaType, duration, location, isFavorite, progressHandler in
            guard let self = self else { throw VaultError.vaultNotInitialized }
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

        // Batch delete successfully vaulted photos
        if !successfulAssets.isEmpty {
            await MainActor.run {
                importProgress.statusMessage = "Cleaning up library…"
            }
            
            // Deduplicate assets
            let uniqueAssets = Array(Set(successfulAssets))
            
            await withCheckedContinuation { continuation in
                PhotosLibraryService.shared.batchDeleteAssets(uniqueAssets) { success in
                    if success {
                        print("Successfully deleted \(uniqueAssets.count) photos from library")
                    } else {
                        print("Failed to delete some photos from library")
                    }
                    continuation.resume()
                }
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

    #if DEBUG
    /// Completely wipes all vault data, settings, and keychain items.
    /// DANGER: This is irreversible. Only for development/testing.
    func nukeAllData() {
        print("☢️ NUKING ALL VAULT DATA ☢️")
        
        // 1. Delete all files
        try? FileManager.default.removeItem(at: storage.baseURL)
        
        // 2. Reset in-memory state
        DispatchQueue.main.async {
            self.hiddenPhotos = []
            self.passwordHash = ""
            self.passwordSalt = ""
            self.securityVersion = 2
            self.isUnlocked = false
            self.showUnlockPrompt = false
        }
        
        cachedMasterKey = nil
        cachedEncryptionKey = nil
        cachedHMACKey = nil
        
        // 3. Clear Keychain
        try? passwordService.clearPasswordCredentials()
        try? securityService.clearBiometricPassword()
        
        // 4. Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "biometricConfigured")
        
        print("✅ Vault nuked successfully")
    }
    #endif
}

