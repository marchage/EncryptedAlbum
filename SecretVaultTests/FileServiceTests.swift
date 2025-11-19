import XCTest
import CryptoKit
#if canImport(SecretVault)
@testable import SecretVault
#else
@testable import SecretVault_iOS
#endif

final class FileServiceTests: XCTestCase {
    var sut: FileService!
    var cryptoService: CryptoService!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        cryptoService = CryptoService()
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
