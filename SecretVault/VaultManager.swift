import SwiftUI
import Foundation
import CryptoKit
import AVFoundation
import LocalAuthentication

// MARK: - Constants

private enum KeychainKeys {
    static let biometricPassword = "SecretVault.BiometricPassword"
    static let legacyPasswordService = "com.secretvault.password"
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
    let idleTimeout: TimeInterval = 600
    
    // Rate limiting for unlock attempts
    private var failedUnlockAttempts: Int = 0
    private var lastUnlockAttemptTime: Date?
    private var failedBiometricAttempts: Int = 0
    private let maxBiometricAttempts: Int = 3
    
    private lazy var photosURL: URL = vaultBaseURL.appendingPathComponent("photos", isDirectory: true)
    private lazy var photosFile: URL = vaultBaseURL.appendingPathComponent("hidden_photos.json")
    private lazy var settingsFile: URL = vaultBaseURL.appendingPathComponent("settings.json")
    private var idleTimer: Timer?
    private let vaultQueue = DispatchQueue(label: "com.secretvault.vaultQueue", qos: .userInitiated)
    
    private init() {
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
    /// Uses biometrics/device auth when available, otherwise falls back to password verification.
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
                let enteredHash = enteredPassword.data(using: .utf8)?.base64EncodedString() ?? ""
                completion(enteredHash == self.passwordHash)
                #else
                // On iOS, we'll need to use a different approach - perhaps a modal view
                // For now, just fail the authentication
                completion(false)
                #endif
            }
        }
    }
    
    /// Sets up the vault password with proper validation and secure hashing.
    /// - Parameter password: The password to set (must be 8-128 characters)
    /// - Returns: `true` on success, `false` if validation fails
    @discardableResult
    func setupPassword(_ password: String) -> Bool {
        // Defensive validation: enforce password requirements
        guard !password.isEmpty else {
            print("VaultManager: refused to set empty password")
            return false
        }
        
        guard password.count >= 8 else {
            print("VaultManager: password too short (minimum 8 characters)")
            return false
        }
        
        guard password.count <= 128 else {
            print("VaultManager: password too long (maximum 128 characters)")
            return false
        }

        // Generate a new random salt for this password
        let saltData = generateSalt()
        passwordSalt = saltData.base64EncodedString()
        
        // Hash password with salt using SHA-256
        guard let passwordData = password.data(using: .utf8) else {
            print("VaultManager: failed to encode password")
            return false
        }
        
        var combinedData = Data()
        combinedData.append(passwordData)
        combinedData.append(saltData)
        
        let hash = SHA256.hash(data: combinedData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        passwordHash = hashString
        saveSettings()
        // Store password for biometric unlock
        saveBiometricPassword(password)
        return true
    }
    
    /// Generates a cryptographically secure random salt.
    /// - Returns: 32 bytes of random data
    private func generateSalt() -> Data {
        var saltData = Data(count: 32)
        _ = saltData.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        return saltData
    }
    
    /// Generates HMAC for data integrity verification.
    /// - Parameters:
    ///   - data: Data to generate HMAC for
    ///   - key: Key used for HMAC
    /// - Returns: HMAC as hex string
    private func generateHMAC(for data: Data, key: String) -> String {
        guard let keyData = key.data(using: .utf8) else { return "" }
        let symmetricKey = SymmetricKey(data: SHA256.hash(data: keyData))
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(hmac).map { String(format: "%02x", $0) }.joined()
    }
    
    /// Attempts to unlock the vault with the provided password.
    /// - Parameter password: The password to verify
    /// - Returns: `true` if unlock successful, `false` otherwise
    func unlock(password: String) -> Bool {
        // Rate limiting: exponential backoff on failed attempts
        if let lastAttempt = lastUnlockAttemptTime {
            let requiredDelay = calculateUnlockDelay()
            let elapsed = Date().timeIntervalSince(lastAttempt)
            
            if elapsed < requiredDelay {
                let remaining = Int(requiredDelay - elapsed)
                #if DEBUG
                print("Rate limited: wait \(remaining) more seconds")
                #endif
                return false
            }
        }
        
        lastUnlockAttemptTime = Date()
        
        guard let passwordData = password.data(using: .utf8) else {
            failedUnlockAttempts += 1
            return false
        }
        
        // Retrieve the stored salt
        guard let saltData = Data(base64Encoded: passwordSalt) else {
            #if DEBUG
            print("VaultManager: failed to decode salt")
            #endif
            failedUnlockAttempts += 1
            return false
        }
        
        // Hash the entered password with the stored salt
        var combinedData = Data()
        combinedData.append(passwordData)
        combinedData.append(saltData)
        
        let hash = SHA256.hash(data: combinedData)
        let testHash = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        if testHash == passwordHash {
            // Success - reset counters
            failedUnlockAttempts = 0
            failedBiometricAttempts = 0
            
            isUnlocked = true
            loadPhotos()
            // Update stored password for biometric unlock
            saveBiometricPassword(password)
            touchActivity()
            startIdleTimer()
            return true
        }
        
        failedUnlockAttempts += 1
        return false
    }
    
    /// Calculates delay before next unlock attempt based on failed attempts.
    /// - Returns: Required delay in seconds (exponential backoff)
    private func calculateUnlockDelay() -> TimeInterval {
        switch failedUnlockAttempts {
        case 0...2: return 0
        case 3: return 5
        case 4: return 10
        case 5: return 30
        case 6: return 60
        default: return 300 // 5 minutes for 7+ failed attempts
        }
    }
    
    /// Checks if biometric authentication should be disabled due to too many failures.
    /// - Returns: `true` if biometrics should be disabled
    func shouldDisableBiometrics() -> Bool {
        return failedBiometricAttempts >= maxBiometricAttempts
    }
    
    /// Records a failed biometric authentication attempt.
    func recordFailedBiometricAttempt() {
        failedBiometricAttempts += 1
    }
    
    func lock() {
        isUnlocked = false
        hiddenPhotos = []
        idleTimer?.invalidate()
        idleTimer = nil
    }
    
    /// Changes the vault password and re-encrypts all data.
    /// - Parameters:
    ///   - currentPassword: Current password for verification
    ///   - newPassword: New password to set
    ///   - progressHandler: Optional callback with progress updates
    /// - Returns: `true` if successful, `false` otherwise
    func changePassword(currentPassword: String, newPassword: String, progressHandler: ((String) -> Void)? = nil) -> Bool {
        // Verify current password
        guard unlock(password: currentPassword) else {
            #if DEBUG
            print("Failed to verify current password")
            #endif
            return false
        }
        
        // Validate new password
        guard !newPassword.isEmpty, newPassword.count >= 8, newPassword.count <= 128 else {
            #if DEBUG
            print("New password validation failed")
            #endif
            return false
        }
        
        progressHandler?("Re-encrypting vault...")
        
        // Store old password hash for decryption
        let oldPasswordHash = passwordHash
        
        // Generate new salt and hash
        let saltData = generateSalt()
        passwordSalt = saltData.base64EncodedString()
        
        guard let passwordData = newPassword.data(using: .utf8) else {
            return false
        }
        
        var combinedData = Data()
        combinedData.append(passwordData)
        combinedData.append(saltData)
        
        let hash = SHA256.hash(data: combinedData)
        passwordHash = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Re-encrypt all photos with new password
        let totalPhotos = hiddenPhotos.count
        var processedCount = 0
        
        for photo in hiddenPhotos {
            autoreleasepool {
                do {
                    // Decrypt with old password
                    let encryptedPath = URL(fileURLWithPath: photo.encryptedDataPath)
                    let encryptedData = try Data(contentsOf: encryptedPath)
                    let decrypted = decryptImage(encryptedData, password: oldPasswordHash)
                    
                    guard !decrypted.isEmpty else {
                        #if DEBUG
                        print("Failed to decrypt photo: \(photo.filename)")
                        #endif
                        return
                    }
                    
                    // Re-encrypt with new password
                    let reencrypted = encryptImage(decrypted, password: passwordHash)
                    try reencrypted.write(to: encryptedPath, options: .atomic)
                    
                    // Re-encrypt thumbnail if it exists
                    if let encThumbPath = photo.encryptedThumbnailPath {
                        let thumbURL = URL(fileURLWithPath: encThumbPath)
                        if FileManager.default.fileExists(atPath: thumbURL.path) {
                            let encThumbData = try Data(contentsOf: thumbURL)
                            let decThumb = decryptImage(encThumbData, password: oldPasswordHash)
                            let reencThumb = encryptImage(decThumb, password: passwordHash)
                            try reencThumb.write(to: thumbURL, options: .atomic)
                        }
                    }
                    
                    processedCount += 1
                    progressHandler?("Re-encrypted \(processedCount)/\(totalPhotos) items")
                    
                } catch {
                    #if DEBUG
                    print("Error re-encrypting photo: \(error)")
                    #endif
                }
            }
        }
        
        // Save new settings
        saveSettings()
        saveBiometricPassword(newPassword)
        
        progressHandler?("Password changed successfully")
        return true
    }
    
    func hasPassword() -> Bool {
        return !passwordHash.isEmpty
    }

    /// Marks user activity and resets the idle timer baseline.
    func touchActivity() {
        lastActivity = Date()
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
    func hidePhoto(imageData: Data, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, assetIdentifier: String? = nil, mediaType: MediaType = .photo, duration: TimeInterval? = nil, location: SecurePhoto.Location? = nil, isFavorite: Bool? = nil) throws {
        touchActivity()
        
        // Ensure photos directory exists
        if !FileManager.default.fileExists(atPath: photosURL.path) {
            do {
                try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
            } catch {
                throw NSError(domain: "VaultManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create photos directory: \(error.localizedDescription)"])
            }
        }
        
        // Check for reasonable data size to prevent memory issues
        guard imageData.count > 0 && imageData.count < 500 * 1024 * 1024 else { // 500MB limit
            throw NSError(domain: "VaultManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Media file too large or empty"])
        }
        
        // Check for duplicates by asset identifier
        if let assetId = assetIdentifier {
            if hiddenPhotos.contains(where: { $0.originalAssetIdentifier == assetId }) {
                print("Media already hidden: \(filename)")
                return // Skip duplicate
            }
        }
        
        // Create photo ID and paths
        let photoId = UUID()
        
        let encryptedPath = photosURL.appendingPathComponent("\(photoId.uuidString).enc")
        let thumbnailPath = photosURL.appendingPathComponent("\(photoId.uuidString)_thumb.jpg")
        let encryptedThumbnailPath = photosURL.appendingPathComponent("\(photoId.uuidString)_thumb.enc")
        
        // Encrypt the media data with error handling
        let encrypted = encryptImage(imageData, password: passwordHash)
        guard encrypted.count > 0 else {
            throw NSError(domain: "VaultManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Encryption failed"])
        }
        
        do {
            try encrypted.write(to: encryptedPath, options: .atomic)
            
            // Generate and store HMAC for integrity verification
            let hmac = generateHMAC(for: encrypted, key: passwordHash)
            let hmacPath = photosURL.appendingPathComponent("\(photoId.uuidString).hmac")
            try hmac.data(using: .utf8)?.write(to: hmacPath, options: .atomic)
        } catch {
            throw NSError(domain: "VaultManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to save encrypted data: \(error.localizedDescription)"])
        }
        
        // Generate thumbnail with memory management
        let thumbnail = generatePhotoThumbnail(from: imageData)
        guard thumbnail.count > 0 else {
            // Clean up encrypted file if thumbnail generation fails
            try? FileManager.default.removeItem(at: encryptedPath)
            throw NSError(domain: "VaultManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Thumbnail generation failed"])
        }
        
        do {
            try thumbnail.write(to: thumbnailPath, options: .atomic)
        } catch {
            // Clean up encrypted file if thumbnail save fails
            try? FileManager.default.removeItem(at: encryptedPath)
            throw NSError(domain: "VaultManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Failed to save thumbnail: \(error.localizedDescription)"])
        }

        let encryptedThumbnail = encryptImage(thumbnail, password: passwordHash)
        guard encryptedThumbnail.count > 0 else {
            // Clean up files if thumbnail encryption fails
            try? FileManager.default.removeItem(at: encryptedPath)
            try? FileManager.default.removeItem(at: thumbnailPath)
            throw NSError(domain: "VaultManager", code: -7, userInfo: [NSLocalizedDescriptionKey: "Thumbnail encryption failed"])
        }
        
        do {
            try encryptedThumbnail.write(to: encryptedThumbnailPath, options: .atomic)
        } catch {
            // Clean up files if encrypted thumbnail save fails
            try? FileManager.default.removeItem(at: encryptedPath)
            try? FileManager.default.removeItem(at: thumbnailPath)
            throw NSError(domain: "VaultManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to save encrypted thumbnail: \(error.localizedDescription)"])
        }
        
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

        // Save to photos list on the main thread to avoid
        // "Publishing changes from background threads" warnings and
        // ensure SwiftUI observers see the update consistently.
        // Use serial queue to prevent race conditions
        vaultQueue.async {
            DispatchQueue.main.async {
                self.hiddenPhotos.append(photo)
                self.savePhotos()
                self.objectWillChange.send()
            }
        }
    }
    
    /// Decrypts a photo or video from the vault.
    /// - Parameter photo: The SecurePhoto record to decrypt
    /// - Returns: Decrypted media data
    /// - Throws: Error if file reading or decryption fails
    func decryptPhoto(_ photo: SecurePhoto) throws -> Data {
        let url = URL(fileURLWithPath: photo.encryptedDataPath)
        let encryptedData = try Data(contentsOf: url)
        
        // Verify HMAC for integrity
        let hmacPath = url.deletingPathExtension().appendingPathExtension("hmac")
        if FileManager.default.fileExists(atPath: hmacPath.path) {
            if let storedHMAC = try? String(contentsOf: hmacPath, encoding: .utf8) {
                let calculatedHMAC = generateHMAC(for: encryptedData, key: passwordHash)
                if storedHMAC != calculatedHMAC {
                    #if DEBUG
                    print("[VaultManager] HMAC verification failed for id=\(photo.id) - file may be corrupted or tampered")
                    #endif
                    throw NSError(domain: "VaultManager", code: -100, userInfo: [NSLocalizedDescriptionKey: "File integrity check failed"])
                }
            }
        }
        
        let decrypted = decryptImage(encryptedData, password: passwordHash)
        if decrypted.isEmpty {
            #if DEBUG
            print("[VaultManager] decryptPhoto: decrypted data is empty for id=\(photo.id), path=\(photo.encryptedDataPath)")
            #endif
        }
        return decrypted
    }

    func decryptThumbnail(for photo: SecurePhoto) throws -> Data {
        // Option 1: be resilient to missing thumbnail files and fall back gracefully.
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            let url = URL(fileURLWithPath: encryptedThumbnailPath)
            if !FileManager.default.fileExists(atPath: url.path) {
                print("[VaultManager] decryptThumbnail: encrypted thumbnail missing for id=\(photo.id). Falling back to legacy thumbnail if available.")
            } else {
                do {
                    let encryptedData = try Data(contentsOf: url)
                    let decrypted = decryptImage(encryptedData, password: passwordHash)
                    if decrypted.isEmpty {
                        print("[VaultManager] decryptThumbnail: decrypted data empty for id=\(photo.id), encThumb=\(encryptedThumbnailPath)")
                    }
                    return decrypted
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
        touchActivity()
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
            
            // Overwrite with random data
            var randomData = Data(count: Int(sizeToOverwrite))
            _ = randomData.withUnsafeMutableBytes { bytes in
                SecRandomCopyBytes(kSecRandomDefault, Int(sizeToOverwrite), bytes.baseAddress!)
            }
            try randomData.write(to: url, options: .atomic)
            
            // Now delete the file
            try FileManager.default.removeItem(at: url)
        } catch {
            #if DEBUG
            print("Secure deletion failed, using standard deletion: \(error)")
            #endif
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    /// Restores a photo or video from the vault to the Photos library.
    /// - Parameter photo: The SecurePhoto to restore
    func restorePhotoToLibrary(_ photo: SecurePhoto) {
        touchActivity()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Decrypt the photo
                let decryptedData = try self.decryptPhoto(photo)
                
                // Save to Photos library (to original album if available) with metadata
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
                        
                        // Delete from vault
                        DispatchQueue.main.async {
                            self.deletePhoto(photo)
                        }
                    } else {
                        print("Failed to restore media to library: \(photo.filename)")
                    }
                }
            } catch {
                print("Failed to decrypt media for restore: \(error)")
            }
        }
    }
    
    /// Restores multiple photos/videos from the vault to the Photos library.
    /// - Parameters:
    ///   - photos: Array of SecurePhoto items to restore
    ///   - restoreToSourceAlbum: Whether to restore to original album
    ///   - toNewAlbum: Optional new album name for all items
    func batchRestorePhotos(_ photos: [SecurePhoto], restoreToSourceAlbum: Bool = false, toNewAlbum: String? = nil) {
        touchActivity()
        // Initialize progress tracking
        DispatchQueue.main.async {
            self.restorationProgress.isRestoring = true
            self.restorationProgress.totalItems = photos.count
            self.restorationProgress.processedItems = 0
            self.restorationProgress.successItems = 0
            self.restorationProgress.failedItems = 0
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
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
            
            let group = DispatchGroup()
            var allRestoredPhotos: [SecurePhoto] = []
            let lock = NSLock()
            
            print("🔄 Starting batch restore of \(photos.count) items grouped into \(albumGroups.count) albums")
            
            // Process each album group
            for (targetAlbum, photosInGroup) in albumGroups {
                group.enter()

                print("📁 Processing group: \(targetAlbum ?? "Library") with \(photosInGroup.count) items")

                // Process photos sequentially (or small batches) to avoid holding many large decrypted Data objects in memory.
                for photo in photosInGroup {
                    autoreleasepool {
                        do {
                            print("  🔓 Decrypting: \(photo.filename) (\(photo.mediaType.rawValue))")
                            let decryptedData = try self.decryptPhoto(photo)
                            print("  ✅ Decrypted successfully: \(photo.filename) - \(decryptedData.count) bytes")

                            // Save each media item individually to keep memory use low.
                            let saveSemaphore = DispatchSemaphore(value: 0)
                            var saveSuccess = false

                            PhotosLibraryService.shared.saveMediaToLibrary(
                                decryptedData,
                                filename: photo.filename,
                                mediaType: photo.mediaType,
                                toAlbum: targetAlbum,
                                creationDate: photo.dateTaken,
                                location: photo.location,
                                isFavorite: photo.isFavorite
                            ) { success in
                                saveSuccess = success
                                saveSemaphore.signal()
                            }

                            // Wait for save to complete before continuing to next item
                            saveSemaphore.wait()

                            // Update progress
                            DispatchQueue.main.async {
                                self.restorationProgress.processedItems += 1
                                if saveSuccess {
                                    self.restorationProgress.successItems += 1
                                } else {
                                    self.restorationProgress.failedItems += 1
                                }
                            }

                            if saveSuccess {
                                lock.lock()
                                allRestoredPhotos.append(photo)
                                lock.unlock()
                            }
                        } catch {
                            print("  ❌ Failed to decrypt \(photo.filename): \(error)")
                            DispatchQueue.main.async {
                                self.restorationProgress.processedItems += 1
                                self.restorationProgress.failedItems += 1
                            }
                        }
                    }
                }

                group.leave()
            }
            
            group.wait()
            
            // Delete all restored photos from vault at once
            DispatchQueue.main.async {
                print("🗑️ Deleting \(allRestoredPhotos.count) restored photos from vault")
                for photo in allRestoredPhotos {
                    self.deletePhoto(photo)
                }
                
                // Mark restoration as complete
                self.restorationProgress.isRestoring = false
                
                // Show summary
                let total = self.restorationProgress.totalItems
                let success = self.restorationProgress.successItems
                let failed = self.restorationProgress.failedItems
                print("📊 Restoration complete: \(success)/\(total) successful, \(failed) failed")
            }
        }
    }
    
    /// Removes duplicate photos from the vault based on asset identifiers.
    func removeDuplicates() {
        DispatchQueue.global(qos: .userInitiated).async {
            var seen = Set<String>()
            var uniquePhotos: [SecurePhoto] = []
            var duplicatesToDelete: [SecurePhoto] = []
            
            for photo in self.hiddenPhotos {
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
    
    private func encryptImage(_ data: Data, password: String) -> Data {
        // Check input data size
        guard data.count > 0 && data.count < 500 * 1024 * 1024 else { // 500MB limit
            #if DEBUG
            print("Encryption failed: data too large or empty")
            #endif
            return Data()
        }
        
        do {
            // Derive a key from the password using SHA-256
            guard let passwordData = password.data(using: .utf8) else {
                #if DEBUG
                print("Encryption failed: invalid password encoding")
                #endif
                return Data()
            }
            let key = SHA256.hash(data: passwordData)
            let symmetricKey = SymmetricKey(data: key)
            
            // Encrypt using AES-GCM
            let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
            
            // Combine nonce + ciphertext + tag for storage
            guard let combined = sealedBox.combined else {
                #if DEBUG
                print("Failed to get combined data from sealed box")
                #endif
                return Data()
            }
            
            return combined
        } catch {
            #if DEBUG
            print("Encryption failed: \(error)")
            #endif
            return Data()
        }
    }
    
    private func decryptImage(_ data: Data, password: String) -> Data {
        // Check input data size
        guard data.count > 0 && data.count < 500 * 1024 * 1024 else { // 500MB limit
            #if DEBUG
            print("Decryption failed: data too large or empty")
            #endif
            return Data()
        }
        
        do {
            // Derive the same key from password
            guard let passwordData = password.data(using: .utf8) else {
                #if DEBUG
                print("Decryption failed: invalid password encoding")
                #endif
                return Data()
            }
            let key = SHA256.hash(data: passwordData)
            let symmetricKey = SymmetricKey(data: key)
            
            // Decrypt using AES-GCM
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
            
            return decrypted
        } catch {
            #if DEBUG
            print("Decryption failed: \(error)")
            #endif
            return Data()
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
        guard videoData.count > 0 && videoData.count < 500 * 1024 * 1024 else { // 500MB limit
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
            print("Failed to generate video thumbnail: \(error)")
            // Clean up temp file if it exists
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Return empty data if thumbnail generation fails
        return Data()
    }
    
    private func savePhotos() {
        guard let data = try? JSONEncoder().encode(hiddenPhotos) else { return }
        #if DEBUG
        print("savePhotos: writing \(hiddenPhotos.count) items to \(photosFile.path)")
        #endif
        try? data.write(to: photosFile)
    }

    private func loadPhotos() {
        #if DEBUG
        print("loadPhotos: reading from \(photosFile.path)")
        #endif
        guard let data = try? Data(contentsOf: photosFile),
            let photos = try? JSONDecoder().decode([SecurePhoto].self, from: data) else {
            #if DEBUG
            print("loadPhotos: no data or decode failed")
            #endif
            return
        }
        #if DEBUG
        print("loadPhotos: loaded \(photos.count) items")
        #endif
        hiddenPhotos = photos
    }
    
    func saveSettings() {
        var settings: [String: String] = [
            "passwordHash": passwordHash,
            "passwordSalt": passwordSalt
        ]
        settings["vaultBaseURL"] = vaultBaseURL.path
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile)
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
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: KeychainKeys.biometricPassword
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new password
        guard let passwordData = password.data(using: .utf8) else { return }
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: KeychainKeys.biometricPassword,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    func getBiometricPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: KeychainKeys.biometricPassword,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    func resetVaultCompletely() {
        // Clear all data and reset to initial state
        passwordHash = ""
        passwordSalt = ""
        isUnlocked = false
        hiddenPhotos = []
        showUnlockPrompt = false
        viewRefreshId = UUID()
        
        // Delete all vault files
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: vaultBaseURL, includingPropertiesForKeys: nil)
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        } catch {
            print("Error clearing vault files: \(error)")
        }
        
        // Recreate photos directory after clearing
        do {
            try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to recreate photos directory: \(error)")
        }
        
        // Save empty settings
        saveSettings()
        
        // Notify observers
        objectWillChange.send()
    }
}
