import CryptoKit
import XCTest

#if canImport(EncryptedAlbum)
    @testable import EncryptedAlbum
#else
    @testable import EncryptedAlbum_iOS
#endif

final class SecurityServiceTests: XCTestCase {

    var securityService: SecurityService!
    var cryptoService: CryptoService!

    override func setUp() {
        super.setUp()
        cryptoService = CryptoService(randomProvider: TestRandomProvider())
        securityService = SecurityService(cryptoService: cryptoService)
    }

    override func tearDown() {
        securityService = nil
        cryptoService = nil
        super.tearDown()
    }

    // MARK: - Health Check Tests

    func testPerformSecurityHealthCheck_ShouldReturnHealthy() async throws {
        let report = try await securityService.performSecurityHealthCheck()

        XCTAssertTrue(report.overallHealthy, "Security health check should pass on a healthy system")
        XCTAssertTrue(report.randomGenerationHealthy, "Random generation should be healthy")
        XCTAssertTrue(report.cryptoOperationsHealthy, "Crypto operations should be healthy")
        XCTAssertTrue(report.memorySecurityHealthy, "Memory security should be healthy")
        // File system check might fail on simulator if it thinks it's jailbroken (unlikely but possible) or if paths differ, but usually passes.
        XCTAssertTrue(report.fileSystemSecure, "File system should be secure")
    }

    // MARK: - Keychain Tests

    func testKeychainStorage_RoundTrip() async throws {
        let key = "biz.front-end.encryptedalbum.test.key"
        let data = "EncryptedData".data(using: .utf8)!

        // 1. Store
        try await securityService.storeInKeychain(data: data, for: key)

        // 2. Retrieve
        let retrieved = try await securityService.retrieveFromKeychain(for: key)
        XCTAssertEqual(retrieved, data)

        // 3. Delete
        try await securityService.deleteFromKeychain(for: key)

        // 4. Verify Deletion
        let retrievedAfterDelete = try await securityService.retrieveFromKeychain(for: key)
        XCTAssertNil(retrievedAfterDelete)
    }

    func testKeychain_OverwriteExisting() async throws {
        let key = "biz.front-end.encryptedalbum.test.overwrite"
        let data1 = "Data1".data(using: .utf8)!
        let data2 = "Data2".data(using: .utf8)!

        try await securityService.storeInKeychain(data: data1, for: key)
        try await securityService.storeInKeychain(data: data2, for: key)

        let retrieved = try await securityService.retrieveFromKeychain(for: key)
        XCTAssertEqual(retrieved, data2)

        // Cleanup
        try await securityService.deleteFromKeychain(for: key)
    }

    func testDataProtectionKeychainOverride() async throws {
        // Force the UserDefaults flag OFF and make sure the code honors it
        UserDefaults.standard.set(false, forKey: "security.useDataProtectionKeychain")
        defer { UserDefaults.standard.removeObject(forKey: "security.useDataProtectionKeychain") }

        // When forced off, shouldUseDataProtectionKeychain should immediately return false
        #if os(macOS)
            XCTAssertFalse(securityService.shouldUseDataProtectionKeychain())
        #else
            // On non-macOS platforms this function does not exist / isn't relevant — nothing to assert.
            XCTAssertTrue(true)
        #endif
    }

    // MARK: - Biometric Password Storage Tests

    func testBiometricPasswordStorage_RoundTrip() async throws {
        // Note: This test might fail on Simulator if biometrics are not enrolled or if the keychain requires interaction.
        // However, storeBiometricPassword uses SecAccessControl which might not block *storage*, but retrieval might block.
        // We will test storage and basic retrieval logic, but expect nil or interaction required in a real scenario.
        // For unit tests, we might just test that it doesn't throw on storage.

        let password = "BiometricPassword123"

        // We expect this to potentially succeed in storage
        try await securityService.storeBiometricPassword(password)

        // Retrieval usually requires user interaction (biometrics), so it might return nil or throw in a headless test environment.
        // We won't assert the value, just that the method call completes.
        _ = try? await securityService.retrieveBiometricPassword()

        // Cleanup
        try await securityService.clearBiometricPassword()
    }

    func testBiometricsAreSuppressedWhenTrustedModalActive() async throws {
        // Activate trusted modal and ensure biometric calls are suppressed (no UI should be triggered)
        #if os(iOS)
            // Coordinator is @MainActor-isolated; call via MainActor to satisfy isolation rules
            await MainActor.run { UltraPrivacyCoordinator.shared.beginTrustedModal() }
            defer { Task { @MainActor in UltraPrivacyCoordinator.shared.endTrustedModal() } }
        #elseif os(macOS)
            await MainActor.run { MacPrivacyCoordinator.shared.beginTrustedModal() }
            defer { Task { @MainActor in MacPrivacyCoordinator.shared.endTrustedModal() } }
        #endif

        // Expect the authenticate call to be rejected as cancelled due to active trusted modal
        do {
            _ = try await securityService.authenticateWithBiometrics(reason: "Test")
            XCTFail("Expected authenticateWithBiometrics to throw when trusted modal is active")
        } catch let err as AlbumError {
            XCTAssertEqual(err, AlbumError.biometricCancelled)
        } catch {
            XCTFail("Unexpected error type thrown: \(error)")
        }

        // Retrieval should also be cancelled
        do {
            _ = try await securityService.retrieveBiometricPassword()
            XCTFail("Expected retrieveBiometricPassword to throw when trusted modal is active")
        } catch let err as AlbumError {
            XCTAssertEqual(err, AlbumError.biometricCancelled)
        } catch {
            XCTFail("Unexpected error type thrown: \(error)")
        }
    }
}
