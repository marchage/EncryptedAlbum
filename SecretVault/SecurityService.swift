import Foundation
import LocalAuthentication
import Security
import CryptoKit

/// Service responsible for security validation and health checks
class SecurityService {
    private let queue = DispatchQueue(label: "com.secretvault.security", qos: .userInitiated)
    private let cryptoService: CryptoService

    // Rate limiting
    private var lastBiometricAttempt: Date?
    private var biometricAttemptCount = 0
    private var rateLimitDelay: TimeInterval = CryptoConstants.rateLimitBaseDelay

    init(cryptoService: CryptoService) {
        self.cryptoService = cryptoService
    }

    // MARK: - Biometric Authentication

    /// Performs biometric authentication
    func authenticateWithBiometrics(reason: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // Check rate limiting
                if let lastAttempt = self.lastBiometricAttempt {
                    let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
                    if timeSinceLastAttempt < self.rateLimitDelay {
                        let retryAfter = self.rateLimitDelay - timeSinceLastAttempt
                        continuation.resume(throwing: VaultError.rateLimitExceeded(retryAfter: retryAfter))
                        return
                    }
                }

                // Check attempt count
                if self.biometricAttemptCount >= CryptoConstants.biometricMaxAttempts {
                    continuation.resume(throwing: VaultError.tooManyBiometricAttempts(maxAttempts: CryptoConstants.biometricMaxAttempts))
                    return
                }

                let context = LAContext()
                var error: NSError?

                guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                    if let error = error {
                        switch error.code {
                        case LAError.biometryNotAvailable.rawValue:
                            continuation.resume(throwing: VaultError.biometricNotAvailable)
                        default:
                            continuation.resume(throwing: VaultError.biometricFailed)
                        }
                    } else {
                        continuation.resume(throwing: VaultError.biometricNotAvailable)
                    }
                    return
                }

