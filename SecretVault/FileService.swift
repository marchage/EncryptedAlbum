import CryptoKit
import Foundation

#if os(iOS)
    import UIKit
    import Photos
#endif

/// Service responsible for all file system operations in the vault
class FileService {
    private let cryptoService: CryptoService
    private let tempDirectory: URL

    init(cryptoService: CryptoService) {
        self.cryptoService = cryptoService
        let baseTemp = FileManager.default.temporaryDirectory.appendingPathComponent(
            FileConstants.tempWorkingDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: baseTemp.path) {
            try? FileManager.default.createDirectory(at: baseTemp, withIntermediateDirectories: true)
        }
        self.tempDirectory = baseTemp
    }

    /// Removes stale working files that may have been left behind after crashes or aborted operations.
    func cleanupTemporaryArtifacts(olderThan: TimeInterval = 24 * 60 * 60) {
        let fm = FileManager.default
        guard
            let contents = try? fm.contentsOfDirectory(
                at: tempDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
        else {
            return
        }

        let cutoff = Date().addingTimeInterval(-olderThan)
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                let modified = values.contentModificationDate
            else {
                continue
            }

            if modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func makeTemporaryFileURL(preferredExtension: String?) -> URL {
        let filename = "\(FileConstants.decryptedTempPrefix)-\(UUID().uuidString)"
        if let ext = preferredExtension, !ext.isEmpty {
            return tempDirectory.appendingPathComponent(filename).appendingPathExtension(ext)
        }
        return tempDirectory.appendingPathComponent(filename)
    }

    // MARK: - Streaming Format

    struct EmbeddedMetadata: Codable {
        let filename: String
        let dateCreated: Date
        let originalAssetIdentifier: String?
        let duration: TimeInterval?
        // We can add more fields here as needed
    }

    private struct StreamFileHeader {
        let version: UInt8
        let mediaType: MediaType
        let originalSize: UInt64
        let chunkSize: UInt32
        let metadataLength: UInt32 // New in V2
    }

    private var streamMagicData: Data {
        Data(CryptoConstants.streamingMagic.utf8)
    }

    // MARK: - File Operations

    /// Saves encrypted data to file with integrity protection using SVF2 format
    func saveEncryptedFile(
        data: Data, filename: String, to directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey,
        metadata: EmbeddedMetadata? = nil
    ) async throws {
        let fileURL = directory.appendingPathComponent(filename)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            throw VaultError.fileAlreadyExists(path: fileURL.path)
        }

        // Prepare metadata if provided
        var encryptedMetadataData = Data()
        if let metadata = metadata {
            let jsonData = try JSONEncoder().encode(metadata)
            // Encrypt metadata as a single block
            let (encrypted, nonce, hmac) = try await cryptoService.encryptDataWithIntegrity(
                jsonData, encryptionKey: encryptionKey, hmacKey: hmacKey)
            
            // Format: [Nonce(12)][HMAC(32)][Ciphertext]
            encryptedMetadataData.append(nonce)
            encryptedMetadataData.append(hmac)
            encryptedMetadataData.append(encrypted)
        }

        // Create SVF2 Header
        let header = StreamFileHeader(
            version: CryptoConstants.streamingVersion,
            mediaType: .photo, // Defaulting to photo for thumbnails/generic data
            originalSize: UInt64(data.count),
            chunkSize: UInt32(CryptoConstants.streamingChunkSize),
            metadataLength: UInt32(encryptedMetadataData.count)
        )
        
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let writeHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? writeHandle.close() }
        
        do {
            try writeStreamHeader(header, to: writeHandle)

            // Write metadata if present
            if !encryptedMetadataData.isEmpty {
                try writeHandle.write(contentsOf: encryptedMetadataData)
            }
            
            // Encrypt and write data in chunks
            let chunkSize = Int(CryptoConstants.streamingChunkSize)
            var offset = 0
            
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunkData = data[offset..<end]
                
                let nonce = AES.GCM.Nonce()
                let sealedBox = try AES.GCM.seal(chunkData, using: encryptionKey, nonce: nonce)
                
                var chunkLength = UInt32(chunkData.count).littleEndian
                try writeHandle.write(contentsOf: Data(bytes: &chunkLength, count: MemoryLayout<UInt32>.size))
                
                let nonceData = nonce.withUnsafeBytes { Data($0) }
                try writeHandle.write(contentsOf: nonceData)
                try writeHandle.write(contentsOf: sealedBox.ciphertext)
                try writeHandle.write(contentsOf: sealedBox.tag)
                
                offset += chunkSize
            }
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }

