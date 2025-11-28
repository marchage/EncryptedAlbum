import XCTest
import CryptoKit
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#else
@testable import EncryptedAlbum_iOS
#endif

@MainActor
final class AlbumManagerTests: XCTestCase {
    var sut: AlbumManager!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        // Create a unique temp directory for each test
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        sut = AlbumManager(storage: AlbumStorage(customBaseURL: tempDir))
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
        } catch AlbumError.invalidPassword {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        XCTAssertFalse(sut.isUnlocked)
    }

    func testHidePhoto_WhenAlbumLocked_Throws() async throws {
        let password = "LockCheck123!"
        try await sut.setupPassword(password)

        let photoData = Data("Encrypted".utf8)

        do {
            try await sut.hidePhoto(
                imageData: photoData,
                filename: "locked.jpg",
                mediaType: .photo
            )
            XCTFail("Expected albumNotInitialized error")
        } catch AlbumError.albumNotInitialized {
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
        
        let photoData = "Encrypted Photo Content".data(using: .utf8)!
        try await sut.hidePhoto(
            imageData: photoData,
            filename: "encrypted.jpg",
            mediaType: .photo
        )
        
        XCTAssertEqual(sut.hiddenPhotos.count, 1)
        let photo = sut.hiddenPhotos.first!
        
        let decrypted = try await sut.decryptPhoto(photo)
        XCTAssertEqual(decrypted, photoData)
    }

    func testSuspendResumeIdleTimerUpdatesSystemIdleStateOnIOS() async throws {
        #if canImport(UIKit)
        // Ensure starting state is predictable
        UIApplication.shared.isIdleTimerDisabled = false

        // Suspend should disable system idle timer for the duration of suspension
        sut.suspendIdleTimer(reason: .importing)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled, "System idle timer should be disabled while suspended")

        // Resume should restore system idle timer state (defaults in tests to not keeping awake while unlocked)
        sut.resumeIdleTimer(reason: .importing)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "System idle timer should be re-enabled after resume when user preference is not set")
        #else
        try XCTSkipIf(true, "UIKit not available on this platform — skipping idle timer behaviour test")
        #endif
    }

    func testPerformManualCloudSyncUpdatesStatus() async throws {
        #if canImport(UIKit)
        // Make sure the setting is set so the method attempts to exercise the path
        sut.encryptedCloudSyncEnabled = true

        let success = await sut.performManualCloudSync()

        // The environment where tests run may not have iCloud available; assert the method completes
        // and lands in a final non-syncing state that is one of notAvailable/failed/idle.
        XCTAssertTrue([AlbumManager.CloudSyncStatus.idle, .failed, .notAvailable].contains(sut.cloudSyncStatus))
        if success {
            XCTAssertEqual(sut.cloudSyncStatus, .idle)
            XCTAssertNotNil(sut.lastCloudSync)
        }
        #else
        try XCTSkipIf(true, "UIKit not available on this platform — skipping manual cloud sync test")
        #endif
    }

    func testPerformQuickEncryptedCloudVerificationCompletes() async throws {
        #if canImport(UIKit)
        // Setup unlocked state required for verification
        let password = "TestPassQuick123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)

        let result = await sut.performQuickEncryptedCloudVerification()

        XCTAssertTrue([AlbumManager.CloudVerificationStatus.success, .failed, .notAvailable].contains(sut.cloudVerificationStatus))
        // If result succeeded we should have a timestamp
        if result {
            XCTAssertEqual(sut.cloudVerificationStatus, .success)
            XCTAssertNotNil(sut.lastCloudVerification)
        }
        #else
        try XCTSkipIf(true, "UIKit not available on this platform — skipping cloud verification test")
        #endif
    }

    func testLockdownBlocksManualCloudSync() async throws {
        #if canImport(UIKit)
        // Enable lockdown and attempt a manual cloud sync
        sut.lockdownModeEnabled = true
        sut.encryptedCloudSyncEnabled = true

        let success = await sut.performManualCloudSync()

        XCTAssertFalse(success)
        XCTAssertEqual(sut.cloudSyncStatus, .failed)
        #else
        try XCTSkipIf(true, "UIKit not available on this platform — skipping lockdown cloud sync test")
        #endif
    }

    func testLockdownBlocksQuickVerification() async throws {
        #if canImport(UIKit)
        let password = "VerifyLockdown123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)

        sut.lockdownModeEnabled = true
        sut.encryptedCloudSyncEnabled = true

        let result = await sut.performQuickEncryptedCloudVerification()

        XCTAssertFalse(result)
        XCTAssertEqual(sut.cloudVerificationStatus, .failed)
        #else
        try XCTSkipIf(true, "UIKit not available on this platform — skipping lockdown cloud verification test")
        #endif
    }

    func testLockdownPreventsHidePhoto() async throws {
        let password = "LockdownPhoto123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)

        // Enable lockdown
        sut.lockdownModeEnabled = true

        let photoData = "TestPhoto".data(using: .utf8)!

        do {
            try await sut.hidePhoto(imageData: photoData, filename: "blocked.jpg", mediaType: .photo)
            XCTFail("Expected operationDeniedByLockdown error")
        } catch AlbumError.operationDeniedByLockdown {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLockdownPersistedInSettings() async throws {
        let password = "PersistLockdown123!"
        try await sut.setupPassword(password)

        sut.lockdownModeEnabled = true
        sut.saveSettings()

        // Create a new manager pointing at same storage to load saved settings
        let reloaded = AlbumManager(storage: AlbumStorage(customBaseURL: tempDir))

        // Wait a bit for loadSettings task to complete
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(reloaded.lockdownModeEnabled)
    }

    func testDecoyUnlockDoesNotWipeRealAlbum() async throws {
        // 1. Setup a real album with a hidden photo
        let realPassword = "RealSecret123!"
        try await sut.setupPassword(realPassword)
        try await sut.unlock(password: realPassword)

        let realPhotoData = "REAL_PHOTO_CONTENT".data(using: .utf8)!
        try await sut.hidePhoto(imageData: realPhotoData, filename: "real.jpg", mediaType: .photo)

        XCTAssertEqual(sut.hiddenPhotos.count, 1, "There should be one real hidden photo")

        let realPhoto = sut.hiddenPhotos.first!
        let realFileURL = sut.urlForStoredPath(realPhoto.encryptedDataPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: realFileURL.path), "Real encrypted file should exist on disk")

        // 2. Enable decoy password and unlock using the decoy; ensure real data is untouched
        sut.setDecoyPassword("DecoyTest123!")
        sut.lock()

        // Unlock using decoy password - this should set isDecoyMode and not touch stored files
        try await sut.unlock(password: "DecoyTest123!")
        XCTAssertTrue(sut.isDecoyMode, "Manager should be in decoy mode after decoy unlock")

        // Hidden photos in decoy mode must be the fake collection; the real file must still exist on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: realFileURL.path), "Real encrypted file must remain on disk when in decoy mode")

        // 3. Lock and unlock with the real password, then verify we can still decrypt the original photo
        sut.lock()
        try await sut.unlock(password: realPassword)

        XCTAssertFalse(sut.isDecoyMode, "After real unlock decoy mode should be disabled")

        // Re-find the real photo (hiddenPhotos may have been reloaded)
        guard let restored = sut.hiddenPhotos.first(where: { $0.filename == realPhoto.filename }) else {
            XCTFail("Real photo metadata should still be present after returning from decoy mode")
            return
        }

        let decrypted = try await sut.decryptPhoto(restored)
        XCTAssertEqual(decrypted, realPhotoData, "Decrypted contents must match the original data")
    }

    func testUserInitiatedLockSetsSuppressFlag() async throws {
        let password = "ManualLock123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)

        // Make sure we're unlocked to begin
        XCTAssertTrue(sut.isUnlocked)

        sut.lock(userInitiated: true)

        // The flag should be set synchronously for the UI to respect it
        XCTAssertTrue(sut.suppressAutoBiometricAfterManualLock, "User-initiated lock should set suppression flag immediately")
    }

    func testClearSuppressAutoBiometricClearsFlag() async throws {
        let password = "ManualLockClear123!"
        try await sut.setupPassword(password)
        try await sut.unlock(password: password)

        sut.lock(userInitiated: true)
        XCTAssertTrue(sut.suppressAutoBiometricAfterManualLock)

        sut.clearSuppressAutoBiometric()
        // clearSuppressAutoBiometric uses main queue; tests are @MainActor so the change is immediate
        XCTAssertFalse(sut.suppressAutoBiometricAfterManualLock)
    }
}
