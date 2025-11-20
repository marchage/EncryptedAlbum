
import XCTest
#if canImport(SecretVault)
@testable import SecretVault
#else
@testable import SecretVault_iOS
#endif

final class PasswordServiceTests: XCTestCase {
    
    var passwordService: PasswordService!
    var cryptoService: CryptoService!
    var securityService: SecurityService!
    
    override func setUp() {
        super.setUp()
        cryptoService = CryptoService()
        securityService = SecurityService(cryptoService: cryptoService)
        passwordService = PasswordService(cryptoService: cryptoService, securityService: securityService)
    }
    
    override func tearDown() {
        // Clean up any keychain items we might have created
        try? passwordService.clearPasswordCredentials()
        passwordService = nil
        securityService = nil
        cryptoService = nil
        super.tearDown()
    }
    
    // MARK: - Password Validation Tests
    
    func testValidatePassword_ValidPassword_ShouldNotThrow() {
        let validPassword = "CorrectHorseBatteryStaple123!"
        XCTAssertNoThrow(try passwordService.validatePassword(validPassword))
    }
    
    func testValidatePassword_EmptyPassword_ShouldThrowInvalid() {
        XCTAssertThrowsError(try passwordService.validatePassword("")) { error in
            XCTAssertEqual(error as? VaultError, VaultError.invalidPassword)
        }
    }
    
    func testValidatePassword_TooShort_ShouldThrowTooShort() {
        let shortPassword = "short"
        XCTAssertThrowsError(try passwordService.validatePassword(shortPassword)) { error in
            if case VaultError.passwordTooShort(let minLength) = error {
                XCTAssertEqual(minLength, 8) // Assuming 8 is the min length from constants
            } else {
                XCTFail("Expected passwordTooShort error, got \(error)")
            }
        }
    }
    
    // MARK: - Password Strength Tests
    
    func testAnalyzePasswordStrength_WeakPassword() {
        let weak = "password"
        let result = passwordService.analyzePasswordStrength(weak)
        
        // Should be weak because it's a common pattern and short-ish
        XCTAssertTrue(result.score < 5)
        XCTAssertTrue(result.feedback.contains("Avoid common patterns"))
    }
    
    func testAnalyzePasswordStrength_StrongPassword() {
        let strong = "CorrectHorseBatteryStaple123!"
        let result = passwordService.analyzePasswordStrength(strong)
        
        XCTAssertEqual(result.level, .strong)
        XCTAssertTrue(result.score >= 7)
    }
    
    // MARK: - Hashing and Verification Tests
    
    func testHashAndVerifyPassword_CorrectPassword_ShouldReturnTrue() async throws {
        let password = "TestPassword123!"
        
        // 1. Hash
        let (hash, salt) = try await passwordService.hashPassword(password)
        XCTAssertFalse(hash.isEmpty)
        XCTAssertFalse(salt.isEmpty)
        
        // 2. Verify with correct password
        let isValid = try await passwordService.verifyPassword(password, against: hash, salt: salt)
        XCTAssertTrue(isValid)
    }
    
    func testHashAndVerifyPassword_WrongPassword_ShouldReturnFalse() async throws {
        let password = "TestPassword123!"
        let wrongPassword = "WrongPassword123!"
        
        // 1. Hash
        let (hash, salt) = try await passwordService.hashPassword(password)
        
        // 2. Verify with wrong password
        let isValid = try await passwordService.verifyPassword(wrongPassword, against: hash, salt: salt)
        XCTAssertFalse(isValid)
    }
    
    func testHashAndVerifyPassword_WrongSalt_ShouldReturnFalse() async throws {
        let password = "TestPassword123!"
        
        // 1. Hash
        let (hash, _) = try await passwordService.hashPassword(password)
        
        // 2. Generate a different salt
        let wrongSalt = try await cryptoService.generateSalt()
        
        // 3. Verify
        let isValid = try await passwordService.verifyPassword(password, against: hash, salt: wrongSalt)
        XCTAssertFalse(isValid)
    }
    
    // MARK: - Storage Tests (Integration-like)
    
    func testStoreAndRetrieveCredentials() throws {
        let hash = Data(repeating: 0xAA, count: 32)
        let salt = Data(repeating: 0xBB, count: 16)
        
        // 1. Store
        try passwordService.storePasswordHash(hash, salt: salt)
        
        // 2. Retrieve
        let retrieved = try passwordService.retrievePasswordCredentials()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.hash, hash)
        XCTAssertEqual(retrieved?.salt, salt)
        
        // 3. Clear
        try passwordService.clearPasswordCredentials()
        let retrievedAfterClear = try passwordService.retrievePasswordCredentials()
        XCTAssertNil(retrievedAfterClear)
    }
}
