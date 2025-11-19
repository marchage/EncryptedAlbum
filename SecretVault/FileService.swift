import Foundation
import CryptoKit
#if os(iOS)
import UIKit
import Photos
#endif

/// Service responsible for all file system operations in the vault
class FileService {
    private let cryptoService: CryptoService

    init(cryptoService: CryptoService) {
        self.cryptoService = cryptoService
    }

    // MARK: - Directory Management

    /// Creates the photos directory if it doesn't exist
    func createPhotosDirectory(in vaultURL: URL) async throws -> URL {
        let photosURL = vaultURL.appendingPathComponent(FileConstants.photosDirectoryName)
        try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true, attributes: nil)
        return photosURL
    }

    // MARK: - File Operations

    /// Saves encrypted data to file with integrity protection
    func saveEncryptedFile(data: Data, filename: String, to directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) async throws {
        let fileURL = directory.appendingPathComponent(filename)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            throw VaultError.fileAlreadyExists(path: fileURL.path)
        }

        // Encrypt data with integrity
        let (encryptedData, nonce, hmac) = try await self.cryptoService.encryptDataWithIntegrity(data, encryptionKey: encryptionKey, hmacKey: hmacKey)

        // Write encrypted data
        try encryptedData.write(to: fileURL, options: .atomic)

        // Write nonce as extended attribute
        try self.setExtendedAttribute(name: "com.secretvault.nonce", data: nonce, at: fileURL)

        // Write HMAC as extended attribute
        try self.setExtendedAttribute(name: "com.secretvault.hmac", data: hmac, at: fileURL)
    }

    /// Loads and decrypts file with integrity verification
    func loadEncryptedFile(filename: String, from directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) async throws -> Data {
        let fileURL = directory.appendingPathComponent(filename)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.fileNotFound(path: fileURL.path)
        }

        // Read encrypted data
        let encryptedData = try Data(contentsOf: fileURL)

        // Read nonce from extended attribute
        guard let nonce = try self.getExtendedAttribute(name: "com.secretvault.nonce", at: fileURL) else {
            throw VaultError.fileReadFailed(path: fileURL.path, reason: "Missing nonce")
        }

        // Read HMAC from extended attribute
        guard let hmac = try self.getExtendedAttribute(name: "com.secretvault.hmac", at: fileURL) else {
            throw VaultError.fileReadFailed(path: fileURL.path, reason: "Missing HMAC")
        }

        // Decrypt with integrity verification
        let decryptedData = try await self.cryptoService.decryptDataWithIntegrity(encryptedData, nonce: nonce, hmac: hmac, encryptionKey: encryptionKey, hmacKey: hmacKey)

        return decryptedData
    }

    /// Securely deletes a file with multiple pass overwrite
    func secureDeleteFile(at url: URL) async throws {
        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        if fileSize > CryptoConstants.maxSecureDeleteSize {
            // For large files, just remove normally
            try FileManager.default.removeItem(at: url)
            return
        }

        // Multi-pass secure deletion
        try self.performSecureDeletion(at: url, fileSize: Int(fileSize))
    }

    private func performSecureDeletion(at url: URL, fileSize: Int) throws {
        let fileHandle = try FileHandle(forUpdating: url)

        let randomData = Data((0..<fileSize).map { _ in UInt8.random(in: .min ... .max) })
        fileHandle.seek(toFileOffset: 0)
        fileHandle.write(randomData)

        // Pass 2: Inverse of random data
        let inverseData = Data(randomData.map { ~$0 })
        fileHandle.seek(toFileOffset: 0)
        fileHandle.write(inverseData)

        // Pass 3: Random data again
        let randomData2 = try Data(count: fileSize)
        fileHandle.seek(toFileOffset: 0)
        fileHandle.write(randomData2)

        try fileHandle.close()

        // Finally remove the file
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Thumbnail Operations

#if os(iOS)
    /// Generates and saves thumbnail for an image
    func generateAndSaveThumbnail(for imageData: Data, filename: String, to directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) async throws {
        guard let image = UIImage(data: imageData) else {
            throw VaultError.invalidFileFormat(reason: "Invalid image data")
        }

        let thumbnail = try self.generateThumbnail(from: image)
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: CryptoConstants.thumbnailCompressionQuality) else {
            throw VaultError.invalidFileFormat(reason: "Failed to compress thumbnail")
        }

        let thumbnailFilename = filename.replacingOccurrences(of: ".\(FileConstants.encryptedFileExtension)", with: FileConstants.encryptedThumbnailSuffix)
        try await self.saveEncryptedFile(data: thumbnailData, filename: thumbnailFilename, to: directory, encryptionKey: encryptionKey, hmacKey: hmacKey)
    }

    /// Loads and decrypts thumbnail
    func loadThumbnail(filename: String, from directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) async throws -> UIImage? {
        let thumbnailFilename = filename.replacingOccurrences(of: ".\(FileConstants.encryptedFileExtension)", with: FileConstants.encryptedThumbnailSuffix)
        let thumbnailData = try await self.loadEncryptedFile(filename: thumbnailFilename, from: directory, encryptionKey: encryptionKey, hmacKey: hmacKey)

        guard let image = UIImage(data: thumbnailData) else {
            return nil
        }

        return image
    }

    private func generateThumbnail(from image: UIImage) throws -> UIImage {
        let size = image.size

        let maxDimension = CryptoConstants.maxThumbnailDimension
        let aspectRatio = size.width / size.height

        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))

        guard let thumbnail = UIGraphicsGetImageFromCurrentImageContext() else {
            throw VaultError.invalidFileFormat(reason: "Failed to generate thumbnail")
        }

        return thumbnail
    }
#endif

    // MARK: - Extended Attributes

    private func setExtendedAttribute(name: String, data: Data, at url: URL) throws {
        let result = data.withUnsafeBytes { bytes in
            setxattr(url.path, name, bytes.baseAddress, bytes.count, 0, 0)
        }
        if result != 0 {
            throw VaultError.fileWriteFailed(path: url.path, reason: "Failed to set extended attribute '\(name)'")
        }
    }

    private func getExtendedAttribute(name: String, at url: URL) throws -> Data? {
        let bufferSize = getxattr(url.path, name, nil, 0, 0, 0)
        if bufferSize == -1 {
            return nil // Attribute doesn't exist
        }

        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let result = buffer.withUnsafeMutableBytes { bytes in
            getxattr(url.path, name, bytes.baseAddress, bufferSize, 0, 0)
        }

        if result == -1 {
            throw VaultError.fileReadFailed(path: url.path, reason: "Failed to read extended attribute '\(name)'")
        }

        return Data(buffer)
    }

    // MARK: - Utility Functions

    /// Gets file size safely
    func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    /// Checks if file exists
    func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Lists all files in directory
    func listFiles(in directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
        return contents.filter { $0.pathExtension == FileConstants.encryptedFileExtension }
    }
}
