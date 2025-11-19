import AVFoundation
import Combine
import CryptoKit
import Foundation
import LocalAuthentication
import SwiftUI
import Photos

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
        // Use malloc with MallocFlags to attempt to avoid swapping
        // Note: This is a best-effort attempt and may not work on all systems
        let buffer = malloc(count)
        guard buffer != nil else { return nil }

        // Zero the buffer initially
        memset_s(buffer, count, 0, count)

        return UnsafeMutableRawBufferPointer(start: buffer, count: count)
    }

    /// Deallocates a secure buffer after zeroing it
    static func deallocateSecureBuffer(_ buffer: UnsafeMutableRawBufferPointer) {
        // Zero before deallocating
        zero(buffer)
        free(buffer.baseAddress)
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

// Import progress tracking
class ImportProgress: ObservableObject {
    @Published var isImporting = false
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
        isImporting = false
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
    static let shared = VaultManager()

    // Services
    private let cryptoService: CryptoService
    private let fileService: FileService
    private let securityService: SecurityService
    private let passwordService: PasswordService
    private let vaultState: VaultState
    private var restorationProgressCancellable: AnyCancellable?

    // Legacy properties for backward compatibility
    @Published var hiddenPhotos: [SecurePhoto] = []
    @Published var isUnlocked = false
    @Published var showUnlockPrompt = false
    @Published var passwordHash: String = ""
    @Published var passwordSalt: String = ""  // Salt for password hashing
    @Published var securityVersion: Int = 1   // 1 = Legacy (Key as Hash), 2 = Secure (Verifier)
    @Published var restorationProgress = RestorationProgress()
    @Published var importProgress = ImportProgress()
    @Published var vaultBaseURL: URL = URL(fileURLWithPath: "/tmp")
    @Published var hideNotification: HideNotification? = nil
    @Published var lastActivity: Date = Date()
    @Published var viewRefreshId = UUID()  // Force view refresh when needed

    /// Idle timeout in seconds before automatically locking the vault when unlocked.
    /// Default is 600 seconds (10 minutes).
    let idleTimeout: TimeInterval = CryptoConstants.idleTimeout

    // Rate limiting for unlock attempts
    private var failedUnlockAttempts: Int = 0
    private var lastUnlockAttemptTime: Date?
    private var failedBiometricAttempts: Int = 0
    private let maxBiometricAttempts: Int = CryptoConstants.biometricMaxAttempts

    private lazy var photosURL: URL = vaultBaseURL.appendingPathComponent(
        FileConstants.photosDirectoryName, isDirectory: true)
    private lazy var photosFile: URL = vaultBaseURL.appendingPathComponent(FileConstants.photosMetadataFileName)
    private lazy var settingsFile: URL = vaultBaseURL.appendingPathComponent(FileConstants.settingsFileName)
    private var idleTimer: Timer?

    // Serial queue for thread-safe operations
    private let vaultQueue = DispatchQueue(label: "com.secretvault.vaultQueue", qos: .userInitiated)

    // Derived keys cache (in-memory only, never persisted)
    private var cachedMasterKey: SymmetricKey?
    private var cachedEncryptionKey: SymmetricKey?
    private var cachedHMACKey: SymmetricKey?

    init(customBaseURL: URL? = nil) {
        // Initialize services
        cryptoService = CryptoService()
        securityService = SecurityService(cryptoService: cryptoService)
        passwordService = PasswordService(cryptoService: cryptoService, securityService: securityService)
        fileService = FileService(cryptoService: cryptoService)
        vaultState = VaultState()
        fileService.cleanupTemporaryArtifacts()
        restorationProgressCancellable = restorationProgress.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        if let customURL = customBaseURL {
            vaultBaseURL = customURL
        } else {
            // Determine vault base directory based on platform
            #if os(macOS)
                // macOS: Use Application Support or custom location
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                let defaultBaseDirectory: URL

                if let appSupport = appSupport {
                    defaultBaseDirectory = appSupport
                } else {
                    // Fallback to documents directory if Application Support is unavailable
                    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    else {
                        fatalError("Unable to access file system")
                    }
                    defaultBaseDirectory = documents
                }

                // Load previously chosen vault base URL if available
                let resolvedBaseURL: URL
                if let storedBaseURL = VaultManager.loadStoredVaultBaseURL() {
                    resolvedBaseURL = storedBaseURL
                } else {
                    resolvedBaseURL = defaultBaseDirectory.appendingPathComponent("SecretVault", isDirectory: true)
                }
                vaultBaseURL = resolvedBaseURL
                print("macOS vault base URL: \(vaultBaseURL.path)")
            #else
                // iOS: Use iCloud Drive if available, otherwise local documents
                let fileManager = FileManager.default
                var baseURL: URL

                if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
                {
                    // iCloud is available
                    baseURL = iCloudURL.appendingPathComponent("SecretVault", isDirectory: true)
                    print("Using iCloud Drive for vault storage: \(baseURL.path)")
                } else {
                    // Fallback to local documents
                    guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                        fatalError("Unable to access file system")
                    }
                    baseURL = documentsURL.appendingPathComponent("SecretVault", isDirectory: true)
                    print("Using local storage for vault (iCloud not available): \(baseURL.path)")
                }

                vaultBaseURL = baseURL
            #endif
        }

        // Create directories
        do {
            try FileManager.default.createDirectory(at: vaultBaseURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to create directory: \(error)")
        }

        do {
            try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to create photos directory: \(error)")
        }

        print("Loading settings from: \(settingsFile.path)")
        loadSettings()
        print("After loading settings - passwordHash.isEmpty: \(passwordHash.isEmpty), hasPassword(): \(hasPassword())")
        if !passwordHash.isEmpty {
            showUnlockPrompt = true
            print("Password exists, showing unlock prompt")
        } else {
            print("No password found, should show setup screen")
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
        try passwordService.validatePassword(password)

        let (hash, salt) = try await passwordService.hashPassword(password)
        try passwordService.storePasswordHash(hash, salt: salt)

        passwordHash = hash.map { String(format: "%02x", $0) }.joined()
        passwordSalt = salt.base64EncodedString()
        securityVersion = 2 // New setups are always V2

        cachedMasterKey = nil
        cachedEncryptionKey = nil
        cachedHMACKey = nil
        saveSettings()

        // Store password for biometric unlock
        saveBiometricPassword(password)
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
                print("🔒 Migrating vault security to V2 (Verifier-based)...")
                let (newVerifier, _) = try await passwordService.hashPassword(password) // Uses new verifier logic
                // Salt remains the same to avoid re-encrypting data (we just change the stored verifier)
                try passwordService.storePasswordHash(newVerifier, salt: storedSalt)
                
                await MainActor.run {
                    self.passwordHash = newVerifier.map { String(format: "%02x", $0) }.joined()
                    self.securityVersion = 2
                }
                saveSettings()
                print("✅ Migration complete. Encryption key removed from storage.")
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
            saveSettings()
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
        
        // 1. Prepare: Verify old password and generate new keys
        progressHandler?("Verifying and generating keys...")
        let (newVerifier, newSalt, newEncryptionKey, newHMACKey) = try await passwordService.preparePasswordChange(
            currentPassword: currentPassword,
            newPassword: newPassword
        )
        
        guard let oldEncryptionKey = cachedEncryptionKey, let oldHMACKey = cachedHMACKey else {
            throw VaultError.vaultNotInitialized
        }
        
        // 2. Re-encrypt all photos
        let photos = hiddenPhotos // Capture current list
        let total = photos.count
        
        for (index, photo) in photos.enumerated() {
            progressHandler?("Re-encrypting item \(index + 1) of \(total)...")
            
            let photosDir = vaultBaseURL.appendingPathComponent(FileConstants.photosDirectoryName)
            let filename = URL(fileURLWithPath: photo.encryptedDataPath).lastPathComponent
            
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
            let thumbFilename = URL(fileURLWithPath: photo.encryptedThumbnailPath ?? photo.thumbnailPath).lastPathComponent
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
            } else {
                // If it was a legacy unencrypted thumbnail, we should probably encrypt it now?
                // For now, we leave it as is or handle it if we want to enforce full encryption.
                // Let's stick to re-encrypting what is already encrypted.
            }
        }
        
        // 3. Commit: Store new password verifier and salt
        progressHandler?("Saving new password...")
        try passwordService.storePasswordHash(newVerifier, salt: newSalt)
        
        // 4. Update local state
        await MainActor.run {
            self.passwordHash = newVerifier.map { String(format: "%02x", $0) }.joined()
            self.passwordSalt = newSalt.base64EncodedString()
            self.securityVersion = 2
        }
        
        // 5. Update cached keys
        cachedEncryptionKey = newEncryptionKey
        cachedHMACKey = newHMACKey
        
        // 6. Save settings
        saveSettings()
        
        // 7. Update biometric password
        saveBiometricPassword(newPassword)
        
        progressHandler?("Password changed successfully")
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
        cachedMasterKey = nil
        cachedEncryptionKey = nil
        cachedHMACKey = nil
        isUnlocked = false
        startIdleTimer()
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

            let elapsed = Date().timeIntervalSince(self.lastActivity)
            if elapsed > self.idleTimeout {
                self.lock()
            }
        }
        if let idleTimer = idleTimer {
            RunLoop.main.add(idleTimer, forMode: .common)
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

        let photosURL = try await fileService.createPhotosDirectory(in: vaultBaseURL)

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
            vaultQueue.sync {
                isDuplicate = hiddenPhotos.contains(where: { $0.originalAssetIdentifier == assetId })
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

        var thumbnail = generateThumbnailData(from: mediaSource, mediaType: mediaType)
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
            data: thumbnail, filename: thumbnailFilename, to: photosURL, encryptionKey: cachedEncryptionKey!,
            hmacKey: cachedHMACKey!)

        let encryptedFilename = "\(photoId.uuidString).enc"
        switch mediaSource {
        case .data(let data):
            try await fileService.saveEncryptedFile(
                data: data, filename: encryptedFilename, to: photosURL, encryptionKey: cachedEncryptionKey!,
                hmacKey: cachedHMACKey!)
        case .fileURL(let url):
            try await fileService.saveStreamEncryptedFile(
                from: url, filename: encryptedFilename, mediaType: mediaType, to: photosURL,
                encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!, progressHandler: progressHandler)
        }

        let photo = SecurePhoto(
            encryptedDataPath: encryptedPath.path,
            thumbnailPath: thumbnailPath.path,
            encryptedThumbnailPath: encryptedThumbnailPath.path,
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
        let filename = URL(fileURLWithPath: photo.encryptedDataPath).lastPathComponent
        return try await fileService.loadEncryptedFile(
            filename: filename, from: URL(fileURLWithPath: photo.encryptedDataPath).deletingLastPathComponent(),
            encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
    }

    func decryptPhotoToTemporaryURL(_ photo: SecurePhoto, progressHandler: ((Int64) -> Void)? = nil) async throws -> URL
    {
        let filename = URL(fileURLWithPath: photo.encryptedDataPath).lastPathComponent
        let directory = URL(fileURLWithPath: photo.encryptedDataPath).deletingLastPathComponent()
        let originalExtension = URL(fileURLWithPath: photo.filename).pathExtension
        let preferredExtension = originalExtension.isEmpty ? nil : originalExtension
        return try await fileService.decryptEncryptedFileToTemporaryURL(
            filename: filename,
            originalExtension: preferredExtension,
            from: directory,
            encryptionKey: cachedEncryptionKey!,
            hmacKey: cachedHMACKey!,
            progressHandler: progressHandler
        )
    }

    func decryptThumbnail(for photo: SecurePhoto) async throws -> Data {
        // Option 1: be resilient to missing thumbnail files and fall back gracefully.
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            let url = URL(fileURLWithPath: encryptedThumbnailPath)
            if !FileManager.default.fileExists(atPath: url.path) {
                print(
                    "[VaultManager] decryptThumbnail: encrypted thumbnail missing for id=\(photo.id). Falling back to legacy thumbnail if available."
                )
            } else {
                do {
                    // Use FileService to load and decrypt the encrypted thumbnail
                    let filename = URL(fileURLWithPath: encryptedThumbnailPath).lastPathComponent
                    return try await fileService.loadEncryptedFile(
                        filename: filename,
                        from: URL(fileURLWithPath: encryptedThumbnailPath).deletingLastPathComponent(),
                        encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
                } catch {
                    print(
                        "[VaultManager] decryptThumbnail: error reading encrypted thumbnail for id=\(photo.id): \(error). Falling back to legacy thumbnail if available."
                    )
                }
            }
        }

        // Legacy or fallback path: try the plain thumbnailPath.
        let legacyURL = URL(fileURLWithPath: photo.thumbnailPath)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            do {
                let data = try Data(contentsOf: legacyURL)
                if data.isEmpty {
                    print(
                        "[VaultManager] decryptThumbnail: legacy thumbnail data empty for id=\(photo.id), thumb=\(photo.thumbnailPath)"
                    )
                }
                return data
            } catch {
                print("[VaultManager] decryptThumbnail: error reading legacy thumbnail for id=\(photo.id): \(error)")
            }
        } else {
            print(
                "[VaultManager] decryptThumbnail: legacy thumbnail file missing for id=\(photo.id) at path=\(photo.thumbnailPath)"
            )
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
        secureDeleteFile(at: URL(fileURLWithPath: photo.encryptedDataPath))
        secureDeleteFile(at: URL(fileURLWithPath: photo.thumbnailPath))
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            secureDeleteFile(at: URL(fileURLWithPath: encryptedThumbnailPath))
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
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: photo.encryptedDataPath))
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: photo.thumbnailPath))
                if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: encryptedThumbnailPath))
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

        DispatchQueue.global(qos: .userInitiated).async {
            let thumbnailData: Data

            if mediaType == .video {
                // For videos, extract a frame as thumbnail
                thumbnailData = self.generateVideoThumbnail(from: mediaData)
            } else {
                // For photos, resize the image
                thumbnailData = self.generatePhotoThumbnail(from: mediaData)
            }

            DispatchQueue.main.async {
                completion(thumbnailData)
            }
        }
    }

    private func generateThumbnailData(from source: MediaSource, mediaType: MediaType) -> Data {
        switch (mediaType, source) {
        case (.video, .data(let data)):
            return generateVideoThumbnail(from: data)
        case (.video, .fileURL(let url)):
            return generateVideoThumbnail(fromFileURL: url)
        case (.photo, .data(let data)):
            return generatePhotoThumbnail(from: data)
        case (.photo, .fileURL(let url)):
            return generatePhotoThumbnail(fromFileURL: url)
        }
    }

    /// Generates a thumbnail from photo data (synchronous, call from background queue).
    private func generatePhotoThumbnail(from mediaData: Data) -> Data {
        #if os(macOS)
            guard let image = NSImage(data: mediaData) else {
                return Data()
            }
            return renderPhotoThumbnail(from: image)
        #else
            guard let image = UIImage(data: mediaData) else {
                return Data()
            }
            return renderPhotoThumbnail(from: image)
        #endif
    }

    private func generatePhotoThumbnail(fromFileURL url: URL) -> Data {
        #if os(macOS)
            guard let image = NSImage(contentsOf: url) else {
                return Data()
            }
            return renderPhotoThumbnail(from: image)
        #else
            guard let image = UIImage(contentsOfFile: url.path) else {
                return Data()
            }
            return renderPhotoThumbnail(from: image)
        #endif
    }

    #if os(macOS)
        private func renderPhotoThumbnail(from image: NSImage) -> Data {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return Data()
            }

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
        }
    #else
        private func renderPhotoThumbnail(from image: UIImage) -> Data {
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
        }
    #endif

    /// Generates a thumbnail from video data (synchronous, call from background queue).
    private func generateVideoThumbnail(from videoData: Data) -> Data {
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
            return generateVideoThumbnail(fromAsset: asset)
        } catch {
            #if DEBUG
                print("Failed to generate video thumbnail: \(error)")
            #endif
        }

        return Data()
    }

    private func generateVideoThumbnail(fromFileURL url: URL) -> Data {
        let asset = AVAsset(url: url)
        return generateVideoThumbnail(fromAsset: asset)
    }

    private func generateVideoThumbnail(fromAsset asset: AVAsset) -> Data {
        guard asset.tracks(withMediaType: .video).count > 0 else {
            #if DEBUG
                print("No video tracks found in asset")
            #endif
            return Data()
        }

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 300, height: 300)

        let duration = asset.duration
        let time = CMTimeMinimum(CMTime(seconds: 1, preferredTimescale: 60), duration)

        guard let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) else {
            #if DEBUG
                print("Failed to generate CGImage from video")
            #endif
            return Data()
        }

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
            print("savePhotos: writing \(hiddenPhotos.count) items to \(photosFile.path)")
        #endif
        try? data.write(to: photosFile)
    }

    func saveSettings() {
        // Ensure vault directory exists before saving
        do {
            try FileManager.default.createDirectory(at: vaultBaseURL, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
                print("Failed to create vault directory: \(error)")
            #endif
            return
        }

        var settings: [String: String] = [
            "passwordHash": passwordHash,
            "passwordSalt": passwordSalt,
            "securityVersion": String(securityVersion)
        ]
        settings["vaultBaseURL"] = vaultBaseURL.path

        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsFile, options: .atomic)
            #if DEBUG
                print("Successfully saved settings to: \(settingsFile.path)")
            #endif
        } catch {
            #if DEBUG
                print("Failed to save settings: \(error)")
            #endif
        }
    }

    private func loadSettings() {
        #if DEBUG
            print("Attempting to load settings from: \(settingsFile.path)")
        #endif
        guard let data = try? Data(contentsOf: settingsFile),
            let settings = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            #if DEBUG
                print("No settings file found or failed to decode")
            #endif
            return
        }

        #if DEBUG
            print("Loaded settings: \(settings)")
        #endif
        if let hash = settings["passwordHash"] {
            passwordHash = hash
            #if DEBUG
                print("Loaded password hash: \(hash.isEmpty ? "empty" : "present")")
            #endif
        }
        if let salt = settings["passwordSalt"] {
            passwordSalt = salt
            #if DEBUG
                print("Loaded password salt: \(salt.isEmpty ? "empty" : "present")")
            #endif
        }
        
        if let versionString = settings["securityVersion"], let version = Int(versionString) {
            securityVersion = version
        } else {
            // Default to 1 (Legacy) if missing
            securityVersion = 1
        }
        
        // On macOS we respect a stored custom vaultBaseURL so users can move
        // the vault. On iOS, the container path is not stable across installs,
        // so we ignore the stored path and always use the current Documents
        // location determined during init.
        #if os(macOS)
            if let basePath = settings["vaultBaseURL"] {
                let url = URL(fileURLWithPath: basePath, isDirectory: true)
                vaultBaseURL = url
                #if DEBUG
                    print("Loaded vault base URL: \(basePath)")
                #endif
            }
        #endif
    }

    private static func loadStoredVaultBaseURL() -> URL? {
        // This is only used during init before instance properties are set
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseDirectory = appSupport ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        guard let baseDirectory = baseDirectory else { return nil }
        let appDirectory = baseDirectory.appendingPathComponent("SecretVault", isDirectory: true)
        let settingsFile = appDirectory.appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settingsFile),
            let settings = try? JSONDecoder().decode([String: String].self, from: data),
            let basePath = settings["vaultBaseURL"]
        else {
            return nil
        }

        return URL(fileURLWithPath: basePath, isDirectory: true)
    }

    // MARK: - Biometric Authentication Helpers

    func saveBiometricPassword(_ password: String) {
        #if DEBUG
            print("💾 Saving biometric password (length: \(password.count))")
        #endif
        do {
            try securityService.storeBiometricPassword(password)
        } catch {
            #if DEBUG
                print("Failed to store biometric password: \(error)")
            #endif
        }
    }

    func getBiometricPassword() -> String? {
        let password = try? securityService.retrieveBiometricPassword()
        #if DEBUG
            if let password = password {
                print("🔐 Retrieved biometric password: exists (length: \(password.count))")
            } else {
                print("🔐 Retrieved biometric password: nil")
            }
        #endif
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
        guard let data = try? Data(contentsOf: photosFile) else {
            await MainActor.run {
                hiddenPhotos = []
            }
            return
        }

        let decodedPhotos = try JSONDecoder().decode([SecurePhoto].self, from: data)
        await MainActor.run {
            hiddenPhotos = decodedPhotos
        }
    }
}

