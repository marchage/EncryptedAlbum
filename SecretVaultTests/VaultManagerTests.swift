import XCTest
import CryptoKit
#if canImport(SecretVault)
@testable import SecretVault
#else
@testable import SecretVault_iOS
#endif

@MainActor
final class VaultManagerTests: XCTestCase {
    var sut: VaultManager!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        // Create a unique temp directory for each test
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        sut = VaultManager(storage: VaultStorage(customBaseURL: tempDir))
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }
    
    func testSetupPassword_SetsPasswordHash() async throws {
        let password = "NewPassword123!"
        try await sut.setupPassword(password)
        
        XCTAssertTrue(sut.hasPassword())
        XCTAssertFalse(sut.passwordHash.isEmpty)
        XCTAssertFalse(sut.passwordSalt.isEmpty)
        XCTAssertEqual(sut.securityVersion, 2)
    }
    
    func testUnlock_WithCorrectPassword_Unlocks() async throws {
        let password = "NewPassword123!"
        try await sut.setupPassword(password)
        
        try await sut.unlock(password: password)
        
        XCTAssertTrue(sut.isUnlocked)
    }
    
    func testUnlock_WithIncorrectPassword_Throws() async throws {
        let password = "NewPassword123!"
        try await sut.setupPassword(password)
        
        do {
            try await sut.unlock(password: "WrongPassword")
            XCTFail("Should have thrown invalidPassword")
        } catch VaultError.invalidPassword {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        XCTAssertFalse(sut.isUnlocked)
    }

    func testHidePhoto_WhenVaultLocked_Throws() async throws {
        let password = "LockCheck123!"
        try await sut.setupPassword(password)

        let photoData = Data("Secret".utf8)

        do {
            try await sut.hidePhoto(
                imageData: photoData,
                filename: "locked.jpg",
                mediaType: .photo
            )
            XCTFail("Expected vaultNotInitialized error")
        } catch VaultError.vaultNotInitialized {
            // Expected path
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testChangePassword_ReEncryptsData() async throws {
        // 1. Setup
        let oldPassword = "OldPassword123!"
        let newPassword = "NewPassword123!"
        try await sut.setupPassword(oldPassword)
        try await sut.unlock(password: oldPassword)
        
        // 2. Add a photo
        let photoData = "Photo Data".data(using: .utf8)!
        try await sut.hidePhoto(
            imageData: photoData,
            filename: "test.jpg",
            mediaType: .photo
        )
        
        let photo = sut.hiddenPhotos.first!
        
        // 3. Change Password
        try await sut.changePassword(currentPassword: oldPassword, newPassword: newPassword)
        
        // 4. Verify we can unlock with new password
        sut.lock()
        try await sut.unlock(password: newPassword)
        XCTAssertTrue(sut.isUnlocked)
        
        // 5. Verify we can decrypt the photo
        // We need to find the photo again because the list might have been reloaded or updated
        // Actually changePassword updates hiddenPhotos in place or reloads?
        // It re-encrypts files on disk. The SecurePhoto struct paths remain valid (filenames don't change, just content).
        
        let decryptedData = try await sut.decryptPhoto(photo)
        XCTAssertEqual(decryptedData, photoData)
    }
    
    func testHideAndDecryptPhoto_Success() async throws {
        let password = "Password123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)
        
        let photoData = "Secret Photo Content".data(using: .utf8)!
        try await sut.hidePhoto(
            imageData: photoData,
            filename: "secret.jpg",
            mediaType: .photo
        )
        
        XCTAssertEqual(sut.hiddenPhotos.count, 1)
        let photo = sut.hiddenPhotos.first!
        
        let decrypted = try await sut.decryptPhoto(photo)
        XCTAssertEqual(decrypted, photoData)
    }
}