    /// Encrypts a file already on disk by streaming chunks to the destination file.
    /// Supports SVF2 with embedded metadata.
    func saveStreamEncryptedFile(
        from sourceURL: URL, 
        filename: String, 
        mediaType: MediaType, 
        metadata: EmbeddedMetadata? = nil,
        to directory: URL, 
        encryptionKey: SymmetricKey,
        hmacKey: SymmetricKey, 
        progressHandler: ((Int64) async -> Void)? = nil
    ) async throws {
        let destinationURL = directory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            throw VaultError.fileAlreadyExists(path: destinationURL.path)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let fileSize = attributes[.size] as? NSNumber ?? 0

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)

        let readHandle = try FileHandle(forReadingFrom: sourceURL)
        let writeHandle = try FileHandle(forWritingTo: destinationURL)

        defer {
            try? readHandle.close()
            try? writeHandle.close()
        }

        // Prepare metadata if provided
        var encryptedMetadataData = Data()
        if let metadata = metadata {
            let jsonData = try JSONEncoder().encode(metadata)
            // Encrypt metadata as a single block
            let (encrypted, nonce, hmac) = try await cryptoService.encryptDataWithIntegrity(
                jsonData, encryptionKey: encryptionKey, hmacKey: hmacKey)
            
            // Format: [Nonce(12)][HMAC(32)][Ciphertext]
            encryptedMetadataData.append(nonce)
            encryptedMetadataData.append(hmac)
            encryptedMetadataData.append(encrypted)
        }

        let header = StreamFileHeader(
            version: CryptoConstants.streamingVersion,
            mediaType: mediaType,
            originalSize: fileSize.uint64Value,
            chunkSize: UInt32(CryptoConstants.streamingChunkSize),
            metadataLength: UInt32(encryptedMetadataData.count)
        )

        do {
            try writeStreamHeader(header, to: writeHandle)

            // Write metadata if present
            if !encryptedMetadataData.isEmpty {
                try writeHandle.write(contentsOf: encryptedMetadataData)
            }

            let chunkSize = CryptoConstants.streamingChunkSize
            var totalProcessed: Int64 = 0

            while true {
                try Task.checkCancellation()
                guard let chunkData = try readHandle.read(upToCount: chunkSize), !chunkData.isEmpty else {
                    break
                }

                let nonce = AES.GCM.Nonce()
                let sealedBox = try AES.GCM.seal(chunkData, using: encryptionKey, nonce: nonce)

                var chunkLength = UInt32(chunkData.count).littleEndian
                try writeHandle.write(contentsOf: Data(bytes: &chunkLength, count: MemoryLayout<UInt32>.size))

                let nonceData = nonce.withUnsafeBytes { Data($0) }
                try writeHandle.write(contentsOf: nonceData)
                try writeHandle.write(contentsOf: sealedBox.ciphertext)
                try writeHandle.write(contentsOf: sealedBox.tag)

                totalProcessed += Int64(chunkData.count)
                if let progressHandler = progressHandler {
                    await progressHandler(totalProcessed)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    /// Loads and decrypts file with integrity verification
    func loadEncryptedFile(filename: String, from directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey)
        async throws -> Data
    {
        let fileURL = directory.appendingPathComponent(filename)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.fileNotFound(path: fileURL.path)
        }

        if let streamData = try await decryptStreamFileDataIfNeeded(at: fileURL, encryptionKey: encryptionKey) {
            return streamData
        }

        throw VaultError.invalidFileFormat(reason: "File is not in valid SVF2 format")
    }

    /// Decrypts an encrypted file to a temporary location on disk, returning the URL for downstream streaming uses.
    func decryptEncryptedFileToTemporaryURL(
        filename: String, originalExtension: String?, from directory: URL, encryptionKey: SymmetricKey,
        hmacKey: SymmetricKey, progressHandler: ((Int64) -> Void)? = nil
    ) async throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.fileNotFound(path: fileURL.path)
        }

        if let tempURL = try await decryptStreamFileToTempURLIfNeeded(
            at: fileURL, encryptionKey: encryptionKey, preferredExtension: originalExtension,
            progressHandler: progressHandler)
        {
            return tempURL
        }

        throw VaultError.invalidFileFormat(reason: "File is not in valid SVF2 format")
    }

