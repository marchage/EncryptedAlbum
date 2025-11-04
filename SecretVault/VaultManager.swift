import SwiftUI
import Foundation
import CryptoKit

// MARK: - Data Models

struct SecurePhoto: Identifiable, Codable {
    let id: UUID
    var encryptedDataPath: String
    var thumbnailPath: String
    var filename: String
    var dateAdded: Date
    var dateTaken: Date?
    var sourceAlbum: String?
    var vaultAlbum: String? // Custom album within the vault
    var fileSize: Int64
    var originalAssetIdentifier: String? // To track the original Photos library asset
    
    init(id: UUID = UUID(), encryptedDataPath: String, thumbnailPath: String, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, vaultAlbum: String? = nil, fileSize: Int64 = 0, originalAssetIdentifier: String? = nil) {
        self.id = id
        self.encryptedDataPath = encryptedDataPath
        self.thumbnailPath = thumbnailPath
        self.filename = filename
        self.dateAdded = Date()
        self.dateTaken = dateTaken
        self.sourceAlbum = sourceAlbum
        self.vaultAlbum = vaultAlbum
        self.fileSize = fileSize
        self.originalAssetIdentifier = originalAssetIdentifier
    }
}

// MARK: - Vault Manager

class VaultManager: ObservableObject {
    static let shared = VaultManager()
    
    @Published var hiddenPhotos: [SecurePhoto] = []
    @Published var isUnlocked = false
    @Published var showUnlockPrompt = false
    @Published var passwordHash: String = ""
    
    private let photosURL: URL
    private let photosFile: URL
    private let settingsFile: URL
    
    private init() {
        // Use the app's container directory instead of shared Application Support
        // This works with App Sandbox
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseDirectory: URL
        
        if let appSupport = appSupport {
            baseDirectory = appSupport
        } else {
            // Fallback to documents directory if Application Support is unavailable
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                fatalError("Unable to access file system")
            }
            baseDirectory = documents
        }
        
        let appDirectory = baseDirectory.appendingPathComponent("SecretVault", isDirectory: true)
        
        // Initialize the URLs first
        self.photosURL = appDirectory.appendingPathComponent("photos", isDirectory: true)
        self.photosFile = appDirectory.appendingPathComponent("hidden_photos.json")
        self.settingsFile = appDirectory.appendingPathComponent("settings.json")
        
        // Now create directories
        do {
            try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
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
            return true
        }
        return false
    }
    
    func lock() {
        isUnlocked = false
        hiddenPhotos = []
    }
    
    func hasPassword() -> Bool {
        return !passwordHash.isEmpty
    }
    
    func hidePhoto(imageData: Data, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, assetIdentifier: String? = nil) throws {
        // Check for duplicates by asset identifier
        if let assetId = assetIdentifier {
            if hiddenPhotos.contains(where: { $0.originalAssetIdentifier == assetId }) {
                print("Photo already hidden: \(filename)")
                return // Skip duplicate
            }
        }
        
        // Create photo ID and paths
        let photoId = UUID()
        
        let encryptedPath = photosURL.appendingPathComponent("\(photoId.uuidString).enc")
        let thumbnailPath = photosURL.appendingPathComponent("\(photoId.uuidString)_thumb.jpg")
        
        // Simple encryption (XOR for demo - replace with real AES in production)
        let encrypted = encryptImage(imageData, password: passwordHash)
        try encrypted.write(to: encryptedPath)
        
        // Generate thumbnail
        let thumbnail = generateThumbnail(from: imageData)
        try thumbnail.write(to: thumbnailPath)
        
        // Create photo record
        let photo = SecurePhoto(
            encryptedDataPath: encryptedPath.path,
            thumbnailPath: thumbnailPath.path,
            filename: filename,
            dateTaken: dateTaken,
            sourceAlbum: sourceAlbum,
            fileSize: Int64(imageData.count),
            originalAssetIdentifier: assetIdentifier
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
    
    func deletePhoto(_ photo: SecurePhoto) {
        // Delete files
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: photo.encryptedDataPath))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: photo.thumbnailPath))
        
        // Remove from list
        hiddenPhotos.removeAll { $0.id == photo.id }
        savePhotos()
    }
    
    func restorePhotoToLibrary(_ photo: SecurePhoto) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Decrypt the photo
                let decryptedData = try self.decryptPhoto(photo)
                
                // Save to Photos library (to original album if available)
                PhotosLibraryService.shared.saveImageToLibrary(decryptedData, filename: photo.filename, toAlbum: photo.sourceAlbum) { success in
                    if success {
                        print("Photo restored to library: \(photo.filename)")
                        
                        // Delete from vault
                        DispatchQueue.main.async {
                            self.deletePhoto(photo)
                        }
                    } else {
                        print("Failed to restore photo to library: \(photo.filename)")
                    }
                }
            } catch {
                print("Failed to decrypt photo for restore: \(error)")
            }
        }
    }
    
    func batchRestorePhotos(_ photos: [SecurePhoto], restoreToSourceAlbum: Bool = false, toNewAlbum: String? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            var restoredPhotos: [SecurePhoto] = []
            
            for photo in photos {
                group.enter()
                
                do {
                    // Decrypt the photo
                    let decryptedData = try self.decryptPhoto(photo)
                    
                    // Determine target album
                    var targetAlbum: String? = nil
                    if let newAlbum = toNewAlbum {
                        targetAlbum = newAlbum
                    } else if restoreToSourceAlbum {
                        targetAlbum = photo.sourceAlbum
                    }
                    
                    // Save to Photos library
                    PhotosLibraryService.shared.saveImageToLibrary(decryptedData, filename: photo.filename, toAlbum: targetAlbum) { success in
                        if success {
                            print("Photo restored to library: \(photo.filename)")
                            restoredPhotos.append(photo)
                        } else {
                            print("Failed to restore photo to library: \(photo.filename)")
                        }
                        group.leave()
                    }
                } catch {
                    print("Failed to decrypt photo for restore: \(error)")
                    group.leave()
                }
            }
            
            group.wait()
            
            // Delete all restored photos from vault at once
            DispatchQueue.main.async {
                for photo in restoredPhotos {
                    self.deletePhoto(photo)
                }
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
    
    private func generateThumbnail(from imageData: Data) -> Data {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return imageData
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
            return imageData
        }
        
        return jpegData
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
        let settings = ["passwordHash": passwordHash]
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile)
    }
    
    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONDecoder().decode([String: String].self, from: data),
              let hash = settings["passwordHash"] else {
            return
        }
        passwordHash = hash
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
