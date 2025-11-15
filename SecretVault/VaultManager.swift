import SwiftUI
import Foundation
import CryptoKit
import AVFoundation
import LocalAuthentication

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
    @Published var restorationProgress = RestorationProgress()
    @Published var vaultBaseURL: URL = URL(fileURLWithPath: "/tmp")
    @Published var hideNotification: HideNotification? = nil
    @Published var lastActivity: Date = Date()

    /// Idle timeout in seconds before automatically locking the vault when unlocked.
    /// Default is 600 seconds (10 minutes).
    let idleTimeout: TimeInterval = 600
    
    private lazy var photosURL: URL = vaultBaseURL.appendingPathComponent("photos", isDirectory: true)
    private lazy var photosFile: URL = vaultBaseURL.appendingPathComponent("hidden_photos.json")
    private lazy var settingsFile: URL = vaultBaseURL.appendingPathComponent("settings.json")
    private var idleTimer: Timer?
    
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
        #else
        // iOS: Use iCloud Drive if available, otherwise local documents
        let fileManager = FileManager.default
        var baseURL: URL
        
        if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            // iCloud is available
            baseURL = iCloudURL.appendingPathComponent("SecretVault", isDirectory: true)
            print("Using iCloud Drive for vault storage")
        } else {
            // Fallback to local documents
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                fatalError("Unable to access file system")
            }
            baseURL = documentsURL.appendingPathComponent("SecretVault", isDirectory: true)
            print("Using local storage for vault (iCloud not available)")
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
        
        loadSettings()
        if !passwordHash.isEmpty {
            showUnlockPrompt = true
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
    
    func setupPassword(_ password: String) {
        let hash = password.data(using: .utf8)?.base64EncodedString() ?? ""
        passwordHash = hash
        saveSettings()
        // Store password for biometric unlock
        saveBiometricPassword(password)
    }
    
    func unlock(password: String) -> Bool {
        let testHash = password.data(using: .utf8)?.base64EncodedString() ?? ""
        if testHash == passwordHash {
            isUnlocked = true
            loadPhotos()
            // Update stored password for biometric unlock
            saveBiometricPassword(password)
            touchActivity()
            startIdleTimer()
            return true
        }
        return false
    }
    
    func lock() {
        isUnlocked = false
        hiddenPhotos = []
        idleTimer?.invalidate()
        idleTimer = nil
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
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.isUnlocked else { return }

            let elapsed = Date().timeIntervalSince(self.lastActivity)
            if elapsed > self.idleTimeout {
                self.lock()
            }
        }
        if let idleTimer = idleTimer {
            RunLoop.main.add(idleTimer, forMode: .common)
        }
    }
    
    func hidePhoto(imageData: Data, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, assetIdentifier: String? = nil, mediaType: MediaType = .photo, duration: TimeInterval? = nil, location: SecurePhoto.Location? = nil, isFavorite: Bool? = nil) throws {
        touchActivity()
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
        
        // Encrypt the media data
        let encrypted = encryptImage(imageData, password: passwordHash)
        try encrypted.write(to: encryptedPath)
        
        // Generate thumbnail
        let thumbnail = generateThumbnail(from: imageData, mediaType: mediaType)
        try thumbnail.write(to: thumbnailPath)

        let encryptedThumbnail = encryptImage(thumbnail, password: passwordHash)
        try encryptedThumbnail.write(to: encryptedThumbnailPath)
        
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
        
        // Save to photos list
        hiddenPhotos.append(photo)
        savePhotos()
        objectWillChange.send()
    }
    
    func decryptPhoto(_ photo: SecurePhoto) throws -> Data {
        let encryptedData = try Data(contentsOf: URL(fileURLWithPath: photo.encryptedDataPath))
        return decryptImage(encryptedData, password: passwordHash)
    }

    func decryptThumbnail(for photo: SecurePhoto) throws -> Data {
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            let encryptedData = try Data(contentsOf: URL(fileURLWithPath: encryptedThumbnailPath))
            return decryptImage(encryptedData, password: passwordHash)
        } else {
            return try Data(contentsOf: URL(fileURLWithPath: photo.thumbnailPath))
        }
    }
    
    func deletePhoto(_ photo: SecurePhoto) {
        touchActivity()
        // Delete files
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: photo.encryptedDataPath))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: photo.thumbnailPath))
        if let encryptedThumbnailPath = photo.encryptedThumbnailPath {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: encryptedThumbnailPath))
        }
        
        // Remove from list
        hiddenPhotos.removeAll { $0.id == photo.id }
        savePhotos()
    }
    
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
        do {
            // Derive a key from the password using SHA-256
            let passwordData = password.data(using: .utf8) ?? Data()
            let key = SHA256.hash(data: passwordData)
            let symmetricKey = SymmetricKey(data: key)
            
            // Encrypt using AES-GCM
            let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
            
            // Combine nonce + ciphertext + tag for storage
            guard let combined = sealedBox.combined else {
                print("Failed to get combined data from sealed box")
                return data
            }
            
            return combined
        } catch {
            print("Encryption failed: \(error)")
            return data
        }
    }
    
    private func decryptImage(_ data: Data, password: String) -> Data {
        do {
            // Derive the same key from password
            let passwordData = password.data(using: .utf8) ?? Data()
            let key = SHA256.hash(data: passwordData)
            let symmetricKey = SymmetricKey(data: key)
            
            // Decrypt using AES-GCM
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
            
            return decrypted
        } catch {
            print("Decryption failed: \(error)")
            return data
        }
    }
    
    private func generateThumbnail(from mediaData: Data, mediaType: MediaType) -> Data {
        if mediaType == .video {
            // For videos, extract a frame as thumbnail
            return generateVideoThumbnail(from: mediaData)
        } else {
            // For photos, resize the image
            #if os(macOS)
            guard let image = NSImage(data: mediaData),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return mediaData
            }
            
            let maxSize: CGFloat = 300
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let scale = min(maxSize / width, maxSize / height)
            
            let newSize = NSSize(width: width * scale, height: height * scale)
            let thumbnail = NSImage(size: newSize)
            thumbnail.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            thumbnail.unlockFocus()
            
            guard let tiffData = thumbnail.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
                return mediaData
            }
            
            return jpegData
            #else
            guard let image = UIImage(data: mediaData) else {
                return mediaData
            }
            
            let maxSize: CGFloat = 300
            let size = image.size
            let scale = min(maxSize / size.width, maxSize / size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext(),
                  let jpegData = resizedImage.jpegData(compressionQuality: 0.8) else {
                UIGraphicsEndImageContext()
                return mediaData
            }
            UIGraphicsEndImageContext()
            
            return jpegData
            #endif
        }
    }
    
    private func generateVideoThumbnail(from videoData: Data) -> Data {
        // Write video data to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        do {
            try videoData.write(to: tempURL)
            
            let asset = AVAsset(url: tempURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            let time = CMTime(seconds: 1, preferredTimescale: 60)
            if let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
                #if os(macOS)
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                
                // Resize thumbnail
                let maxSize: CGFloat = 300
                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)
                let scale = min(maxSize / width, maxSize / height)
                
                let newSize = NSSize(width: width * scale, height: height * scale)
                let thumbnail = NSImage(size: newSize)
                thumbnail.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: newSize))
                thumbnail.unlockFocus()
                
                if let tiffData = thumbnail.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) {
                    try? FileManager.default.removeItem(at: tempURL)
                    return jpegData
                }
                #else
                let image = UIImage(cgImage: cgImage)
                
                // Resize thumbnail
                let maxSize: CGFloat = 300
                let size = image.size
                let scale = min(maxSize / size.width, maxSize / size.height)
                let newSize = CGSize(width: size.width * scale, height: size.height * scale)
                
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext(),
                      let jpegData = resizedImage.jpegData(compressionQuality: 0.8) else {
                    UIGraphicsEndImageContext()
                    try? FileManager.default.removeItem(at: tempURL)
                    return Data()
                }
                UIGraphicsEndImageContext()
                
                try? FileManager.default.removeItem(at: tempURL)
                return jpegData
                #endif
            }
            
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("Failed to generate video thumbnail: \(error)")
        }
        
        // Return a placeholder if thumbnail generation fails
        return Data()
    }
    
    private func savePhotos() {
        guard let data = try? JSONEncoder().encode(hiddenPhotos) else { return }
        try? data.write(to: photosFile)
    }
    
    private func loadPhotos() {
        guard let data = try? Data(contentsOf: photosFile),
              let photos = try? JSONDecoder().decode([SecurePhoto].self, from: data) else {
            return
        }
        hiddenPhotos = photos
    }
    
    private func saveSettings() {
        var settings: [String: String] = ["passwordHash": passwordHash]
        settings["vaultBaseURL"] = vaultBaseURL.path
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile)
    }
    
    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }

        if let hash = settings["passwordHash"] {
            passwordHash = hash
        }
        if let basePath = settings["vaultBaseURL"] {
            let url = URL(fileURLWithPath: basePath, isDirectory: true)
            vaultBaseURL = url
        }
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
        let keychainKey = "SecretVault.BiometricPassword"
        
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new password
        guard let passwordData = password.data(using: .utf8) else { return }
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    func getBiometricPassword() -> String? {
        let keychainKey = "SecretVault.BiometricPassword"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
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
}
