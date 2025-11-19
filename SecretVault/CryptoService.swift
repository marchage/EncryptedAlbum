import CommonCrypto
import CryptoKit
import Foundation

/// Service responsible for all cryptographic operations in the vault
class CryptoService {
    private let queue = DispatchQueue(label: "com.secretvault.crypto", qos: .userInitiated)

    // MARK: - Key Derivation

    /// Derives encryption and HMAC keys from password and salt
    func deriveKeys(password: String, salt: Data) async throws -> (encryptionKey: SymmetricKey, hmacKey: SymmetricKey) {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let passwordData = password.data(using: .utf8) else {
                    continuation.resume(throwing: VaultError.keyDerivationFailed(reason: "Invalid password encoding"))
                    return
                }

                // Derive master key using PBKDF2
                var derivedKey = [UInt8](repeating: 0, count: CryptoConstants.masterKeySize)
                let saltBytes = [UInt8](salt)

                let result = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
                    saltBytes.withUnsafeBytes { saltPtr in
                        passwordData.withUnsafeBytes { passwordPtr in
                            CCKeyDerivationPBKDF(
                                CCPBKDFAlgorithm(kCCPBKDF2),
                                passwordPtr.baseAddress, passwordPtr.count,
                                saltPtr.baseAddress, saltPtr.count,
                                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                UInt32(CryptoConstants.pbkdf2Iterations),
                                derivedKeyPtr.baseAddress, derivedKeyPtr.count
                            )
                        }
                    }
                }

                guard result == kCCSuccess else {
                    continuation.resume(throwing: VaultError.keyDerivationFailed(reason: "PBKDF2 derivation failed"))
                    return
                }

                let masterKey = SymmetricKey(data: Data(derivedKey))

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
                    continuation.resume(throwing: VaultError.encryptionFailed(reason: error.localizedDescription))
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
                        continuation.resume(throwing: VaultError.decryptionFailed(reason: "Invalid nonce"))
                        return
                    }

                    // Split ciphertext and tag
                    let tagSize = 16  // AES-GCM tag is always 16 bytes
                    guard encryptedData.count >= tagSize else {
                        continuation.resume(
                            throwing: VaultError.decryptionFailed(reason: "Invalid encrypted data format"))
                        return
                    }

                    let ciphertext = encryptedData.prefix(encryptedData.count - tagSize)
                    let tag = encryptedData.suffix(tagSize)

                    let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
                    let decryptedData = try AES.GCM.open(sealedBox, using: key)
                    continuation.resume(returning: decryptedData)
                } catch {
                    continuation.resume(throwing: VaultError.decryptionFailed(reason: error.localizedDescription))
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
                    continuation.resume(throwing: VaultError.hmacVerificationFailed)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }

    // MARK: - Utility Functions

    /// Generates cryptographically secure random data
    func generateRandomData(length: Int) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var data = Data(count: length)
                let result = data.withUnsafeMutableBytes {
                    SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!)
                }

                guard result == errSecSuccess else {
                    continuation.resume(
                        throwing: VaultError.randomGenerationFailed(
                            reason: "SecRandomCopyBytes failed with code \(result)"))
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    /// Generates a random salt for key derivation
    func generateSalt() async throws -> Data {
        return try await generateRandomData(length: CryptoConstants.saltSize)
    }
}
