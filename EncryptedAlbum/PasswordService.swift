import CryptoKit
import Foundation

/// Service responsible for password management and validation
class PasswordService {
    private let queue = DispatchQueue(label: "biz.front-end.encryptedalbum.password", qos: .userInitiated)
    private let cryptoService: CryptoService
    private let securityService: SecurityService

    init(cryptoService: CryptoService, securityService: SecurityService) {
        self.cryptoService = cryptoService
        self.securityService = securityService
    }

    // MARK: - Password Validation

    /// Validates password strength and requirements
    func validatePassword(_ password: String) throws {
        let normalized = PasswordService.normalizePassword(password)

        guard !normalized.isEmpty else {
            throw AlbumError.invalidPassword
        }
        if normalized.count < CryptoConstants.minPasswordLength {
            throw AlbumError.passwordTooShort(minLength: CryptoConstants.minPasswordLength)
        }
        if normalized.count > CryptoConstants.maxPasswordLength {
            throw AlbumError.passwordTooLong(maxLength: CryptoConstants.maxPasswordLength)
        }

        // Additional strength checks could be added here
        // - Check for common passwords
        // - Check for dictionary words
        // - Check for repeated characters
        // - Check for sequential characters
    }

    // MARK: - Password Hashing

    /// Hashes a password with salt for storage
    func hashPassword(_ password: String) async throws -> (hash: Data, salt: Data) {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        let salt = try await self.cryptoService.generateSalt()
                        // Use the dedicated verifier derivation
                        let normalized = PasswordService.normalizePassword(password)
                        let verifier = try await self.cryptoService.deriveVerifier(password: normalized, salt: salt)
                        continuation.resume(returning: (verifier, salt))
                    } catch {
                        continuation.resume(
                            throwing: AlbumError.keyDerivationFailed(reason: error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Verifies a password against a stored hash (Verifier)
    func verifyPassword(_ password: String, against hash: Data, salt: Data) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        let normalized = PasswordService.normalizePassword(password)
                        let computedVerifier = try await self.cryptoService.deriveVerifier(
                            password: normalized, salt: salt)
                        continuation.resume(returning: computedVerifier == hash)
                    } catch {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    /// Verifies a password against a stored legacy hash (Encryption Key)
    /// Used for migration from V1 to V2 security
    func verifyLegacyPassword(_ password: String, against storedKey: Data, salt: Data) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        let normalized = PasswordService.normalizePassword(password)
                        let (computedKey, _) = try await self.cryptoService.deriveKeys(password: normalized, salt: salt)
                        let computedKeyData = computedKey.withUnsafeBytes { Data($0) }
                        continuation.resume(returning: computedKeyData == storedKey)
                    } catch {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    // MARK: - Password Storage

    private let passwordHashKey = "biz.front-end.encryptedalbum.passwordHash"
    private let passwordSaltKey = "biz.front-end.encryptedalbum.passwordSalt"

    /// Stores password hash and salt securely
    func storePasswordHash(_ hash: Data, salt: Data) async throws {
        try await securityService.storeInKeychain(data: hash, for: passwordHashKey)
        try await securityService.storeInKeychain(data: salt, for: passwordSaltKey)
    }

    /// Retrieves stored password hash and salt
    func retrievePasswordCredentials() async throws -> (hash: Data, salt: Data)? {
        guard let hash = try await securityService.retrieveFromKeychain(for: passwordHashKey),
            let salt = try await securityService.retrieveFromKeychain(for: passwordSaltKey)
        else {
            return nil
        }
        return (hash, salt)
    }

    /// Clears stored password credentials
    func clearPasswordCredentials() async throws {
        try await securityService.deleteFromKeychain(for: passwordHashKey)
        try await securityService.deleteFromKeychain(for: passwordSaltKey)
    }

    // MARK: - Password Change

    /// Changes the album password
    func changePassword(
        from oldPassword: String, to newPassword: String, albumURL: URL, encryptionKey: SymmetricKey,
        hmacKey: SymmetricKey
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        // Validate new password
                            // 1. Validate new password (normalization handled inside validatePassword)
                            try self.validatePassword(newPassword)

                        // Verify old password
                        guard let (storedHash, storedSalt) = try await self.retrievePasswordCredentials() else {
                            continuation.resume(throwing: AlbumError.albumNotInitialized)
                            return
                        }

                        let oldPasswordValid = try await self.verifyPassword(
                            oldPassword, against: storedHash, salt: storedSalt)
                        guard oldPasswordValid else {
                            continuation.resume(throwing: AlbumError.invalidPassword)
                            return
                        }

                        // Generate new hash and salt for new password
                            let (newHash, newSalt) = try await self.hashPassword(newPassword)

                        // Store new credentials
                        try await self.storePasswordHash(newHash, salt: newSalt)

                        // TODO: Re-encrypt all album contents with new keys derived from new password
                        // This would require:
                        // 1. Deriving new encryption/HMAC keys from new password
                        // 2. Reading all encrypted files
                        // 3. Re-encrypting with new keys
                        // 4. Updating metadata
                        // This is a complex operation that should be done carefully

                        continuation.resume(returning: ())
                    } catch let error as AlbumError {
                        continuation.resume(throwing: error)
                    } catch {
                        continuation.resume(throwing: AlbumError.unknownError(reason: error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Password Change Preparation

    /// Prepares for a password change by verifying the old password and generating new keys/verifier.
    /// Does NOT store anything. This allows the caller (AlbumManager) to re-encrypt data before committing the change.
    func preparePasswordChange(currentPassword: String, newPassword: String) async throws -> (
        newVerifier: Data, newSalt: Data, newEncryptionKey: SymmetricKey, newHMACKey: SymmetricKey
    ) {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        // 1. Validate new password strength/rules
                        try self.validatePassword(newPassword)

                        // 2. Verify old password
                        guard let (storedHash, storedSalt) = try await self.retrievePasswordCredentials() else {
                            continuation.resume(throwing: AlbumError.albumNotInitialized)
                            return
                        }

                        // We need to handle both V1 and V2 verification here to be safe,
                        // though AlbumManager should have migrated us to V2 on unlock.
                        // Assuming V2 for simplicity as migration is enforced on unlock.
                        let oldPasswordValid = try await self.verifyPassword(
                            currentPassword, against: storedHash, salt: storedSalt)

                        guard oldPasswordValid else {
                            continuation.resume(throwing: AlbumError.invalidPassword)
                            return
                        }

                        // 3. Generate new salt and keys
                        let newSalt = try await self.cryptoService.generateSalt()
                        let normalizedNew = PasswordService.normalizePassword(newPassword)
                        let newVerifier = try await self.cryptoService.deriveVerifier(
                            password: normalizedNew, salt: newSalt)
                        let (newEncryptionKey, newHMACKey) = try await self.cryptoService.deriveKeys(
                            password: normalizedNew, salt: newSalt)

                        continuation.resume(returning: (newVerifier, newSalt, newEncryptionKey, newHMACKey))
                    } catch let error as AlbumError {
                        continuation.resume(throwing: error)
                    } catch {
                        continuation.resume(throwing: AlbumError.unknownError(reason: error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Password Strength Analysis

    /// Normalize incoming password for consistent handling (use NFKC / compatibility mapping)
    /// This reduces surprises caused by differently composed Unicode characters.
    static func normalizePassword(_ password: String) -> String {
        let ns = password as NSString
        return ns.precomposedStringWithCompatibilityMapping
    }

    /// Analyzes password strength and provides feedback
    func analyzePasswordStrength(_ password: String) -> PasswordStrength {
        var score = 0
        var feedback: [String] = []

        let normalized = PasswordService.normalizePassword(password)

        // Length check
        if normalized.count >= 20 {
            score += 8
        } else if password.count >= 16 {
            score += 5
        } else if password.count >= 12 {
            score += 3
        } else if password.count >= 8 {
            score += 1
        } else {
            feedback.append("Use at least 8 characters")
        }

        // Character variety
        let hasLowercase = normalized.contains { $0.isLowercase }
        let hasUppercase = normalized.contains { $0.isUppercase }
        let hasDigits = normalized.contains { $0.isNumber }
        // Treat *any* Unicode punctuation or symbol as a special character for strength scoring.
        let specialSet = CharacterSet.punctuationCharacters.union(.symbols)
        let hasSpecialChars = normalized.unicodeScalars.contains { specialSet.contains($0) }

        if hasLowercase { score += 1 } else { feedback.append("Include lowercase letters") }
        if hasUppercase { score += 2 } else { feedback.append("Include uppercase letters") }
        if hasDigits { score += 3 } else { feedback.append("Include numbers") }
        if hasSpecialChars { score += 5 } else { feedback.append("Include special characters") }

        // Common patterns
        let commonPatterns = ["123456", "password", "qwerty", "abc123", "admin"]
        if commonPatterns.contains(where: { normalized.lowercased().contains($0) }) {
            score -= 5
            feedback.append("Avoid common patterns")
        }

        // Sequential characters
        let sequential = ["abcdefghijklmnopqrstuvwxyz", "0123456789"]
        for seq in sequential {
            for i in 0...(seq.count - 3) {
                let substring = String(
                    seq[seq.index(seq.startIndex, offsetBy: i)...seq.index(seq.startIndex, offsetBy: i + 2)])
                if normalized.lowercased().contains(substring) {
                    score -= 3
                    feedback.append("Avoid sequential characters")
                    break
                }
            }
        }

        // Repeated characters (3 or more consecutive)
        var hasTripleRepeat = false
        let chars = Array(normalized)
        if chars.count >= 3 {
            for i in 0...(chars.count - 3) {
                if chars[i] == chars[i + 1] && chars[i] == chars[i + 2] {
                    hasTripleRepeat = true
                    break
                }
            }
        }

        if hasTripleRepeat {
            score -= 3
            feedback.append("Avoid repeated characters")
        }

        let strength: PasswordStrength.Level
        switch score {
        case ..<5: strength = .veryWeak
        case 5...8: strength = .weak
        case 9...12: strength = .fair
        case 13...16: strength = .good
        default: strength = .strong
        }

        return PasswordStrength(level: strength, score: score, feedback: feedback)
    }
}

/// Password strength analysis result
struct PasswordStrength {
    enum Level: String {
        case veryWeak = "Very Weak"
        case weak = "Weak"
        case fair = "Fair"
        case good = "Good"
        case strong = "Strong"

        var color: String {
            switch self {
            case .veryWeak: return "red"
            case .weak: return "orange"
            case .fair: return "yellow"
            case .good: return "blue"
            case .strong: return "green"
            }
        }
    }

    let level: Level
    let score: Int
    let feedback: [String]
}