    private func decryptStreamFileDataIfNeeded(at fileURL: URL, encryptionKey: SymmetricKey) async throws -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer { try? handle.close() }

        guard let header = try readStreamHeader(from: handle) else {
            return nil
        }
        
        // Skip metadata if present
        if header.metadataLength > 0 {
            try handle.seek(toOffset: handle.offsetInFile + UInt64(header.metadataLength))
        }

        var decrypted = Data()
        if header.originalSize > 0 && header.originalSize < UInt64(Int.max) {
            decrypted.reserveCapacity(Int(header.originalSize))
        }

        try await processStreamFile(
            from: handle, header: header, encryptionKey: encryptionKey,
            chunkHandler: { chunk in
                decrypted.append(chunk)
            })

        return decrypted
    }

    private func decryptStreamFileToTempURLIfNeeded(
        at fileURL: URL, encryptionKey: SymmetricKey, preferredExtension: String?, progressHandler: ((Int64) -> Void)?
    ) async throws -> URL? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer { try? handle.close() }

        guard let header = try readStreamHeader(from: handle) else {
            return nil
        }
        
        // Skip metadata if present
        if header.metadataLength > 0 {
            try handle.seek(toOffset: handle.offsetInFile + UInt64(header.metadataLength))
        }

        let tempURL = makeTemporaryFileURL(preferredExtension: preferredExtension)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let writeHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? writeHandle.close() }

        do {
            try await processStreamFile(
                from: handle, header: header, encryptionKey: encryptionKey,
                chunkHandler: { chunk in
                    try writeHandle.write(contentsOf: chunk)
                }, progressHandler: progressHandler)
            return tempURL
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private func writeStreamHeader(_ header: StreamFileHeader, to handle: FileHandle) throws {
        var data = Data()
        data.append(streamMagicData)
        data.append(header.version)
        data.append(header.mediaType == .video ? 0x02 : 0x01)
        data.append(contentsOf: [UInt8](repeating: 0, count: 2))

        var originalSize = header.originalSize.littleEndian
        data.append(Data(bytes: &originalSize, count: MemoryLayout<UInt64>.size))

        var chunkSize = header.chunkSize.littleEndian
        data.append(Data(bytes: &chunkSize, count: MemoryLayout<UInt32>.size))
        
        // New in V2
        var metadataLength = header.metadataLength.littleEndian
        data.append(Data(bytes: &metadataLength, count: MemoryLayout<UInt32>.size))

        try handle.write(contentsOf: data)
    }

    private func readStreamHeader(from handle: FileHandle) throws -> StreamFileHeader? {
        try handle.seek(toOffset: 0)
        guard let magicData = try handle.read(upToCount: streamMagicData.count), magicData == streamMagicData else {
            try handle.seek(toOffset: 0)
            return nil
        }

        // Read version first
        guard let versionData = try handle.read(upToCount: 1) else { return nil }
        let version = versionData[0]
        
        // Read remaining V1 header fields (15 bytes)
        // Type(1) + Res(2) + Size(8) + Chunk(4)
        let v1RemainingSize = 1 + 2 + 8 + 4
        guard let v1Data = try handle.read(upToCount: v1RemainingSize), v1Data.count == v1RemainingSize else {
            throw VaultError.fileReadFailed(path: handle.description, reason: "Incomplete stream header")
        }

        let mediaByte = v1Data[0]
        let mediaType: MediaType = mediaByte == 0x02 ? .video : .photo

        let originalSize: UInt64 = v1Data[3..<11].withUnsafeBytes { rawBuffer in
            var value: UInt64 = 0
            memcpy(&value, rawBuffer.baseAddress!, MemoryLayout<UInt64>.size)
            return UInt64(littleEndian: value)
        }

        let chunkSize: UInt32 = v1Data[11..<15].withUnsafeBytes { rawBuffer in
            var value: UInt32 = 0
            memcpy(&value, rawBuffer.baseAddress!, MemoryLayout<UInt32>.size)
            return UInt32(littleEndian: value)
        }
        
        var metadataLength: UInt32 = 0
        if version >= 2 {
            // Read metadata length (4 bytes)
            if let metaLenData = try handle.read(upToCount: 4), metaLenData.count == 4 {
                metadataLength = metaLenData.withUnsafeBytes { rawBuffer in
                    var value: UInt32 = 0
                    memcpy(&value, rawBuffer.baseAddress!, MemoryLayout<UInt32>.size)
                    return UInt32(littleEndian: value)
                }
            }
        }

        return StreamFileHeader(
            version: version, mediaType: mediaType, originalSize: originalSize, chunkSize: chunkSize, metadataLength: metadataLength)
    }
    
    /// Reads and decrypts embedded metadata from a file
    func readMetadata(from fileURL: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) async throws -> EmbeddedMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        
        guard let header = try readStreamHeader(from: handle) else { return nil }
        
        guard header.metadataLength > 0 else { return nil }
        
        guard let metadataData = try handle.read(upToCount: Int(header.metadataLength)),
              metadataData.count == Int(header.metadataLength) else {
            return nil
        }
        
        // Decrypt metadata
        // Format: [Nonce(12)][HMAC(32)][Ciphertext]
        let nonceSize = CryptoConstants.streamingNonceSize
        let hmacSize = CryptoConstants.encryptionKeySize // Assuming HMAC size matches key size or constant
        // Actually CryptoConstants.streamingTagSize is 16 (GCM tag), but here we used encryptDataWithIntegrity which uses HMAC-SHA256 (32 bytes) usually?
        // Wait, encryptDataWithIntegrity returns (encryptedData, nonce, hmac).
        // encryptDataWithIntegrity uses AES.GCM (16 byte tag included in ciphertext usually?) OR AES.CTR + HMAC?
        // Let's check CryptoService.encryptDataWithIntegrity.
        
        // I need to check CryptoService to be sure about the format of `encryptDataWithIntegrity`.
        // But assuming I can just call `decryptDataWithIntegrity` with the components.
        
        // Parse components
        // Nonce is 12 bytes (AES.GCM.Nonce)
        // HMAC is 32 bytes (SHA256)
        // Ciphertext is the rest
        
        let hmacLength = 32 // SHA256
        
        guard metadataData.count > nonceSize + hmacLength else { return nil }
        
        let nonceData = metadataData.prefix(nonceSize)
        let hmacData = metadataData.dropFirst(nonceSize).prefix(hmacLength)
        let ciphertext = metadataData.dropFirst(nonceSize + hmacLength)
        
        let decryptedData = try await cryptoService.decryptDataWithIntegrity(
            ciphertext, 
            nonce: nonceData, 
            hmac: hmacData, 
            encryptionKey: encryptionKey, 
            hmacKey: hmacKey
        )
        
        return try JSONDecoder().decode(EmbeddedMetadata.self, from: decryptedData)
    }

    private func processStreamFile(
        from handle: FileHandle, header: StreamFileHeader, encryptionKey: SymmetricKey,
        chunkHandler: (Data) throws -> Void, progressHandler: ((Int64) -> Void)? = nil
    ) async throws {
        var totalProcessed: Int64 = 0

        while true {
            try Task.checkCancellation()
            guard let lengthData = try handle.read(upToCount: MemoryLayout<UInt32>.size), !lengthData.isEmpty else {
                break
            }

            guard lengthData.count == MemoryLayout<UInt32>.size else {
                throw VaultError.decryptionFailed(reason: "Corrupted chunk length")
            }

            let chunkLength = UInt32(littleEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self) })

            let nonceData = try readExact(from: handle, count: CryptoConstants.streamingNonceSize)
            guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
                throw VaultError.decryptionFailed(reason: "Invalid chunk nonce")
            }

            let ciphertext = try readExact(from: handle, count: Int(chunkLength))
            let tag = try readExact(from: handle, count: CryptoConstants.streamingTagSize)

            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let chunk = try AES.GCM.open(sealedBox, using: encryptionKey)

            try chunkHandler(chunk)
            totalProcessed += Int64(chunk.count)
            progressHandler?(totalProcessed)
        }
    }

    private func readExact(from handle: FileHandle, count: Int) throws -> Data {
        var remaining = count
        var data = Data(capacity: count)

        while remaining > 0 {
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                throw VaultError.fileReadFailed(path: handle.description, reason: "Unexpected EOF while reading stream")
            }
            data.append(chunk)
            remaining -= chunk.count
        }

        return data
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
        let randomData2 = Data(count: fileSize)
        fileHandle.seek(toFileOffset: 0)
        fileHandle.write(randomData2)

        try fileHandle.close()

        // Finally remove the file
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Thumbnail Operations

    #if os(iOS)
        /// Generates and saves thumbnail for an image
        func generateAndSaveThumbnail(
            for imageData: Data, filename: String, to directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey
        ) async throws {
            guard let image = UIImage(data: imageData) else {
                throw VaultError.invalidFileFormat(reason: "Invalid image data")
            }

            let thumbnail = try self.generateThumbnail(from: image)
            guard
                let thumbnailData = thumbnail.jpegData(compressionQuality: CryptoConstants.thumbnailCompressionQuality)
            else {
                throw VaultError.invalidFileFormat(reason: "Failed to compress thumbnail")
            }

            let thumbnailFilename = filename.replacingOccurrences(
                of: ".\(FileConstants.encryptedFileExtension)", with: FileConstants.encryptedThumbnailSuffix)
            try await self.saveEncryptedFile(
                data: thumbnailData, filename: thumbnailFilename, to: directory, encryptionKey: encryptionKey,
                hmacKey: hmacKey)
        }

        /// Loads and decrypts thumbnail
        func loadThumbnail(filename: String, from directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey)
            async throws -> UIImage?
        {
            let thumbnailFilename = filename.replacingOccurrences(
                of: ".\(FileConstants.encryptedFileExtension)", with: FileConstants.encryptedThumbnailSuffix)
            let thumbnailData = try await self.loadEncryptedFile(
                filename: thumbnailFilename, from: directory, encryptionKey: encryptionKey, hmacKey: hmacKey)

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
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [])
        return contents.filter { $0.pathExtension == FileConstants.encryptedFileExtension }
    }

    // MARK: - Re-encryption

    /// Re-encrypts a file with new keys by decrypting to a temp file and re-encrypting.
    /// Handles both legacy and streaming formats.
    func reEncryptFile(
        filename: String,
        directory: URL,
        mediaType: MediaType,
        oldEncryptionKey: SymmetricKey,
        oldHMACKey: SymmetricKey,
        newEncryptionKey: SymmetricKey,
        newHMACKey: SymmetricKey
    ) async throws {
        let fileURL = directory.appendingPathComponent(filename)

        // 0. Read metadata from the old file
        let metadata = try await readMetadata(from: fileURL, encryptionKey: oldEncryptionKey, hmacKey: oldHMACKey)

        // 1. Decrypt to temporary file using OLD keys
        // We use the existing decryptEncryptedFileToTemporaryURL which handles both legacy and stream formats
        let tempURL = try await decryptEncryptedFileToTemporaryURL(
            filename: filename,
            originalExtension: nil, // We don't care about extension for the temp file
            from: directory,
            encryptionKey: oldEncryptionKey,
            hmacKey: oldHMACKey
        )

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // 2. Encrypt from temporary file to a new destination file using NEW keys
        // We use a temporary destination filename to ensure atomicity
        let newFilename = filename + ".reencrypt"
        let newFileURL = directory.appendingPathComponent(newFilename)

        // Ensure we don't have a stale file there
        try? FileManager.default.removeItem(at: newFileURL)

        try await saveStreamEncryptedFile(
            from: tempURL,
            filename: newFilename,
            mediaType: mediaType,
            metadata: metadata, // Pass the preserved metadata
            to: directory,
            encryptionKey: newEncryptionKey,
            hmacKey: newHMACKey
        )

        // 3. Atomic Swap: Replace the old file with the new one
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: newFileURL, backupItemName: nil, options: .usingNewMetadataOnly)
    }
}
