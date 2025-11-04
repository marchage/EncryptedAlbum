import SwiftUI
import Foundation

// MARK: - Data Models

struct SecurePhoto: Identifiable, Codable {
    let id: UUID
    var encryptedDataPath: String
    var thumbnailPath: String
    var filename: String
    var dateAdded: Date
    var dateTaken: Date?
    var sourceAlbum: String?
    var fileSize: Int64
    var originalAssetIdentifier: String? // To track the original Photos library asset
    
    init(id: UUID = UUID(), encryptedDataPath: String, thumbnailPath: String, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, fileSize: Int64 = 0, originalAssetIdentifier: String? = nil) {
        self.id = id
        self.encryptedDataPath = encryptedDataPath
        self.thumbnailPath = thumbnailPath
        self.filename = filename
        self.dateAdded = Date()
        self.dateTaken = dateTaken
        self.sourceAlbum = sourceAlbum
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
    }
    
    func unlock(password: String) -> Bool {
        let testHash = password.data(using: .utf8)?.base64EncodedString() ?? ""
        if testHash == passwordHash {
            isUnlocked = true
            loadPhotos()
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
    
    func removeDuplicates() {
        var seen = Set<String>()
        var uniquePhotos: [SecurePhoto] = []
        var duplicatesToDelete: [SecurePhoto] = []
        
        for photo in hiddenPhotos {
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
        
        hiddenPhotos = uniquePhotos
        savePhotos()
        
        print("Removed \(duplicatesToDelete.count) duplicate photos")
    }
    
    private func encryptImage(_ data: Data, password: String) -> Data {
        // Simple XOR encryption (use AES-256 in production)
        let key = password.data(using: .utf8) ?? Data()
        var encrypted = Data()
        for (index, byte) in data.enumerated() {
            let keyByte = key[index % key.count]
            encrypted.append(byte ^ keyByte)
        }
        return encrypted
    }
    
    private func decryptImage(_ data: Data, password: String) -> Data {
        // XOR is reversible
        return encryptImage(data, password: password)
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
}
