import XCTest
import CryptoKit
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#else
@testable import EncryptedAlbum_iOS
#endif

final class FileServiceTests: XCTestCase {
    var sut: FileService!
    var cryptoService: CryptoService!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        cryptoService = CryptoService(randomProvider: TestRandomProvider())
        sut = FileService(cryptoService: cryptoService)
        
        // Create a unique temp directory for each test
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        cryptoService = nil
        super.tearDown()
    }
    
    func testStreamEncryption_RoundTrip_Success() async throws {
        // 1. Create a large-ish file (larger than chunk size ideally, but for unit test speed maybe just 5MB)
        // Chunk size is 4MB in Constants.swift
        let dataSize = 5 * 1024 * 1024 // 5MB
        let originalData = try await cryptoService.generateRandomData(length: dataSize)
        let sourceURL = tempDir.appendingPathComponent("original.dat")
        try originalData.write(to: sourceURL)
        
        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        let encryptedFilename = "encrypted.enc"
        
        // 2. Encrypt
        try await sut.saveStreamEncryptedFile(
            from: sourceURL,
            filename: encryptedFilename,
            mediaType: .photo,
            to: tempDir,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )
        
        // 3. Decrypt
        let decryptedData = try await sut.loadEncryptedFile(
            filename: encryptedFilename,
            from: tempDir,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )
        
        // 4. Verify
        XCTAssertEqual(decryptedData, originalData)
    }

    func testLoadEncryptedFileMissingCompletionMarkerThrows() async throws {
        let dataSize = 2 * 1024 * 1024
        let originalData = try await cryptoService.generateRandomData(length: dataSize)
        let sourceURL = tempDir.appendingPathComponent("original2.dat")
        try originalData.write(to: sourceURL)

        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        let encryptedFilename = "encrypted_truncated.enc"

        try await sut.saveStreamEncryptedFile(
            from: sourceURL,
            filename: encryptedFilename,
            mediaType: .photo,
            to: tempDir,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )

        let encryptedURL = tempDir.appendingPathComponent(encryptedFilename)
        var fileData = try Data(contentsOf: encryptedURL)
        let trailerBytesToRemove = MemoryLayout<UInt32>.size + CryptoConstants.streamingCompletionMarker.count
        fileData.removeLast(trailerBytesToRemove)
        try fileData.write(to: encryptedURL, options: .atomic)

        do {
            _ = try await sut.loadEncryptedFile(
                filename: encryptedFilename,
                from: tempDir,
                encryptionKey: encryptionKey,
                hmacKey: hmacKey
            )
            XCTFail("Expected loadEncryptedFile to throw")
        } catch let AlbumError.decryptionFailed(reason) {
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("completion marker"))
        } catch {
            XCTFail("Expected AlbumError.decryptionFailed, got \(error)")
        }
    }

    func testLoadEncryptedFileRejectsInvalidCompletionMarker() async throws {
        let dataSize = 1 * 1024 * 1024
        let originalData = try await cryptoService.generateRandomData(length: dataSize)
        let sourceURL = tempDir.appendingPathComponent("original_invalid_marker.dat")
        try originalData.write(to: sourceURL)

        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        let encryptedFilename = "encrypted_invalid_marker.enc"

        try await sut.saveStreamEncryptedFile(
            from: sourceURL,
            filename: encryptedFilename,
            mediaType: .photo,
            to: tempDir,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )

        let encryptedURL = tempDir.appendingPathComponent(encryptedFilename)
        var fileData = try Data(contentsOf: encryptedURL)
        let markerData = Data(CryptoConstants.streamingCompletionMarker.utf8)
        let markerStartIndex = fileData.count - markerData.count
        var corruptedMarker = Array(markerData)
        corruptedMarker[corruptedMarker.count - 1] ^= 0xFF
        fileData.replaceSubrange(markerStartIndex..<fileData.count, with: corruptedMarker)
        try fileData.write(to: encryptedURL, options: .atomic)

        do {
            _ = try await sut.loadEncryptedFile(
                filename: encryptedFilename,
                from: tempDir,
                encryptionKey: encryptionKey,
                hmacKey: hmacKey
            )
            XCTFail("Expected loadEncryptedFile to throw")
        } catch let AlbumError.decryptionFailed(reason) {
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("completion marker"))
        } catch {
            XCTFail("Expected AlbumError.decryptionFailed, got \(error)")
        }
    }

    func testLoadEncryptedFileRejectsTrailingData() async throws {
        let dataSize = 1 * 1024 * 1024
        let originalData = try await cryptoService.generateRandomData(length: dataSize)
        let sourceURL = tempDir.appendingPathComponent("original3.dat")
        try originalData.write(to: sourceURL)

        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        let encryptedFilename = "encrypted_with_trailing.enc"

        try await sut.saveStreamEncryptedFile(
            from: sourceURL,
            filename: encryptedFilename,
            mediaType: .photo,
            to: tempDir,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )

        let encryptedURL = tempDir.appendingPathComponent(encryptedFilename)
        var fileData = try Data(contentsOf: encryptedURL)
        fileData.append(contentsOf: [0xAA, 0xBB, 0xCC])
        try fileData.write(to: encryptedURL, options: .atomic)

        do {
            _ = try await sut.loadEncryptedFile(
                filename: encryptedFilename,
                from: tempDir,
                encryptionKey: encryptionKey,
                hmacKey: hmacKey
            )
            XCTFail("Expected loadEncryptedFile to throw")
        } catch let AlbumError.decryptionFailed(reason) {
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("unexpected data"))
        } catch {
            XCTFail("Expected AlbumError.decryptionFailed, got \(error)")
        }
    }

    func testSaveStreamEncryptedFileCancellationRemovesPartialFile() async throws {
        let chunkSize = CryptoConstants.streamingChunkSize
        let dataSize = (chunkSize * 2) + (chunkSize / 2)
        let originalData = Data(repeating: 0xAB, count: dataSize)
        let sourceURL = tempDir.appendingPathComponent("cancellable_source.dat")
        try originalData.write(to: sourceURL)

        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        let encryptedFilename = "encrypted_cancelled.enc"
        let destinationURL = tempDir.appendingPathComponent(encryptedFilename)

        let encryptionTask = Task {
            try await self.sut.saveStreamEncryptedFile(
                from: sourceURL,
                filename: encryptedFilename,
                mediaType: .photo,
                to: self.tempDir,
                encryptionKey: encryptionKey,
                hmacKey: hmacKey,
                progressHandler: { _ in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        encryptionTask.cancel()

        do {
            try await encryptionTask.value
            XCTFail("Expected saveStreamEncryptedFile to be cancelled")
        } catch is CancellationError {
            // Expected path
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testLoadEncryptedFileRejectsUnsupportedStreamVersion() async throws {
        let dataSize = 1 * 1024 * 1024
        let originalData = try await cryptoService.generateRandomData(length: dataSize)
        let sourceURL = tempDir.appendingPathComponent("original4.dat")
        try originalData.write(to: sourceURL)

        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        let encryptedFilename = "encrypted_legacy.enc"

        try await sut.saveStreamEncryptedFile(
            from: sourceURL,
            filename: encryptedFilename,
            mediaType: .photo,
            to: tempDir,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )

        let encryptedURL = tempDir.appendingPathComponent(encryptedFilename)
        var fileData = try Data(contentsOf: encryptedURL)
        let versionIndex = CryptoConstants.streamingMagic.count
        fileData[versionIndex] = 0x02
        try fileData.write(to: encryptedURL, options: .atomic)

        do {
            _ = try await sut.loadEncryptedFile(
                filename: encryptedFilename,
                from: tempDir,
                encryptionKey: encryptionKey,
                hmacKey: hmacKey
            )
            XCTFail("Expected loadEncryptedFile to throw")
        } catch let AlbumError.invalidFileFormat(reason) {
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("unsupported stream version"))
        } catch {
            XCTFail("Expected AlbumError.invalidFileFormat, got \(error)")
        }
    }
    
    func testReEncryptFile_Success() async throws {
        // 1. Setup initial file
        let data = "Sensitive Data".data(using: .utf8)!
        let sourceURL = tempDir.appendingPathComponent("source.dat")
        try data.write(to: sourceURL)
        
        let oldEncKey = SymmetricKey(size: .bits256)
        let oldHmacKey = SymmetricKey(size: .bits256)
        let newEncKey = SymmetricKey(size: .bits256)
        let newHmacKey = SymmetricKey(size: .bits256)
        
        let filename = "test_reencrypt.enc"
        
        // 2. Encrypt with OLD keys
        try await sut.saveStreamEncryptedFile(
            from: sourceURL,
            filename: filename,
            mediaType: .photo,
            to: tempDir,
            encryptionKey: oldEncKey,
            hmacKey: oldHmacKey
        )
        
        // 3. Re-encrypt
        try await sut.reEncryptFile(
            filename: filename,
            directory: tempDir,
            mediaType: .photo,
            oldEncryptionKey: oldEncKey,
            oldHMACKey: oldHmacKey,
            newEncryptionKey: newEncKey,
            newHMACKey: newHmacKey
        )
        
        // 4. Verify we can decrypt with NEW keys
        let decryptedData = try await sut.loadEncryptedFile(
            filename: filename,
            from: tempDir,
            encryptionKey: newEncKey,
            hmacKey: newHmacKey
        )
        
        XCTAssertEqual(decryptedData, data)
        
        // 5. Verify we CANNOT decrypt with OLD keys (should fail or produce garbage/error)
        do {
            _ = try await sut.loadEncryptedFile(
                filename: filename,
                from: tempDir,
                encryptionKey: oldEncKey,
                hmacKey: oldHmacKey
            )
            // Note: It might not throw if the format is valid but the key is wrong, 
            // it will just fail GCM authentication (decryptionFailed)
            XCTFail("Should not be able to decrypt with old keys")
        } catch {
            // Expected failure
        }
    }
    
    func testSecureDelete_RemovesFile() async throws {
        let data = "Delete Me".data(using: .utf8)!
        let url = tempDir.appendingPathComponent("todelete.dat")
        try data.write(to: url)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        
        try await sut.secureDeleteFile(at: url)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
