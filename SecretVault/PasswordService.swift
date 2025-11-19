import Foundation
import CryptoKit

/// Service responsible for password management and validation
class PasswordService {
    private let queue = DispatchQueue(label: "com.secretvault.password", qos: .userInitiated)
    private let cryptoService: CryptoService
    private let securityService: SecurityService

    init(cryptoService: CryptoService, securityService: SecurityService) {
        self.cryptoService = cryptoService
        self.securityService = securityService
    }

    // MARK: - Password Validation

    /// Validates password strength and requirements
    func validatePassword(_ password: String) throws {
        guard !password.isEmpty else {
            throw VaultError.invalidPassword
        }

        if password.count < CryptoConstants.minPasswordLength {
            throw VaultError.passwordTooShort(minLength: CryptoConstants.minPasswordLength)
        }

        if password.count > CryptoConstants.maxPasswordLength {
            throw VaultError.passwordTooLong(maxLength: CryptoConstants.maxPasswordLength)
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
                        let (encryptionKey, _) = try await self.cryptoService.deriveKeys(password: password, salt: salt)

                        // Use the encryption key as the password hash
                        // In a real implementation, you might want to use a dedicated KDF for password hashing
                        let hash = encryptionKey.withUnsafeBytes { Data($0) }

                        continuation.resume(returning: (hash, salt))
                    } catch {
                        continuation.resume(throwing: VaultError.keyDerivationFailed(reason: error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Verifies a password against a stored hash
    func verifyPassword(_ password: String, against hash: Data, salt: Data) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        let (computedKey, _) = try await self.cryptoService.deriveKeys(password: password, salt: salt)
                        let computedHash = computedKey.withUnsafeBytes { Data($0) }

                        continuation.resume(returning: computedHash == hash)
                    } catch {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    // MARK: - Password Storage

    private let passwordHashKey = "com.secretvault.passwordHash"
    private let passwordSaltKey = "com.secretvault.passwordSalt"

    /// Stores password hash and salt securely
    func storePasswordHash(_ hash: Data, salt: Data) throws {
        try securityService.storeInKeychain(data: hash, for: passwordHashKey)
        try securityService.storeInKeychain(data: salt, for: passwordSaltKey)
    }

    /// Retrieves stored password hash and salt
    func retrievePasswordCredentials() throws -> (hash: Data, salt: Data)? {
        guard let hash = try securityService.retrieveFromKeychain(for: passwordHashKey),
              let salt = try securityService.retrieveFromKeychain(for: passwordSaltKey) else {
            return nil
        }
        return (hash, salt)
    }

    /// Clears stored password credentials
    func clearPasswordCredentials() throws {
        try securityService.deleteFromKeychain(for: passwordHashKey)
        try securityService.deleteFromKeychain(for: passwordSaltKey)
    }

    // MARK: - Password Change

    /// Changes the vault password
    func changePassword(from oldPassword: String, to newPassword: String, vaultURL: URL, encryptionKey: SymmetricKey, hmacKey: SymmetricKey) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        // Validate new password
                        try self.validatePassword(newPassword)

                        // Verify old password
                        guard let (storedHash, storedSalt) = try self.retrievePasswordCredentials() else {
                            continuation.resume(throwing: VaultError.vaultNotInitialized)
                            return
                        }

                        let oldPasswordValid = try await self.verifyPassword(oldPassword, against: storedHash, salt: storedSalt)
                        guard oldPasswordValid else {
                            continuation.resume(throwing: VaultError.invalidPassword)
                            return
                        }

                        // Generate new hash and salt for new password
                        let (newHash, newSalt) = try await self.hashPassword(newPassword)

                        // Store new credentials
                        try self.storePasswordHash(newHash, salt: newSalt)

                        // TODO: Re-encrypt all vault contents with new keys derived from new password
                        // This would require:
                        // 1. Deriving new encryption/HMAC keys from new password
                        // 2. Reading all encrypted files
                        // 3. Re-encrypting with new keys
                        // 4. Updating metadata
                        // This is a complex operation that should be done carefully

                        continuation.resume(returning: ())
                    } catch let error as VaultError {
                        continuation.resume(throwing: error)
                    } catch {
                        continuation.resume(throwing: VaultError.unknownError(reason: error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Password Strength Analysis

    /// Analyzes password strength and provides feedback
    func analyzePasswordStrength(_ password: String) -> PasswordStrength {
        var score = 0
        var feedback: [String] = []

        // Length check
        if password.count >= 12 {
            score += 2
        } else if password.count >= 8 {
            score += 1
        } else {
            feedback.append("Use at least 8 characters")
        }

        // Character variety
        let hasLowercase = password.contains { $0.isLowercase }
        let hasUppercase = password.contains { $0.isUppercase }
        let hasDigits = password.contains { $0.isNumber }
        let hasSpecialChars = password.contains { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }

        if hasLowercase { score += 1 } else { feedback.append("Include lowercase letters") }
        if hasUppercase { score += 1 } else { feedback.append("Include uppercase letters") }
        if hasDigits { score += 1 } else { feedback.append("Include numbers") }
        if hasSpecialChars { score += 1 } else { feedback.append("Include special characters") }

        // Common patterns
        let commonPatterns = ["123456", "password", "qwerty", "abc123", "admin"]
        if commonPatterns.contains(where: { password.lowercased().contains($0) }) {
            score -= 2
            feedback.append("Avoid common patterns")
        }

        // Sequential characters
        let sequential = ["abcdefghijklmnopqrstuvwxyz", "0123456789"]
        for seq in sequential {
            for i in 0...(seq.count - 3) {
                let substring = String(seq[seq.index(seq.startIndex, offsetBy: i)...seq.index(seq.startIndex, offsetBy: i + 2)])
                if password.lowercased().contains(substring) {
                    score -= 1
                    feedback.append("Avoid sequential characters")
                    break
                }
            }
        }

        // Repeated characters
        if password.contains(where: { char in
            password.filter { $0 == char }.count >= 3
        }) {
            score -= 1
            feedback.append("Avoid repeated characters")
        }

        let strength: PasswordStrength.Level
        switch score {
        case 0...2: strength = .veryWeak
        case 3...4: strength = .weak
        case 5...6: strength = .fair
        case 7...8: strength = .good
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