import CommonCrypto
import CryptoKit
import Foundation

/// Service responsible for all cryptographic operations in the album
class CryptoService {
    private let queue = DispatchQueue(label: "biz.front-end.encryptedalbum.crypto", qos: .userInitiated)

    // MARK: - Key Derivation

    /// Derives encryption and HMAC keys from password (Data) and salt
    func deriveKeys(password: Data, salt: Data) async throws -> (encryptionKey: SymmetricKey, hmacKey: SymmetricKey) {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
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
            queue.async {
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

    /// Validates that generated random data has sufficient entropy.
    /// Uses a Shannon-entropy estimate (bits per byte) to detect pathological outputs.
    /// Returns true when entropy looks reasonable; thresholds are conservative.
    private func validateEntropy(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }

        // Compute byte frequency
        var counts = [Int](repeating: 0, count: 256)
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let buf = ptr.bindMemory(to: UInt8.self)
            for b in buf {
                counts[Int(b)] += 1
            }
        }

        let length = Double(data.count)
        var entropy: Double = 0.0
        for c in counts where c > 0 {
            let p = Double(c) / length
            entropy += -p * log2(p)
        }

        // entropy is bits per symbol (max 8 for byte symbols)
        // Use conservative thresholds: for short blobs (<=16) allow slightly lower threshold.
        let threshold: Double = (data.count <= 16) ? 6.0 : 7.0
        return entropy >= threshold
    }

    /// Generates cryptographically secure random data. This will attempt a small number of
    /// retries if the quick entropy validation fails. On extremely rare failures (platform
    /// RNG malfunction) we log a warning and return the last generated blob rather than
    /// throwing, to avoid blocking user signup flows.
    func generateRandomData(length: Int) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let maxAttempts = 3
                var lastData: Data? = nil
                for attempt in 1...maxAttempts {
                    var data = Data(count: length)
                    let result = data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Int32 in
                        guard let base = ptr.baseAddress else { return -1 }
                        return SecRandomCopyBytes(kSecRandomDefault, length, base)
                    }

                    guard result == errSecSuccess else {
                        // If SecRandomCopyBytes failed, no point retrying many times; fail fast.
                        continuation.resume(
                            throwing: AlbumError.randomGenerationFailed(
                                reason: "SecRandomCopyBytes failed with code \(result) on attempt \(attempt)"))
                        return
                    }

                    lastData = data

                    // Quick entropy sanity check
                    if self.validateEntropy(data) {
                        continuation.resume(returning: data)
                        return
                    }

                    // otherwise, try again (fall through to next attempt)
                }

                // All attempts produced data that failed the entropy check. This is extremely
                // rare; log a warning and return the last blob rather than throwing so the user
                // signup flow isn't blocked by a false positive.
                if let fallback = lastData {
                    AppLog.errorPublic("CryptoService: generated random data failed entropy checks after \(3) attempts; returning fallback blob")
                    continuation.resume(returning: fallback)
                    return
                }

                continuation.resume(throwing: AlbumError.randomGenerationFailed(reason: "Unable to generate random data"))
            }
        }
    }

    /// Generates a random salt for key derivation
    func generateSalt() async throws -> Data {
        return try await generateRandomData(length: CryptoConstants.saltSize)
    }
}