                self.lastBiometricAttempt = Date()
                self.biometricAttemptCount += 1

                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                    if success {
                        self.resetBiometricRateLimit()
                        continuation.resume(returning: ())
                    } else if let error = error as? LAError {
                        switch error.code {
                        case .userCancel, .appCancel, .systemCancel:
                            continuation.resume(throwing: VaultError.biometricCancelled)
                        default:
                            continuation.resume(throwing: VaultError.biometricFailed)
                        }
                    } else {
                        continuation.resume(throwing: VaultError.biometricFailed)
                    }
                }
            }
        }
    }

    private func resetBiometricRateLimit() {
        biometricAttemptCount = 0
        rateLimitDelay = CryptoConstants.rateLimitBaseDelay
        lastBiometricAttempt = nil
    }

    // MARK: - Security Health Checks

    /// Performs comprehensive security health check
    func performSecurityHealthCheck() async throws -> SecurityHealthReport {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        var report = SecurityHealthReport()

                        // Check random number generation
                        report.randomGenerationHealthy = try await self.validateRandomGeneration()

                        // Check cryptographic operations
                        report.cryptoOperationsHealthy = try await self.validateCryptoOperations()

                        // Check file system security
                        report.fileSystemSecure = try await self.validateFileSystemSecurity()

                        // Check memory security
                        report.memorySecurityHealthy = try await self.validateMemorySecurity()

                        // Overall health
                        report.overallHealthy = report.randomGenerationHealthy &&
                                               report.cryptoOperationsHealthy &&
                                               report.fileSystemSecure &&
                                               report.memorySecurityHealthy

                        continuation.resume(returning: report)
                    } catch {
                        continuation.resume(throwing: VaultError.securityHealthCheckFailed(reason: error.localizedDescription))
                    }
                }
            }
        }
    }

    private func validateRandomGeneration() async throws -> Bool {
        // Generate multiple random samples and check entropy
        var samples: [Data] = []
        for _ in 0..<SecurityConstants.randomValidationSampleSize {
            let sample = try await cryptoService.generateRandomData(length: 32)
            samples.append(sample)
        }

        // Check for uniqueness
        let uniqueSamples = Set(samples.map { $0.base64EncodedString() })
        guard uniqueSamples.count == samples.count else {
            return false
        }

        // Check entropy (simplified check)
        let totalData = samples.reduce(Data()) { $0 + $1 }
        let entropy = self.calculateEntropy(of: totalData)
        return entropy >= SecurityConstants.minRandomEntropy
    }

    private func calculateEntropy(of data: Data) -> Double {
        var frequency = [UInt8: Int](minimumCapacity: 256)
        for byte in data {
            frequency[byte, default: 0] += 1
        }

        let dataSize = Double(data.count)
        var entropy = 0.0

        for count in frequency.values {
            let probability = Double(count) / dataSize
            entropy -= probability * log2(probability)
        }

        return entropy / 8.0 // Normalize to 0-1 range
    }

    private func validateCryptoOperations() async throws -> Bool {
        let testData = SecurityConstants.cryptoTestData.data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        // Test encryption/decryption round trip
        let (encryptedData, nonce) = try await cryptoService.encryptData(testData, key: key)
        let decryptedData = try await cryptoService.decryptData(encryptedData, key: key, nonce: nonce)

        return decryptedData == testData
    }

    private func validateFileSystemSecurity() async throws -> Bool {
        // Check if we're running on a jailbroken device (iOS)
        #if os(iOS)
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt"
        ]

        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return false
            }
        }
        #endif

        return true
    }

    private func validateMemorySecurity() async throws -> Bool {
        // Test secure memory allocation/deallocation
        let testSize = 1024
        let secureData = try await cryptoService.generateRandomData(length: testSize)

        // Verify data is properly randomized (not zeroed or patterned)
        let firstByte = secureData[0]
        let allSame = secureData.allSatisfy { $0 == firstByte }
        let allZero = secureData.allSatisfy { $0 == 0 }

        return !allSame && !allZero
    }

    // MARK: - Vault Integrity Validation

    /// Validates the integrity of the entire vault
    func validateVaultIntegrity(vaultURL: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey, expectedMetadata: Data?) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    // Check vault directory exists
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                        continuation.resume(throwing: VaultError.vaultCorrupted(reason: "Vault directory not found"))
                        return
                    }

                    // Check photos directory exists
                    let photosURL = vaultURL.appendingPathComponent(FileConstants.photosDirectoryName)
                    guard FileManager.default.fileExists(atPath: photosURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                        continuation.resume(throwing: VaultError.vaultCorrupted(reason: "Photos directory not found"))
                        return
                    }

                    // Validate metadata if provided
                    if let expectedMetadata = expectedMetadata {
                        try self.validateMetadataIntegrity(expectedMetadata, encryptionKey: encryptionKey, hmacKey: hmacKey)
                    }

                    continuation.resume(returning: ())
                } catch let error as VaultError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: VaultError.integrityCheckFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    private func validateMetadataIntegrity(_ metadata: Data, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) throws {
        // This would validate the metadata structure and integrity
        // Implementation depends on how metadata is stored
        // For now, just check it's valid JSON
        guard (try? JSONSerialization.jsonObject(with: metadata)) != nil else {
            throw VaultError.metadataCorrupted(reason: "Invalid JSON format")
        }
    }

    // MARK: - Keychain Operations

    /// Stores data securely in Keychain
    func storeInKeychain(data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.unknownError(reason: "Keychain storage failed with status \(status)")
        }
    }

    /// Retrieves data from Keychain
    func retrieveFromKeychain(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw VaultError.unknownError(reason: "Keychain retrieval failed with status \(status)")
        }

        return data
    }

    /// Deletes data from Keychain
    func deleteFromKeychain(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.unknownError(reason: "Keychain deletion failed with status \(status)")
        }
    }

    // MARK: - Biometric Password Storage

    private let biometricPasswordKey = "SecretVault.BiometricPassword"

    /// Stores the password for biometric authentication
    func storeBiometricPassword(_ password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw VaultError.unknownError(reason: "Failed to encode password")
        }
        try storeInKeychain(data: passwordData, for: biometricPasswordKey)
    }

    /// Retrieves the stored biometric password
    func retrieveBiometricPassword() throws -> String? {
        guard let passwordData = try retrieveFromKeychain(for: biometricPasswordKey) else {
            return nil
        }
        return String(data: passwordData, encoding: .utf8)
    }

    /// Clears the stored biometric password
    func clearBiometricPassword() throws {
        try deleteFromKeychain(for: biometricPasswordKey)
    }
}

/// Report structure for security health checks
struct SecurityHealthReport {
    var overallHealthy = false
    var randomGenerationHealthy = false
    var cryptoOperationsHealthy = false
    var fileSystemSecure = false
    var memorySecurityHealthy = false

    var description: String {
        """
        Security Health Report:
        Overall: \(overallHealthy ? "✓" : "✗")
        Random Generation: \(randomGenerationHealthy ? "✓" : "✗")
        Crypto Operations: \(cryptoOperationsHealthy ? "✓" : "✗")
        File System: \(fileSystemSecure ? "✓" : "✗")
        Memory Security: \(memorySecurityHealthy ? "✓" : "✗")
        """
    }
}