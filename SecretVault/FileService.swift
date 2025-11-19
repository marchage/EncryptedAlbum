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

    private struct StreamFileHeader {
        let version: UInt8
        let mediaType: MediaType
        let originalSize: UInt64
        let chunkSize: UInt32
    }

    private var streamMagicData: Data {
        Data(CryptoConstants.streamingMagic.utf8)
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
    func saveEncryptedFile(
        data: Data, filename: String, to directory: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey
    ) async throws {
        let fileURL = directory.appendingPathComponent(filename)

        // Check if file already exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            throw VaultError.fileAlreadyExists(path: fileURL.path)
        }

        // Encrypt data with integrity
        let (encryptedData, nonce, hmac) = try await self.cryptoService.encryptDataWithIntegrity(
            data, encryptionKey: encryptionKey, hmacKey: hmacKey)

        // Write encrypted data
        try encryptedData.write(to: fileURL, options: .atomic)

        // Write nonce as extended attribute
        try self.setExtendedAttribute(name: "com.secretvault.nonce", data: nonce, at: fileURL)

        // Write HMAC as extended attribute
        try self.setExtendedAttribute(name: "com.secretvault.hmac", data: hmac, at: fileURL)
    }

    /// Encrypts a file already on disk by streaming chunks to the destination file.
    func saveStreamEncryptedFile(
        from sourceURL: URL, filename: String, mediaType: MediaType, to directory: URL, encryptionKey: SymmetricKey,
        hmacKey _: SymmetricKey, progressHandler: ((Int64) async -> Void)? = nil
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

        let header = StreamFileHeader(
            version: CryptoConstants.streamingVersion,
            mediaType: mediaType,
            originalSize: fileSize.uint64Value,
            chunkSize: UInt32(CryptoConstants.streamingChunkSize)
        )

        do {
            try writeStreamHeader(header, to: writeHandle)

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

        return try await decryptLegacyFile(at: fileURL, encryptionKey: encryptionKey, hmacKey: hmacKey)
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

        let data = try await decryptLegacyFile(at: fileURL, encryptionKey: encryptionKey, hmacKey: hmacKey)
        let tempURL = makeTemporaryFileURL(preferredExtension: originalExtension)
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func decryptStreamFileDataIfNeeded(at fileURL: URL, encryptionKey: SymmetricKey) async throws -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer { try? handle.close() }

        guard let header = try readStreamHeader(from: handle) else {
            return nil
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

        try handle.write(contentsOf: data)
    }

    private func readStreamHeader(from handle: FileHandle) throws -> StreamFileHeader? {
        try handle.seek(toOffset: 0)
        guard let magicData = try handle.read(upToCount: streamMagicData.count), magicData == streamMagicData else {
            try handle.seek(toOffset: 0)
            return nil
        }

        let headerSize = 1 + 1 + 2 + 8 + 4
        guard let headerData = try handle.read(upToCount: headerSize), headerData.count == headerSize else {
            throw VaultError.fileReadFailed(path: handle.description, reason: "Incomplete stream header")
        }

        let version = headerData[0]
        let mediaByte = headerData[1]
        let mediaType: MediaType = mediaByte == 0x02 ? .video : .photo

        let originalSize: UInt64 = headerData[4..<12].withUnsafeBytes { rawBuffer in
            var value: UInt64 = 0
            memcpy(&value, rawBuffer.baseAddress!, MemoryLayout<UInt64>.size)
            return UInt64(littleEndian: value)
        }

        let chunkSize: UInt32 = headerData[12..<16].withUnsafeBytes { rawBuffer in
            var value: UInt32 = 0
            memcpy(&value, rawBuffer.baseAddress!, MemoryLayout<UInt32>.size)
            return UInt32(littleEndian: value)
        }

        return StreamFileHeader(
            version: version, mediaType: mediaType, originalSize: originalSize, chunkSize: chunkSize)
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

    private func decryptLegacyFile(at fileURL: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) async throws
        -> Data
    {
        let encryptedData = try Data(contentsOf: fileURL)

        guard let nonce = try self.getExtendedAttribute(name: "com.secretvault.nonce", at: fileURL) else {
            throw VaultError.fileReadFailed(path: fileURL.path, reason: "Missing nonce")
        }

        guard let hmac = try self.getExtendedAttribute(name: "com.secretvault.hmac", at: fileURL) else {
            throw VaultError.fileReadFailed(path: fileURL.path, reason: "Missing HMAC")
        }

        return try await self.cryptoService.decryptDataWithIntegrity(
            encryptedData, nonce: nonce, hmac: hmac, encryptionKey: encryptionKey, hmacKey: hmacKey)
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
            return nil  // Attribute doesn't exist
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
            to: directory,
            encryptionKey: newEncryptionKey,
            hmacKey: newHMACKey
        )

        // 3. Atomic Swap: Replace the old file with the new one
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: newFileURL, backupItemName: nil, options: .usingNewMetadataOnly)
    }
}