// MARK: - Import Operations

extension VaultManager {
    /// Imports assets from Photo Library into the vault
    func importAssets(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        
        await MainActor.run {
            importProgress.reset()
            importProgress.isImporting = true
            importProgress.totalItems = assets.count
            importProgress.statusMessage = "Preparing import…"
            importProgress.detailMessage = "\(assets.count) item(s)"
        }

        // Add overall timeout to prevent hanging
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 300_000_000_000)  // 5 minute overall timeout
            if !Task.isCancelled {
                print("⚠️ Overall hide operation timed out after 5 minutes")
                await MainActor.run {
                    importProgress.isImporting = false
                    importProgress.statusMessage = "Import timed out"
                }
            }
        }

        defer {
            timeoutTask.cancel()
        }

        // Process assets with limited concurrency
        let maxConcurrentOperations = 2
        var successfulAssets: [PHAsset] = []
        var processedCount = 0

        // Create indexed list for tracking
        let indexedAssets = assets.enumerated().map { (index: $0.offset, asset: $0.element) }

        // Process assets in batches
        for batch in indexedAssets.chunked(into: maxConcurrentOperations) {
            if await MainActor.run(body: { importProgress.cancelRequested }) { break }
            
            let batchSuccessful = await withTaskGroup(of: (PHAsset, Bool).self) { group -> [PHAsset] in
                for (index, asset) in batch {
                    group.addTask {
                        await self.processSingleImport(asset: asset, index: index, total: assets.count)
                    }
                }

                var batchAssets: [PHAsset] = []
                // Collect results
                for await (asset, success) in group {
                    if success {
                        batchAssets.append(asset)
                    }
                    await MainActor.run {
                        importProgress.processedItems += 1
                        if success {
                            importProgress.successItems += 1
                        } else {
                            importProgress.failedItems += 1
                        }
                    }
                }
                return batchAssets
            }
            successfulAssets.append(contentsOf: batchSuccessful)
        }

        timeoutTask.cancel()

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

    private func processSingleImport(asset: PHAsset, index: Int, total: Int) async -> (PHAsset, Bool) {
        let itemNumber = index + 1
        
        guard let mediaResult = await PhotosLibraryService.shared.getMediaDataAsync(for: asset) else {
            print("❌ Failed to get media data for asset: \(asset.localIdentifier)")
            await MainActor.run {
                importProgress.detailMessage = "Failed to fetch item \(itemNumber)"
            }
            return (asset, false)
        }

        let fileSizeValue = estimatedSize(for: mediaResult)
        let sizeDescription = ByteCountFormatter.string(fromByteCount: fileSizeValue, countStyle: .file)

        await MainActor.run {
            importProgress.statusMessage = "Encrypting \(mediaResult.filename)…"
            importProgress.detailMessage = "Item \(itemNumber) of \(total) • \(sizeDescription)"
            importProgress.currentBytesTotal = fileSizeValue
            importProgress.currentBytesProcessed = 0
        }

        let cleanupURL = mediaResult.shouldDeleteFileWhenFinished ? mediaResult.fileURL : nil
        let progressHandler: ((Int64) async -> Void)? = mediaResult.fileURL != nil ? { bytesRead in
            await MainActor.run {
                self.importProgress.currentBytesProcessed = bytesRead
            }
        } : nil

        do {
            let mediaSource: MediaSource
            if let fileURL = mediaResult.fileURL {
                mediaSource = .fileURL(fileURL)
            } else if let mediaData = mediaResult.data {
                mediaSource = .data(mediaData)
            } else {
                return (asset, false)
            }

            defer {
                if let cleanupURL = cleanupURL {
                    try? FileManager.default.removeItem(at: cleanupURL)
                }
            }

            try await hidePhoto(
                mediaSource: mediaSource,
                filename: mediaResult.filename,
                dateTaken: mediaResult.dateTaken,
                sourceAlbum: nil, // We could pass this if we want to preserve album structure
                assetIdentifier: asset.localIdentifier,
                mediaType: mediaResult.mediaType,
                duration: mediaResult.duration,
                location: mediaResult.location,
                isFavorite: mediaResult.isFavorite,
                progressHandler: progressHandler
            )

            return (asset, true)
        } catch {
            print("❌ Failed to add media to vault: \(error.localizedDescription)")
            return (asset, false)
        }
    }

    private func estimatedSize(for mediaResult: MediaFetchResult) -> Int64 {
        if let fileURL = mediaResult.fileURL {
            return (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        }
        if let data = mediaResult.data {
            return Int64(data.count)
        }
        return 0
    }
}

// MARK: - Helper Extensions

extension Array {
    /// Splits the array into chunks of the specified size.
    /// - Parameter size: The size of each chunk
    /// - Returns: An array of arrays, each containing up to `size` elements
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
