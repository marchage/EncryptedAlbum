import XCTest
import CryptoKit
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#else
@testable import EncryptedAlbum_iOS
#endif

final class CryptoServiceTests: XCTestCase {
    var sut: CryptoService!
    
    override func setUp() {
        super.setUp()
        sut = CryptoService(randomProvider: TestRandomProvider())
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Key Derivation Tests
    
    func testDeriveKeys_ReturnsValidKeys() async throws {
        let password = "TestPassword123!"
        let salt = try await sut.generateSalt()
        
        let (encryptionKey, hmacKey) = try await sut.deriveKeys(password: password, salt: salt)
        
        // Check key sizes (256 bits = 32 bytes)
        XCTAssertEqual(encryptionKey.bitCount, 256)
        XCTAssertEqual(hmacKey.bitCount, 256)
    }

    func testDeriveKeys_WithDataInput() async throws {
        let password = "TestPassword123!"
        let salt = try await sut.generateSalt()
        guard let pwdData = password.data(using: .utf8) else {
            XCTFail("Failed to encode password")
            return
        }

        let (encryptionKey, hmacKey) = try await sut.deriveKeys(password: pwdData, salt: salt)
        XCTAssertEqual(encryptionKey.bitCount, 256)
        XCTAssertEqual(hmacKey.bitCount, 256)
    }
    
    func testDeriveKeys_Deterministic() async throws {
        let password = "TestPassword123!"
        let salt = try await sut.generateSalt()
        
        let (key1, hmac1) = try await sut.deriveKeys(password: password, salt: salt)
        let (key2, hmac2) = try await sut.deriveKeys(password: password, salt: salt)
        
        XCTAssertEqual(key1, key2)
        XCTAssertEqual(hmac1, hmac2)
    }
    
    func testDeriveKeys_DifferentSalts_ProduceDifferentKeys() async throws {
        let password = "TestPassword123!"
        let salt1 = try await sut.generateSalt()
        let salt2 = try await sut.generateSalt()
        
        let (key1, _) = try await sut.deriveKeys(password: password, salt: salt1)
        let (key2, _) = try await sut.deriveKeys(password: password, salt: salt2)
        
        XCTAssertNotEqual(key1, key2)
    }
    
    // MARK: - Verifier Tests
    
    func testDeriveVerifier_ReturnsValidVerifier() async throws {
        let password = "TestPassword123!"
        let salt = try await sut.generateSalt()
        
        let verifier = try await sut.deriveVerifier(password: password, salt: salt)
        
        XCTAssertEqual(verifier.count, 32) // SHA-256 output size
    }
    
    func testDeriveVerifier_Deterministic() async throws {
        let password = "TestPassword123!"
        let salt = try await sut.generateSalt()
        
        let verifier1 = try await sut.deriveVerifier(password: password, salt: salt)
        let verifier2 = try await sut.deriveVerifier(password: password, salt: salt)
        
        XCTAssertEqual(verifier1, verifier2)
    }
    
    func testDeriveVerifier_DifferentFromEncryptionKey() async throws {
        let password = "TestPassword123!"
        let salt = try await sut.generateSalt()
        
        let (encryptionKey, _) = try await sut.deriveKeys(password: password, salt: salt)
        let verifier = try await sut.deriveVerifier(password: password, salt: salt)
        
        // Convert encryption key to data for comparison
        let keyData = encryptionKey.withUnsafeBytes { Data($0) }
        
        XCTAssertNotEqual(keyData, verifier)
    }
    
    // MARK: - Encryption/Decryption Tests
    
    func testEncryptDecrypt_RoundTrip_Success() async throws {
        let data = "Encrypted Message".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)
        
        let (encrypted, nonce) = try await sut.encryptData(data, key: key)
        let decrypted = try await sut.decryptData(encrypted, key: key, nonce: nonce)
        
        XCTAssertEqual(decrypted, data)
    }
    
    func testEncryptDecryptWithIntegrity_RoundTrip_Success() async throws {
        let data = "Encrypted Message with Integrity".data(using: .utf8)!
        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        
        let (encrypted, nonce, hmac) = try await sut.encryptDataWithIntegrity(
            data,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )
        
        let decrypted = try await sut.decryptDataWithIntegrity(
            encrypted,
            nonce: nonce,
            hmac: hmac,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )
        
        XCTAssertEqual(decrypted, data)
    }
    
    func testDecryptWithIntegrity_TamperedData_Fails() async throws {
        let data = "Encrypted Message".data(using: .utf8)!
        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        
        let (encrypted, nonce, hmac) = try await sut.encryptDataWithIntegrity(
            data,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )
        
        // Create a mutable copy explicitly to avoid potential issues with tuple destructuring mutation
        var tamperedEncrypted = Data(encrypted)
        
        // Tamper with encrypted data
        if !tamperedEncrypted.isEmpty {
            tamperedEncrypted[0] = tamperedEncrypted[0] ^ 0xFF
        }
        
        do {
            _ = try await sut.decryptDataWithIntegrity(
                tamperedEncrypted,
                nonce: nonce,
                hmac: hmac,
                encryptionKey: encryptionKey,
                hmacKey: hmacKey
            )
            XCTFail("Should have thrown error")
        } catch let error as AlbumError {
            // Depending on implementation, this might fail at HMAC check or Decryption
            // But since we tamper with ciphertext, HMAC check should fail first if implemented correctly
            XCTAssertEqual(error, AlbumError.hmacVerificationFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testDecryptWithIntegrity_TamperedHMAC_Fails() async throws {
        let data = "Encrypted Message".data(using: .utf8)!
        let encryptionKey = SymmetricKey(size: .bits256)
        let hmacKey = SymmetricKey(size: .bits256)
        
        let (encrypted, nonce, hmac) = try await sut.encryptDataWithIntegrity(
            data,
            encryptionKey: encryptionKey,
            hmacKey: hmacKey
        )
        
        // Create a mutable copy explicitly
        var tamperedHMAC = hmac
        
        // Tamper with HMAC
        if !tamperedHMAC.isEmpty {
            tamperedHMAC[0] ^= 0xFF
        }
        
        do {
            _ = try await sut.decryptDataWithIntegrity(
                encrypted,
                nonce: nonce,
                hmac: tamperedHMAC,
                encryptionKey: encryptionKey,
                hmacKey: hmacKey
            )
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertEqual(error as? AlbumError, AlbumError.hmacVerificationFailed)
        }
    }
}
