import CommonCrypto
import CryptoKit
import Foundation

/// Service responsible for all cryptographic operations in the album
protocol RandomProvider {
    /// Generate `count` random bytes. Implementations must provide cryptographically secure random data in production.
    func randomBytes(count: Int) async throws -> Data
}

struct SystemRandomProvider: RandomProvider {
    func randomBytes(count: Int) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            var data = Data(count: count)
            let result = data.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
            }

            if result == errSecSuccess {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: AlbumError.randomGenerationFailed(reason: "SecRandomCopyBytes failed with code \(result)"))
            }
        }
    }
}

class CryptoService {
    private let randomProvider: RandomProvider
    private let queue = DispatchQueue(label: "biz.front-end.encryptedalbum.crypto", qos: .userInitiated)

    // MARK: - Key Derivation

    /// Derives encryption and HMAC keys from password (Data) and salt
    func deriveKeys(password: Data, salt: Data) async throws -> (encryptionKey: SymmetricKey, hmacKey: SymmetricKey) {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                // Ensure the service hasn't been deallocated while the work is enqueued.
                // We don't need a local `self` binding here; just verify presence.
                guard self != nil else {
                    continuation.resume(
                        throwing: AlbumError.randomGenerationFailed(reason: "CryptoService deallocated while generating random data")
                    )
                    return
                }
                // Derive master key using PBKDF2
                guard let derivedKeyBuffer = SecureMemory.allocateSecureBuffer(count: CryptoConstants.masterKeySize)
                else {
                    continuation.resume(throwing: AlbumError.keyDerivationFailed(reason: "Memory allocation failed"))
                    return
                }
                defer { SecureMemory.deallocateSecureBuffer(derivedKeyBuffer) }

                let saltBytes = [UInt8](salt)

                let result = saltBytes.withUnsafeBytes { saltPtr in
                    password.withUnsafeBytes { passwordPtr in
                        CCKeyDerivationPBKDF(
                            CCPBKDFAlgorithm(kCCPBKDF2),
                            passwordPtr.baseAddress, passwordPtr.count,
                            saltPtr.baseAddress, saltPtr.count,
                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                            UInt32(CryptoConstants.pbkdf2Iterations),
                            derivedKeyBuffer.baseAddress, derivedKeyBuffer.count
                        )
                    }
                }

                guard result == kCCSuccess else {
                    continuation.resume(throwing: AlbumError.keyDerivationFailed(reason: "PBKDF2 derivation failed"))
                    return
                }

                let masterKey = SymmetricKey(
                    data: Data(bytes: derivedKeyBuffer.baseAddress!, count: derivedKeyBuffer.count))

                // Derive encryption and HMAC keys using HKDF
                let encryptionKey = HKDF<SHA256>.deriveKey(
                    inputKeyMaterial: masterKey,
                    salt: salt,
                    info: Data(CryptoConstants.hkdfInfoEncryption.utf8),
                    outputByteCount: CryptoConstants.encryptionKeySize
                )

                let hmacKey = HKDF<SHA256>.deriveKey(
                    inputKeyMaterial: masterKey,
                    salt: salt,
                    info: Data(CryptoConstants.hkdfInfoHMAC.utf8),
                    outputByteCount: CryptoConstants.hmacKeySize
                )

                continuation.resume(returning: (encryptionKey, hmacKey))
            }
        }
    }

    /// Convenience wrapper for callers that still pass a String; this converts to Data and calls the secure implementation.
    func deriveKeys(password: String, salt: Data) async throws -> (encryptionKey: SymmetricKey, hmacKey: SymmetricKey) {
        guard let data = password.data(using: .utf8) else {
            throw AlbumError.keyDerivationFailed(reason: "Invalid password encoding")
        }
        return try await deriveKeys(password: data, salt: salt)
    }

    // MARK: - Verifier Derivation

    /// Derives a password verifier for secure storage (separate from encryption keys)
    func deriveVerifier(password: Data, salt: Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                // Make sure the service hasn't been deallocated while the work is enqueued.
                // No local binding is required since this closure doesn't use `self`.
                guard self != nil else {
                    continuation.resume(
                        throwing: AlbumError.randomGenerationFailed(reason: "CryptoService deallocated while generating random data")
                    )
                    return
                }
                // Derive master key using PBKDF2 (Same as deriveKeys)
                guard let derivedKeyBuffer = SecureMemory.allocateSecureBuffer(count: CryptoConstants.masterKeySize)
                else {
                    continuation.resume(throwing: AlbumError.keyDerivationFailed(reason: "Memory allocation failed"))
                    return
                }
                defer { SecureMemory.deallocateSecureBuffer(derivedKeyBuffer) }

                let saltBytes = [UInt8](salt)

                let result = saltBytes.withUnsafeBytes { saltPtr in
                    password.withUnsafeBytes { passwordPtr in
                        CCKeyDerivationPBKDF(
                            CCPBKDFAlgorithm(kCCPBKDF2),
                            passwordPtr.baseAddress, passwordPtr.count,
                            saltPtr.baseAddress, saltPtr.count,
                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                            UInt32(CryptoConstants.pbkdf2Iterations),
                            derivedKeyBuffer.baseAddress, derivedKeyBuffer.count
                        )
                    }
                }

                guard result == kCCSuccess else {
                    continuation.resume(throwing: AlbumError.keyDerivationFailed(reason: "PBKDF2 derivation failed"))
                    return
                }

                let masterKey = SymmetricKey(
                    data: Data(bytes: derivedKeyBuffer.baseAddress!, count: derivedKeyBuffer.count))

                // Derive verifier using HKDF
                let verifierKey = HKDF<SHA256>.deriveKey(
                    inputKeyMaterial: masterKey,
                    salt: salt,
                    info: Data(CryptoConstants.hkdfInfoVerifier.utf8),
                    outputByteCount: 32
                )

                let verifier = verifierKey.withUnsafeBytes { Data($0) }
                continuation.resume(returning: verifier)
            }
        }
    }

    /// Convenience wrapper for callers that still pass a String; this converts to Data and calls the secure implementation.
    func deriveVerifier(password: String, salt: Data) async throws -> Data {
        guard let data = password.data(using: .utf8) else {
            throw AlbumError.keyDerivationFailed(reason: "Invalid password encoding")
        }
        return try await deriveVerifier(password: data, salt: salt)
    }

    // MARK: - Encryption

    /// Encrypts data using AES-GCM
    func encryptData(_ data: Data, key: SymmetricKey) async throws -> (encryptedData: Data, nonce: Data) {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let nonce = AES.GCM.Nonce()
                    let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
                    let encryptedData = sealedBox.ciphertext + sealedBox.tag
                    continuation.resume(returning: (encryptedData, Data(nonce)))
                } catch {
                    continuation.resume(throwing: AlbumError.encryptionFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    /// Encrypts data with HMAC for integrity verification
    func encryptDataWithIntegrity(_ data: Data, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) async throws -> (
        encryptedData: Data, nonce: Data, hmac: Data
    ) {
        let (encryptedData, nonce) = try await encryptData(data, key: encryptionKey)
        let hmac = await generateHMAC(for: encryptedData, key: hmacKey)
        return (encryptedData, nonce, hmac)
    }

    // MARK: - Decryption

    /// Decrypts data using AES-GCM
    func decryptData(_ encryptedData: Data, key: SymmetricKey, nonce: Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let nonce = try? AES.GCM.Nonce(data: nonce) else {
                        continuation.resume(throwing: AlbumError.decryptionFailed(reason: "Invalid nonce"))
                        return
                    }

                    // Split ciphertext and tag
                    let tagSize = 16  // AES-GCM tag is always 16 bytes
                    guard encryptedData.count >= tagSize else {
                        continuation.resume(
                            throwing: AlbumError.decryptionFailed(reason: "Invalid encrypted data format"))
                        return
                    }

                    let ciphertext = encryptedData.prefix(encryptedData.count - tagSize)
                    let tag = encryptedData.suffix(tagSize)

                    let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
                    let decryptedData = try AES.GCM.open(sealedBox, using: key)
                    continuation.resume(returning: decryptedData)
                } catch {
                    continuation.resume(throwing: AlbumError.decryptionFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    /// Decrypts data and verifies HMAC integrity
    func decryptDataWithIntegrity(
        _ encryptedData: Data, nonce: Data, hmac: Data, encryptionKey: SymmetricKey, hmacKey: SymmetricKey
    ) async throws -> Data {
        // First verify HMAC
        try await verifyHMAC(hmac, for: encryptedData, key: hmacKey)

        // Then decrypt
        return try await decryptData(encryptedData, key: encryptionKey, nonce: nonce)
    }

    // MARK: - HMAC Operations

    /// Generates HMAC for data integrity verification
    func generateHMAC(for data: Data, key: SymmetricKey) async -> Data {
        return await withCheckedContinuation { continuation in
            queue.async {
                let hmac = HMAC<SHA256>.authenticationCode(for: data, using: key)
                continuation.resume(returning: Data(hmac))
            }
        }
    }

    /// Verifies HMAC for data integrity
    func verifyHMAC(_ hmac: Data, for data: Data, key: SymmetricKey) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let expectedHMAC = Data(HMAC<SHA256>.authenticationCode(for: data, using: key))

                guard hmac == expectedHMAC else {
                    continuation.resume(throwing: AlbumError.hmacVerificationFailed)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }

    // MARK: - Utility Functions

    /// Validates that generated random data has sufficient entropy
    fileprivate func validateEntropy(_ data: Data) -> Bool {
        // Check 1: Not all zeros
        guard !data.allSatisfy({ $0 == 0 }) else { return false }

        // Check 2: Not all same byte
        let firstByte = data.first ?? 0
        guard !data.allSatisfy({ $0 == firstByte }) else { return false }

        // Check 3: Unique byte distribution
        // For small samples we expect many unique bytes (at least ~50% unique). For large buffers
        // (e.g. megabyte-sized payloads) it's impossible to have >50% unique bytes because a
        // byte only has 256 distinct values. Be pragmatic: for very large buffers we only
        // require a modest variety of unique bytes which is sufficient to detect trivial
        // all-zero/constant patterns while avoiding false negatives on large payloads.
        let uniqueBytes = Set(data)
        if data.count <= 512 {
            // Small samples should have at least 50% unique values
            guard uniqueBytes.count >= max(4, data.count / 2) else { return false }
        } else {
            // For larger samples require at least a small set of unique values (e.g. 16)
            // — this avoids failing on large ephemeral buffers while still catching broken RNGs.
            guard uniqueBytes.count >= 16 else { return false }
        }

        return true
    }

    /// Generates cryptographically secure random data
    init(randomProvider: RandomProvider = SystemRandomProvider()) {
        self.randomProvider = randomProvider
    }

    func generateRandomData(length: Int) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        // Acquire random bytes from the provider
                        var data = try await self.randomProvider.randomBytes(count: length)

                        // Validate entropy quickly (basic checks). If entropy checks fail unexpectedly
                        // (very rare), retry a few times before giving up to avoid flaky unit tests.
                        let maxAttempts = CryptoConstants.randomGenerationMaxRetries
                        var attempt = 1
                        while !self.validateEntropy(data) {
                            if attempt >= maxAttempts {
                                continuation.resume(
                                    throwing: AlbumError.randomGenerationFailed(reason: "Generated data failed entropy validation"))
                                return
                            }

                            attempt += 1
                            data = try await self.randomProvider.randomBytes(count: length)
                        }

                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

     /// Generates a random salt for key derivation
     func generateSalt() async throws -> Data {
         return try await generateRandomData(length: CryptoConstants.saltSize)
     }
 }
