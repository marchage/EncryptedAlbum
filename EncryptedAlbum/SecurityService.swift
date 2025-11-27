import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Service responsible for security validation and health checks
class SecurityService {
    private let queue = DispatchQueue(label: "biz.front-end.encryptedalbum.security", qos: .userInitiated)
    private let queueSpecificKey = DispatchSpecificKey<Void>()
    private let cryptoService: CryptoService

    // Rate limiting
    private var lastBiometricAttempt: Date?
    private var biometricAttemptCount = 0
    private var rateLimitDelay: TimeInterval = CryptoConstants.rateLimitBaseDelay

    init(cryptoService: CryptoService) {
        self.cryptoService = cryptoService
        queue.setSpecific(key: queueSpecificKey, value: ())
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
                        continuation.resume(throwing: AlbumError.rateLimitExceeded(retryAfter: retryAfter))
                        return
                    }
                }

                // Check attempt count
                if self.biometricAttemptCount >= CryptoConstants.biometricMaxAttempts {
                    continuation.resume(
                        throwing: AlbumError.tooManyBiometricAttempts(maxAttempts: CryptoConstants.biometricMaxAttempts)
                    )
                    return
                }

                let context = LAContext()
                var error: NSError?

                guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                    if let error = error {
                        switch error.code {
                        case LAError.biometryNotAvailable.rawValue:
                            continuation.resume(throwing: AlbumError.biometricNotAvailable)
                        case LAError.biometryLockout.rawValue:
                            continuation.resume(throwing: AlbumError.biometricLockout)
                        default:
                            continuation.resume(throwing: AlbumError.biometricFailed)
                        }
                    } else {
                        continuation.resume(throwing: AlbumError.biometricNotAvailable)
                    }
                    return
                }

                self.lastBiometricAttempt = Date()
                self.biometricAttemptCount += 1

                // Introduce a short delay so the biometric sheet does not appear abruptly.
                Thread.sleep(forTimeInterval: 1.0)

                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
                    success, error in
                    if success {
                        self.resetBiometricRateLimit()
                        continuation.resume(returning: ())
                    } else if let error = error as? LAError {
                        switch error.code {
                        case .userCancel, .appCancel, .systemCancel:
                            continuation.resume(throwing: AlbumError.biometricCancelled)
                        default:
                            continuation.resume(throwing: AlbumError.biometricFailed)
                        }
                    } else {
                        continuation.resume(throwing: AlbumError.biometricFailed)
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
                        report.overallHealthy =
                            report.randomGenerationHealthy && report.cryptoOperationsHealthy && report.fileSystemSecure
                            && report.memorySecurityHealthy

                        continuation.resume(returning: report)
                    } catch {
                        continuation.resume(
                            throwing: AlbumError.securityHealthCheckFailed(reason: error.localizedDescription))
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

        return entropy / 8.0  // Normalize to 0-1 range
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
            // Skip jailbreak checks on Simulator
            #if targetEnvironment(simulator)
                return true
            #else
                let jailbreakPaths = [
                    "/Applications/Cydia.app",
                    "/Library/MobileSubstrate/MobileSubstrate.dylib",
                    "/bin/bash",
                    "/usr/sbin/sshd",
                    "/etc/apt",
                ]

                for path in jailbreakPaths {
                    if FileManager.default.fileExists(atPath: path) {
                        return false
                    }
                }
                return true
            #endif
        #else
            return true
        #endif
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

    // MARK: - Album Integrity Validation

    /// Validates the integrity of the entire album
    func validateAlbumIntegrity(
        albumURL: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey, expectedMetadata: Data?
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    // Check album directory exists
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: albumURL.path, isDirectory: &isDirectory),
                        isDirectory.boolValue
                    else {
                        continuation.resume(throwing: AlbumError.albumCorrupted(reason: "Album directory not found"))
                        return
                    }

                    // Check photos directory exists
                    let photosURL = albumURL.appendingPathComponent(FileConstants.photosDirectoryName)
                    guard FileManager.default.fileExists(atPath: photosURL.path, isDirectory: &isDirectory),
                        isDirectory.boolValue
                    else {
                        continuation.resume(throwing: AlbumError.albumCorrupted(reason: "Photos directory not found"))
                        return
                    }

                    // Validate metadata if provided
                    if let expectedMetadata = expectedMetadata {
                        try self.validateMetadataIntegrity(
                            expectedMetadata, encryptionKey: encryptionKey, hmacKey: hmacKey)
                    }

                    continuation.resume(returning: ())
                } catch let error as AlbumError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: AlbumError.integrityCheckFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    private func validateMetadataIntegrity(_ metadata: Data, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) throws
    {
        // This would validate the metadata structure and integrity
        // Implementation depends on how metadata is stored
        // For now, just check it's valid JSON
        guard (try? JSONSerialization.jsonObject(with: metadata)) != nil else {
            throw AlbumError.metadataCorrupted(reason: "Invalid JSON format")
        }
    }

    // MARK: - Keychain Operations

    /// Stores data securely in Keychain
    func storeInKeychain(data: Data, for key: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    var query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: key,
                        kSecValueData as String: data,
                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    ]

                    self.applyMacKeychainAttributes(to: &query, requireUISkip: true)

                    SecItemDelete(query as CFDictionary)

                    let status = SecItemAdd(query as CFDictionary, nil)
                    guard status == errSecSuccess else {
                        throw AlbumError.unknownError(reason: "Keychain storage failed with status \(status)")
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Retrieves data from Keychain
    func retrieveFromKeychain(for key: String) async throws -> Data? {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: key,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]

                self.applyMacKeychainAttributes(to: &query, requireUISkip: true)

                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                if status == errSecItemNotFound {
                    continuation.resume(returning: nil)
                    return
                }

                guard status == errSecSuccess, let data = result as? Data else {
                    continuation.resume(
                        throwing: AlbumError.unknownError(reason: "Keychain retrieval failed with status \(status)"))
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    /// Deletes data from Keychain
    func deleteFromKeychain(for key: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: key,
                ]

                self.applyMacKeychainAttributes(to: &query, requireUISkip: false)

                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    continuation.resume(
                        throwing: AlbumError.unknownError(reason: "Keychain deletion failed with status \(status)"))
                    return
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Biometric Password Storage

    private let biometricPasswordKey = "EncryptedAlbum.BiometricPassword"

    /// Stores the password for biometric authentication
    func storeBiometricPassword(_ password: String) async throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw AlbumError.unknownError(reason: "Failed to encode password")
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    var error: Unmanaged<CFError>?
                    guard
                        let accessControl = SecAccessControlCreateWithFlags(
                            kCFAllocatorDefault,
                            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                            .biometryAny,
                            &error
                        )
                    else {
                        let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
                        throw AlbumError.unknownError(reason: "Failed to create access control: \(errorDesc)")
                    }

                    var deleteQuery: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: self.biometricPasswordKey,
                    ]
                    #if os(macOS)
                        if self.shouldUseDataProtectionKeychain() {
                            deleteQuery[kSecUseDataProtectionKeychain as String] = true
                        }
                    #endif
                    SecItemDelete(deleteQuery as CFDictionary)

                    var addQuery: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: self.biometricPasswordKey,
                        kSecValueData as String: passwordData,
                        kSecAttrAccessControl as String: accessControl,
                    ]
                    #if os(macOS)
                        if self.shouldUseDataProtectionKeychain() {
                            addQuery[kSecUseDataProtectionKeychain as String] = true
                        }
                    #endif

                    let status = SecItemAdd(addQuery as CFDictionary, nil)

                    if status != errSecSuccess {
                        #if os(macOS)
                            var fallbackQuery = addQuery
                            fallbackQuery.removeValue(forKey: kSecAttrAccessControl as String)
                            let fallbackStatus = SecItemAdd(fallbackQuery as CFDictionary, nil)

                            guard fallbackStatus == errSecSuccess else {
                                throw AlbumError.unknownError(
                                    reason:
                                        "Keychain storage failed with status \(status) and fallback \(fallbackStatus)")
                            }
                        #else
                            throw AlbumError.unknownError(reason: "Keychain storage failed with status \(status)")
                        #endif
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Retrieves the stored biometric password
    /// This will trigger the system biometric prompt automatically due to SecAccessControl
    func retrieveBiometricPassword(prompt: String = "Authenticate to unlock Encrypted Album") async throws -> String? {
        let context = LAContext()
        context.localizedReason = prompt

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    #if os(macOS)
                        // If we are not using Data Protection Keychain, we likely used the fallback storage (no Access Control).
                        // We must manually authenticate the user to maintain security.
                        if !self.shouldUseDataProtectionKeychain() {
                            do {
                                // Authenticate user before accessing legacy keychain item
                                let success = try await context.evaluatePolicy(
                                    .deviceOwnerAuthenticationWithBiometrics, localizedReason: prompt)
                                if !success {
                                    continuation.resume(throwing: AlbumError.biometricFailed)
                                    return
                                }
                            } catch let error as LAError {
                                if error.code == .userCancel {
                                    continuation.resume(throwing: AlbumError.biometricCancelled)
                                } else {
                                    continuation.resume(throwing: AlbumError.biometricFailed)
                                }
                                return
                            } catch {
                                continuation.resume(throwing: AlbumError.biometricFailed)
                                return
                            }
                        }
                    #endif

                    var query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: self.biometricPasswordKey,
                        kSecReturnData as String: true,
                        kSecMatchLimit as String: kSecMatchLimitOne,
                        kSecUseAuthenticationContext as String: context,
                    ]
                    #if os(macOS)
                        if self.shouldUseDataProtectionKeychain() {
                            query[kSecUseDataProtectionKeychain as String] = true
                        }
                    #endif

                    var result: AnyObject?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)

                    if status == errSecItemNotFound {
                        continuation.resume(returning: nil)
                        return
                    }

                    if status == errSecUserCanceled || status == errSecAuthFailed {
                        continuation.resume(throwing: AlbumError.biometricCancelled)
                        return
                    }

                    guard status == errSecSuccess, let data = result as? Data else {
                        continuation.resume(
                            throwing: AlbumError.unknownError(
                                reason: "Keychain retrieval failed with status: \(status)"))
                        return
                    }

                    continuation.resume(returning: String(data: data, encoding: .utf8))
                }
            }
        }
    }

    /// Checks if a biometric-protected password exists without triggering user interaction
    func biometricPasswordExists() async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async {
                var query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: self.biometricPasswordKey,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecReturnData as String: false,
                    kSecReturnAttributes as String: false,
                    kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
                ]

                self.applyMacKeychainAttributes(to: &query, requireUISkip: true)

                let status = SecItemCopyMatching(query as CFDictionary, nil)
                switch status {
                case errSecSuccess, errSecInteractionNotAllowed:
                    continuation.resume(returning: true)
                case errSecItemNotFound:
                    continuation.resume(returning: false)
                default:
                    #if DEBUG
                        print("🔐 DEBUG: biometricPasswordExists query failed with status \(status)")
                    #endif
                    // Treat unknown errors as "not found" or "false" to be safe,
                    // or we could throw if we wanted to be strict, but Bool return implies simple check.
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Clears the stored biometric password
    func clearBiometricPassword() async throws {
        try await deleteFromKeychain(for: biometricPasswordKey)
    }

    #if os(macOS)
        /// Tracks whether the current process can use the Data Protection Keychain.
        private static var keychainDomainPreference: KeychainDomainPreference = .unknown
        private static let probeAccount = "EncryptedAlbum.KeychainProbe"

        private enum KeychainDomainPreference {
            case unknown
            case legacyLogin
            case dataProtection
        }

        // TODO(marchage): Remove legacy login-keychain fallback once release builds ship with the entitlement.
        private func applyMacKeychainAttributes(to query: inout [String: Any], requireUISkip: Bool) {
            if shouldUseDataProtectionKeychain() {
                query[kSecUseDataProtectionKeychain as String] = true
            } else if requireUISkip {
                query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
            }
        }

        func shouldUseDataProtectionKeychain() -> Bool {
            if #available(macOS 10.15, *) {
                switch SecurityService.keychainDomainPreference {
                case .dataProtection:
                    return true
                case .legacyLogin:
                    return false
                case .unknown:
                    break
                }

                // 1. Try to find the probe item first (Read-only check) to avoid write churn
                let probeQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: SecurityService.probeAccount,
                    kSecReturnAttributes as String: true,
                    kSecUseDataProtectionKeychain as String: true,
                ]

                var result: AnyObject?
                let status = SecItemCopyMatching(probeQuery as CFDictionary, &result)

                if status == errSecSuccess {
                    SecurityService.keychainDomainPreference = .dataProtection
                    return true
                }

                // 2. If not found, try to add it (Write check)
                if status == errSecItemNotFound {
                    guard let probeData = "probe".data(using: .utf8) else {
                        return false
                    }

                    let addQuery: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: SecurityService.probeAccount,
                        kSecValueData as String: probeData,
                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                        kSecUseDataProtectionKeychain as String: true,
                    ]

                    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

                    if addStatus == errSecSuccess {
                        // Successfully added. Keep it to speed up future checks.
                        SecurityService.keychainDomainPreference = .dataProtection
                        return true
                    }

                    if addStatus == errSecDuplicateItem {
                        // It exists (race condition or previous run), so we have access.
                        SecurityService.keychainDomainPreference = .dataProtection
                        return true
                    }

                    if addStatus == errSecMissingEntitlement {
                        SecurityService.keychainDomainPreference = .legacyLogin
                        return false
                    }

                    #if DEBUG
                        print("🔐 DEBUG: Data Protection keychain probe write failed with status \(addStatus)")
                    #endif
                    // Do NOT cache legacy preference for transient errors (e.g. lock errors)
                    return false
                }

                // 3. Read failed with error other than NotFound
                if status == errSecMissingEntitlement {
                    SecurityService.keychainDomainPreference = .legacyLogin
                    return false
                }

                #if DEBUG
                    print("🔐 DEBUG: Data Protection keychain probe read failed with status \(status)")
                #endif
                // Do NOT cache legacy preference for transient errors
                return false
            } else {
                return false
            }
        }
    #else
        private func applyMacKeychainAttributes(to query: inout [String: Any], requireUISkip: Bool) {}
    #endif

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
