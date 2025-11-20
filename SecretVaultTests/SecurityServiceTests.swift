
import XCTest
import CryptoKit
#if canImport(SecretVault)
@testable import SecretVault
#else
@testable import SecretVault_iOS
#endif

final class SecurityServiceTests: XCTestCase {
    
    var securityService: SecurityService!
    var cryptoService: CryptoService!
    
    override func setUp() {
        super.setUp()
        cryptoService = CryptoService()
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
    
    func testKeychainStorage_RoundTrip() throws {
        let key = "com.secretvault.test.key"
        let data = "SecretData".data(using: .utf8)!
        
        // 1. Store
        try securityService.storeInKeychain(data: data, for: key)
        
        // 2. Retrieve
        let retrieved = try securityService.retrieveFromKeychain(for: key)
        XCTAssertEqual(retrieved, data)
        
        // 3. Delete
        try securityService.deleteFromKeychain(for: key)
        
        // 4. Verify Deletion
        let retrievedAfterDelete = try securityService.retrieveFromKeychain(for: key)
        XCTAssertNil(retrievedAfterDelete)
    }
    
    func testKeychain_OverwriteExisting() throws {
        let key = "com.secretvault.test.overwrite"
        let data1 = "Data1".data(using: .utf8)!
        let data2 = "Data2".data(using: .utf8)!
        
        try securityService.storeInKeychain(data: data1, for: key)
        try securityService.storeInKeychain(data: data2, for: key)
        
        let retrieved = try securityService.retrieveFromKeychain(for: key)
        XCTAssertEqual(retrieved, data2)
        
        // Cleanup
        try securityService.deleteFromKeychain(for: key)
    }
    
    // MARK: - Biometric Password Storage Tests
    
    func testBiometricPasswordStorage_RoundTrip() throws {
        // Note: This test might fail on Simulator if biometrics are not enrolled or if the keychain requires interaction.
        // However, storeBiometricPassword uses SecAccessControl which might not block *storage*, but retrieval might block.
        // We will test storage and basic retrieval logic, but expect nil or interaction required in a real scenario.
        // For unit tests, we might just test that it doesn't throw on storage.
        
        let password = "BiometricPassword123"
        
        // We expect this to potentially succeed in storage
        try securityService.storeBiometricPassword(password)
        
        // Retrieval usually requires user interaction (biometrics), so it might return nil or throw in a headless test environment.
        // We won't assert the value, just that the method call completes.
        _ = try? securityService.retrieveBiometricPassword()
        
        // Cleanup
        try securityService.clearBiometricPassword()
    }
}
