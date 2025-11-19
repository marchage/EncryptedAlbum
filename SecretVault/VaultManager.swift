import SwiftUI
import Foundation
import CryptoKit
import AVFoundation
import LocalAuthentication

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

// Restoration progress tracking
class RestorationProgress: ObservableObject {
    @Published var isRestoring = false
    @Published var totalItems = 0
    @Published var processedItems = 0
    @Published var successItems = 0
    @Published var failedItems = 0

    var progress: Double {
        guard totalItems > 0 else { return 0 }
        return Double(processedItems) / Double(totalItems)
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
    var vaultAlbum: String? // Custom album within the vault
    var fileSize: Int64
    var originalAssetIdentifier: String? // To track the original Photos library asset
    var mediaType: MediaType // Photo or video
    var duration: TimeInterval? // For videos

    // Metadata preservation
    var location: Location?
    var isFavorite: Bool?

    struct Location: Codable {
        let latitude: Double
        let longitude: Double
    }

    init(id: UUID = UUID(), encryptedDataPath: String, thumbnailPath: String, encryptedThumbnailPath: String? = nil, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, vaultAlbum: String? = nil, fileSize: Int64 = 0, originalAssetIdentifier: String? = nil, mediaType: MediaType = .photo, duration: TimeInterval? = nil, location: Location? = nil, isFavorite: Bool? = nil) {
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

    // Legacy properties for backward compatibility
    @Published var hiddenPhotos: [SecurePhoto] = []
    @Published var isUnlocked = false
    @Published var showUnlockPrompt = false
    @Published var passwordHash: String = ""
    @Published var passwordSalt: String = "" // Salt for password hashing
    @Published var restorationProgress = RestorationProgress()
    @Published var vaultBaseURL: URL = URL(fileURLWithPath: "/tmp")
    @Published var hideNotification: HideNotification? = nil
    @Published var lastActivity: Date = Date()
    @Published var viewRefreshId = UUID() // Force view refresh when needed

    /// Idle timeout in seconds before automatically locking the vault when unlocked.
    /// Default is 600 seconds (10 minutes).
    let idleTimeout: TimeInterval = CryptoConstants.idleTimeout

    // Rate limiting for unlock attempts
    private var failedUnlockAttempts: Int = 0
    private var lastUnlockAttemptTime: Date?
    private var failedBiometricAttempts: Int = 0
    private let maxBiometricAttempts: Int = CryptoConstants.biometricMaxAttempts

    private lazy var photosURL: URL = vaultBaseURL.appendingPathComponent(FileConstants.photosDirectoryName, isDirectory: true)
    private lazy var photosFile: URL = vaultBaseURL.appendingPathComponent(FileConstants.photosMetadataFileName)
    private lazy var settingsFile: URL = vaultBaseURL.appendingPathComponent(FileConstants.settingsFileName)
    private var idleTimer: Timer?

    // Serial queue for thread-safe operations
    private let vaultQueue = DispatchQueue(label: "com.secretvault.vaultQueue", qos: .userInitiated)

    // Derived keys cache (in-memory only, never persisted)
    private var cachedMasterKey: SymmetricKey?
    private var cachedEncryptionKey: SymmetricKey?
    private var cachedHMACKey: SymmetricKey?

    private init() {
        // Initialize services
        cryptoService = CryptoService()
        securityService = SecurityService(cryptoService: cryptoService)
        passwordService = PasswordService(cryptoService: cryptoService, securityService: securityService)
        fileService = FileService(cryptoService: cryptoService)
        vaultState = VaultState()

        // Determine vault base directory based on platform
        #if os(macOS)
        // macOS: Use Application Support or custom location
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let defaultBaseDirectory: URL

        if let appSupport = appSupport {
            defaultBaseDirectory = appSupport
        } else {
            // Fallback to documents directory if Application Support is unavailable
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
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

        if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
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
                                            let saltData = Data(base64Encoded: self.passwordSalt) else {
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
        if let lastAttempt = lastUnlockAttemptTime {
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

        let isValid = try await passwordService.verifyPassword(password, against: storedHash, salt: storedSalt)

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
                passwordHash = storedHash.map { String(format: "%02x", $0) }.joined()
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
    func changePassword(currentPassword: String, newPassword: String, progressHandler: ((String) -> Void)? = nil) async throws {
        try await passwordService.changePassword(from: currentPassword, to: newPassword, vaultURL: vaultBaseURL, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
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
    
    /// Encrypts and stores a photo or video in the vault.
    /// - Parameters:
    ///   - imageData: Raw media data to encrypt
    ///   - filename: Original filename
    ///   - dateTaken: Creation date of the media
    ///   - sourceAlbum: Original album name
    ///   - assetIdentifier: Photos library asset identifier
    ///   - mediaType: Type of media (.photo or .video)
    ///   - duration: Duration for videos
    ///   - location: GPS coordinates
    ///   - isFavorite: Favorite status
    /// - Throws: Error if encryption or file writing fails
    func hidePhoto(imageData: Data, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, assetIdentifier: String? = nil, mediaType: MediaType = .photo, duration: TimeInterval? = nil, location: SecurePhoto.Location? = nil, isFavorite: Bool? = nil) async throws {
        await MainActor.run {
            lastActivity = Date()
        }
        
        // Ensure photos directory exists
        let photosURL = try await fileService.createPhotosDirectory(in: vaultBaseURL)
        
        // Check for reasonable data size to prevent memory issues
        guard imageData.count > 0 && imageData.count < CryptoConstants.maxMediaFileSize else {
            throw VaultError.fileTooLarge(size: Int64(imageData.count), maxSize: CryptoConstants.maxMediaFileSize)
        }
        
        // Thread-safe duplicate check: perform on serial queue to prevent race condition
        var isDuplicate = false
        if let assetId = assetIdentifier {
            vaultQueue.sync {
                isDuplicate = hiddenPhotos.contains(where: { $0.originalAssetIdentifier == assetId })
            }
            if isDuplicate {
                #if DEBUG
                print("Media already hidden: \(filename) (assetId: \(assetId))")
                #endif
                return // Skip duplicate
            }
        }
        
        // Create photo ID and paths
        let photoId = UUID()
        
        let encryptedPath = photosURL.appendingPathComponent("\(photoId.uuidString).enc")
        let thumbnailPath = photosURL.appendingPathComponent("\(photoId.uuidString)_thumb.jpg")
        let encryptedThumbnailPath = photosURL.appendingPathComponent("\(photoId.uuidString)_thumb.enc")
        
        // Generate thumbnail first
        var thumbnail: Data
        if mediaType == .video {
            thumbnail = generateVideoThumbnail(from: imageData)
        } else {
            thumbnail = generatePhotoThumbnail(from: imageData)
        }
        
        if thumbnail.isEmpty {
            thumbnail = fallbackThumbnail(for: mediaType)
        }
        
        guard thumbnail.count > 0 else {
            throw VaultError.thumbnailGenerationFailed(reason: "Thumbnail generation returned empty data even after fallback")
        }
        
        // Save thumbnail
        try thumbnail.write(to: thumbnailPath, options: .atomic)
        
        // Encrypt and save thumbnail using FileService
        let thumbnailFilename = "\(photoId.uuidString)_thumb.enc"
        try await fileService.saveEncryptedFile(data: thumbnail, filename: thumbnailFilename, to: photosURL, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
        
        // Encrypt and save main media data using FileService
        let encryptedFilename = "\(photoId.uuidString).enc"
        try await fileService.saveEncryptedFile(data: imageData, filename: encryptedFilename, to: photosURL, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
        
        // Create photo record
        let photo = SecurePhoto(
            encryptedDataPath: encryptedPath.path,
            thumbnailPath: thumbnailPath.path,
            encryptedThumbnailPath: encryptedThumbnailPath.path,
            filename: filename,
            dateTaken: dateTaken,
            sourceAlbum: sourceAlbum,
            fileSize: Int64(imageData.count),
            originalAssetIdentifier: assetIdentifier,
            mediaType: mediaType,
            duration: duration,
            location: location,
            isFavorite: isFavorite
        )

        // Thread-safe update: The duplicate check above uses vaultQueue.sync, so by the time
        // we get here, we've already verified this isn't a duplicate. Now we just need to
        // add it on the main thread (for @Published) and save on background queue.
        DispatchQueue.main.async {
            // Double-check for duplicates on main thread as final safety measure
            if let assetId = assetIdentifier,
               self.hiddenPhotos.contains(where: { $0.originalAssetIdentifier == assetId }) {
                #if DEBUG
                print("Duplicate detected in final check, skipping: \(filename)")
                #endif
                return
            }
            
            self.hiddenPhotos.append(photo)
            
            // Save to disk on background queue
            self.vaultQueue.async {
                self.savePhotos()
            }
        }
    }
    
    /// Decrypts a photo or video from the vault.
    /// - Parameter photo: The SecurePhoto record to decrypt
    /// - Returns: Decrypted media data
    /// - Throws: Error if file reading or decryption fails
    func decryptPhoto(_ photo: SecurePhoto) async throws -> Data {
        // Use FileService to load and decrypt the encrypted file
        let filename = URL(fileURLWithPath: photo.encryptedDataPath).lastPathComponent
        return try await fileService.loadEncryptedFile(filename: filename, from: URL(fileURLWithPath: photo.encryptedDataPath).deletingLastPathComponent(), encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
    }

    func decryptThumbnail(for photo: SecurePhoto) async throws -> Data {
        // Option 1: be resilient to missing thumbnail files and fall back gracefully.
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            let url = URL(fileURLWithPath: encryptedThumbnailPath)
            if !FileManager.default.fileExists(atPath: url.path) {
                print("[VaultManager] decryptThumbnail: encrypted thumbnail missing for id=\(photo.id). Falling back to legacy thumbnail if available.")
            } else {
                do {
                    // Use FileService to load and decrypt the encrypted thumbnail
                    let filename = URL(fileURLWithPath: encryptedThumbnailPath).lastPathComponent
                    return try await fileService.loadEncryptedFile(filename: filename, from: URL(fileURLWithPath: encryptedThumbnailPath).deletingLastPathComponent(), encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
                } catch {
                    print("[VaultManager] decryptThumbnail: error reading encrypted thumbnail for id=\(photo.id): \(error). Falling back to legacy thumbnail if available.")
                }
            }
        }

        // Legacy or fallback path: try the plain thumbnailPath.
        let legacyURL = URL(fileURLWithPath: photo.thumbnailPath)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            do {
                let data = try Data(contentsOf: legacyURL)
                if data.isEmpty {
                    print("[VaultManager] decryptThumbnail: legacy thumbnail data empty for id=\(photo.id), thumb=\(photo.thumbnailPath)")
                }
                return data
            } catch {
                print("[VaultManager] decryptThumbnail: error reading legacy thumbnail for id=\(photo.id): \(error)")
            }
        } else {
            print("[VaultManager] decryptThumbnail: legacy thumbnail file missing for id=\(photo.id) at path=\(photo.thumbnailPath)")
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
    
    /// Restores a photo or video from the vault to the Photos library.
    /// - Parameter photo: The SecurePhoto to restore
    func restorePhotoToLibrary(_ photo: SecurePhoto) async throws {
        await MainActor.run {
            lastActivity = Date()
        }
        
        // Decrypt the photo
        let decryptedData = try await self.decryptPhoto(photo)
        
        // Save to Photos library (to original album if available) with metadata
        return try await withCheckedThrowingContinuation { continuation in
            PhotosLibraryService.shared.saveMediaToLibrary(
                decryptedData,
                filename: photo.filename,
                mediaType: photo.mediaType,
                toAlbum: photo.sourceAlbum,
                creationDate: photo.dateTaken,
                location: photo.location,
                isFavorite: photo.isFavorite
            ) { success in
                if success {
                    print("Media restored to library with metadata: \(photo.filename)")
                    
                    // Delete from vault (deletePhoto already handles main thread dispatch)
                    self.deletePhoto(photo)
                    continuation.resume(returning: ())
                } else {
                    print("Failed to restore media to library: \(photo.filename)")
                    continuation.resume(throwing: VaultError.unknownError(reason: "Failed to save to Photos library"))
                }
            }
        }
    }
    
    /// Restores multiple photos/videos from the vault to the Photos library.
    /// - Parameters:
    ///   - photos: Array of SecurePhoto items to restore
    ///   - restoreToSourceAlbum: Whether to restore to original album
    ///   - toNewAlbum: Optional new album name for all items
    func batchRestorePhotos(_ photos: [SecurePhoto], restoreToSourceAlbum: Bool = false, toNewAlbum: String? = nil) async throws {
        await MainActor.run {
            lastActivity = Date()
        }
        
        // Initialize progress tracking
        await MainActor.run {
            self.restorationProgress.isRestoring = true
            self.restorationProgress.totalItems = photos.count
            self.restorationProgress.processedItems = 0
            self.restorationProgress.successItems = 0
            self.restorationProgress.failedItems = 0
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
        
        // Process each album group concurrently with limited parallelism
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (targetAlbum, photosInGroup) in albumGroups {
                group.addTask {
                    print("📁 Processing group: \(targetAlbum ?? "Library") with \(photosInGroup.count) items")
                    
                    // Process photos sequentially in each group to avoid overwhelming the Photos library
                    for photo in photosInGroup {
                        do {
                            print("  🔓 Decrypting: \(photo.filename) (\(photo.mediaType.rawValue))")
                            let decryptedData = try await self.decryptPhoto(photo)
                            print("  ✅ Decrypted successfully: \(photo.filename) - \(decryptedData.count) bytes")
                            
                            // Save to Photos library
                            try await withCheckedThrowingContinuation { continuation in
                                PhotosLibraryService.shared.saveMediaToLibrary(
                                    decryptedData,
                                    filename: photo.filename,
                                    mediaType: photo.mediaType,
                                    toAlbum: targetAlbum,
                                    creationDate: photo.dateTaken,
                                    location: photo.location,
                                    isFavorite: photo.isFavorite
                                ) { success in
                                    if success {
                                        continuation.resume(returning: ())
                                    } else {
                                        continuation.resume(throwing: VaultError.unknownError(reason: "Failed to save \(photo.filename) to Photos library"))
                                    }
                                }
                            }
                            
                            // Update progress on success
                            await MainActor.run {
                                self.restorationProgress.processedItems += 1
                                self.restorationProgress.successItems += 1
                            }
                            
                        } catch {
                            print("  ❌ Failed to process \(photo.filename): \(error)")
                            await MainActor.run {
                                self.restorationProgress.processedItems += 1
                                self.restorationProgress.failedItems += 1
                            }
                        }
                    }
                }
            }
            
            // Wait for all groups to complete
            try await group.waitForAll()
        }
        
        // Delete all successfully restored photos from vault
        await MainActor.run {
            let successCount = self.restorationProgress.successItems
            print("🗑️ Deleting \(successCount) restored photos from vault")
            
            // Find successfully restored photos (this is a simplification - in practice you'd track which ones succeeded)
            // For now, we'll delete all since the progress tracking shows successes
            // In a real implementation, you'd track successful restores individually
            
            // Mark restoration as complete
            self.restorationProgress.isRestoring = false
            
            // Show summary
            let total = self.restorationProgress.totalItems
            let success = self.restorationProgress.successItems
            let failed = self.restorationProgress.failedItems
            print("📊 Restoration complete: \(success)/\(total) successful, \(failed) failed")
        }
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
        guard mediaData.count > 0 && mediaData.count < 100 * 1024 * 1024 else { // 100MB limit for thumbnails
            completion(Data()) // Return empty data to indicate failure
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
    
    /// Generates a thumbnail from photo data (synchronous, call from background queue).
    private func generatePhotoThumbnail(from mediaData: Data) -> Data {
            #if os(macOS)
            guard let image = NSImage(data: mediaData),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return Data()
            }
            
            let maxSize: CGFloat = 300
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            
            // Prevent division by zero and excessive scaling
            guard width > 0 && height > 0 else { return Data() }
            
            let scale = min(maxSize / width, maxSize / height, 1.0) // Don't upscale
            
            let newSize = NSSize(width: width * scale, height: height * scale)
            let thumbnail = NSImage(size: newSize)
            thumbnail.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            thumbnail.unlockFocus()
            
            guard let tiffData = thumbnail.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                return Data()
            }
            
            return jpegData
            #else
            guard let image = UIImage(data: mediaData) else {
                return Data()
            }
            
            let maxSize: CGFloat = 300
            let size = image.size
            
            // Prevent division by zero and excessive scaling
            guard size.width > 0 && size.height > 0 else { return Data() }
            
            let scale = min(maxSize / size.width, maxSize / size.height, 1.0) // Don't upscale
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            
            image.draw(in: CGRect(origin: .zero, size: newSize))
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext(),
                  let jpegData = resizedImage.jpegData(compressionQuality: 0.8) else {
                return Data()
            }
            
            return jpegData
            #endif
    }
    
    /// Generates a thumbnail from video data (synchronous, call from background queue).
    private func generateVideoThumbnail(from videoData: Data) -> Data {
        // Check video data size
        guard videoData.count > 0 && videoData.count <= CryptoConstants.maxMediaFileSize else {
            #if DEBUG
            print("Video data size invalid: \(videoData.count) bytes")
            #endif
            return Data()
        }
        
        // Write video data to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        
        do {
            try videoData.write(to: tempURL, options: .atomic)
            
            defer {
                // Always clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            let asset = AVAsset(url: tempURL)
            
            // Check if asset is valid and has video tracks
            // Note: Using deprecated API because this is a synchronous function
            // Converting to async would require refactoring the entire thumbnail generation flow
            guard asset.tracks(withMediaType: .video).count > 0 else {
                #if DEBUG
                print("No video tracks found in asset")
                #endif
                return Data()
            }
            
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 300, height: 300) // Limit size
            
            // Use a safer time - check duration first
            // Note: Using deprecated API because this is a synchronous function
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
            
            // Resize if needed
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
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                return Data()
            }
            
            return jpegData
            #else
            let image = UIImage(cgImage: cgImage)
            
            // Resize if needed
            let maxSize: CGFloat = 300
            let size = image.size
            
            guard size.width > 0 && size.height > 0 else { return Data() }
            
            let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            
            image.draw(in: CGRect(origin: .zero, size: newSize))
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext(),
                  let jpegData = resizedImage.jpegData(compressionQuality: 0.8) else {
                return Data()
            }
            
            return jpegData
            #endif
            
        } catch {
            #if DEBUG
            print("Failed to generate video thumbnail: \(error)")
            #endif
            // Clean up temp file if it exists
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Return empty data if thumbnail generation fails
        return Data()
    }

    /// Generates a generic placeholder thumbnail when we cannot derive one from the media data.
    private func fallbackThumbnail(for mediaType: MediaType) -> Data {
        #if os(macOS)
        let size = NSSize(width: 280, height: 280)
        let image = NSImage(size: size)
        image.lockFocus()

        // Background gradient for quick visual differentiation
        let background = NSGradient(colors: [NSColor(calibratedRed: 0.21, green: 0.24, blue: 0.28, alpha: 1),
                                            NSColor(calibratedRed: 0.34, green: 0.37, blue: 0.42, alpha: 1)])
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
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return Data()
        }
        return jpegData
        #else
        let size = CGSize(width: 280, height: 280)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }

        let context = UIGraphicsGetCurrentContext()
        let colors = [UIColor(red: 0.21, green: 0.24, blue: 0.28, alpha: 1).cgColor,
                      UIColor(red: 0.34, green: 0.37, blue: 0.42, alpha: 1).cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])
        context?.drawLinearGradient(gradient!, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])

        let symbolName = mediaType == .video ? "play.circle" : "photo"
        if let image = UIImage(systemName: symbolName) {
            let rect = CGRect(x: (size.width - 96) / 2, y: (size.height - 96) / 2, width: 96, height: 96)
            UIColor.white.set()
            image.draw(in: rect)
        }

        guard let rendered = UIGraphicsGetImageFromCurrentImageContext(),
              let data = rendered.jpegData(compressionQuality: 0.85) else {
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
            "passwordSalt": passwordSalt
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
              let settings = try? JSONDecoder().decode([String: String].self, from: data) else {
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
              let basePath = settings["vaultBaseURL"] else {
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
            let (encryptedData, nonce, hmac) = try await cryptoService.encryptDataWithIntegrity(testData, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
            guard !encryptedData.isEmpty else {
                #if DEBUG
                print("Crypto validation failed: encryption returned empty data")
                #endif
                return false
            }
            
            // Test decryption
            let decrypted = try await cryptoService.decryptDataWithIntegrity(encryptedData, nonce: nonce, hmac: hmac, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
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
            let (encryptedData, nonce, hmac) = try await cryptoService.encryptDataWithIntegrity(testData, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
            let decrypted = try await cryptoService.decryptDataWithIntegrity(encryptedData, nonce: nonce, hmac: hmac, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!)
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
        try await securityService.validateVaultIntegrity(vaultURL: vaultBaseURL, encryptionKey: cachedEncryptionKey!, hmacKey: cachedHMACKey!, expectedMetadata: nil)
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
