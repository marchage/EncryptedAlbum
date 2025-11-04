import SwiftUI
import Foundation

// MARK: - Data Models

struct Vault: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String
    var photoCount: Int
    var passwordHash: String
    var salt: Data
    
    init(id: UUID = UUID(), name: String, color: String = "blue", passwordHash: String, salt: Data) {
        self.id = id
        self.name = name
        self.color = color
        self.photoCount = 0
        self.passwordHash = passwordHash
        self.salt = salt
    }
    
    var colorValue: Color {
        switch color {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "green": return .green
        default: return .blue
        }
    }
}

struct SecurePhoto: Identifiable, Codable {
    let id: UUID
    var vaultId: UUID
    var encryptedDataPath: String
    var thumbnailPath: String
    var filename: String
    var dateAdded: Date
    var dateTaken: Date?
    var sourceAlbum: String?
    var fileSize: Int64
    
    init(id: UUID = UUID(), vaultId: UUID, encryptedDataPath: String, thumbnailPath: String, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil, fileSize: Int64 = 0) {
        self.id = id
        self.vaultId = vaultId
        self.encryptedDataPath = encryptedDataPath
        self.thumbnailPath = thumbnailPath
        self.filename = filename
        self.dateAdded = Date()
        self.dateTaken = dateTaken
        self.sourceAlbum = sourceAlbum
        self.fileSize = fileSize
    }
}

// MARK: - Vault Manager

class VaultManager: ObservableObject {
    static let shared = VaultManager()
    
    @Published var vaults: [Vault] = []
    @Published var unlockedVaults: Set<UUID> = []
    @Published var showCreateVault = false
    
    private let vaultsURL: URL
    private let photosURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("SecretVault", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        vaultsURL = appDirectory.appendingPathComponent("vaults.json")
        photosURL = appDirectory.appendingPathComponent("photos", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        
        loadVaults()
    }
    
    func createVault(name: String, password: String, color: String) -> Bool {
        // Simple hash for demo (in production, use proper PBKDF2)
        let salt = Data(UUID().uuidString.utf8)
        let passwordHash = password.data(using: .utf8)?.base64EncodedString() ?? ""
        
        let vault = Vault(name: name, color: color, passwordHash: passwordHash, salt: salt)
        vaults.append(vault)
        saveVaults()
        
        let vaultDir = photosURL.appendingPathComponent(vault.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        
        return true
    }
    
    func unlockVault(_ vault: Vault, password: String) -> Bool {
        let testHash = password.data(using: .utf8)?.base64EncodedString() ?? ""
        if testHash == vault.passwordHash {
            unlockedVaults.insert(vault.id)
            return true
        }
        return false
    }
    
    func lockVault(_ vaultId: UUID) {
        unlockedVaults.remove(vaultId)
    }
    
    func isVaultUnlocked(_ vaultId: UUID) -> Bool {
        unlockedVaults.contains(vaultId)
    }
    
    func getPhotos(for vaultId: UUID) -> [SecurePhoto] {
        let photosFile = photosURL.appendingPathComponent(vaultId.uuidString).appendingPathComponent("photos.json")
        guard let data = try? Data(contentsOf: photosFile),
              let photos = try? JSONDecoder().decode([SecurePhoto].self, from: data) else {
            return []
        }
        return photos
    }
    
    func addPhoto(to vault: Vault, imageData: Data, filename: String, dateTaken: Date? = nil, sourceAlbum: String? = nil) throws {
        // Create photo ID and paths
        let photoId = UUID()
        let vaultDir = photosURL.appendingPathComponent(vault.id.uuidString, isDirectory: true)
        
        let encryptedPath = vaultDir.appendingPathComponent("\(photoId.uuidString).enc")
        let thumbnailPath = vaultDir.appendingPathComponent("\(photoId.uuidString)_thumb.jpg")
        
        // Simple encryption (XOR for demo - replace with real AES in production)
        let encrypted = encryptImage(imageData, password: vault.passwordHash)
        try encrypted.write(to: encryptedPath)
        
        // Generate thumbnail
        let thumbnail = generateThumbnail(from: imageData)
        try thumbnail.write(to: thumbnailPath)
        
        // Create photo record
        let photo = SecurePhoto(
            vaultId: vault.id,
            encryptedDataPath: encryptedPath.path,
            thumbnailPath: thumbnailPath.path,
            filename: filename,
            dateTaken: dateTaken,
            sourceAlbum: sourceAlbum,
            fileSize: Int64(imageData.count)
        )
        
        // Save to photos list
        var photos = getPhotos(for: vault.id)
        photos.append(photo)
        savePhotos(photos, for: vault.id)
        
        // Update vault photo count
        if let index = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[index].photoCount += 1
            saveVaults()
        }
    }
    
    func decryptPhoto(_ photo: SecurePhoto, vault: Vault) throws -> Data {
        let encryptedData = try Data(contentsOf: URL(fileURLWithPath: photo.encryptedDataPath))
        return decryptImage(encryptedData, password: vault.passwordHash)
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
    
    private func savePhotos(_ photos: [SecurePhoto], for vaultId: UUID) {
        let photosFile = photosURL.appendingPathComponent(vaultId.uuidString).appendingPathComponent("photos.json")
        guard let data = try? JSONEncoder().encode(photos) else { return }
        try? data.write(to: photosFile)
    }
    
    private func loadVaults() {
        guard let data = try? Data(contentsOf: vaultsURL),
              let decoded = try? JSONDecoder().decode([Vault].self, from: data) else {
            return
        }
        vaults = decoded
    }
    
    private func saveVaults() {
        guard let data = try? JSONEncoder().encode(vaults) else { return }
        try? data.write(to: vaultsURL)
        objectWillChange.send()
    }
}
