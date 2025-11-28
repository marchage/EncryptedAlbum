import Foundation

/// Comprehensive error types for the EncryptedAlbum application
enum AlbumError: LocalizedError {
    // MARK: - Authentication Errors
    case invalidPassword
    case passwordTooShort(minLength: Int)
    case passwordTooLong(maxLength: Int)
    case biometricNotAvailable
    case biometricFailed
    case biometricCancelled
    case biometricLockout
    case tooManyBiometricAttempts(maxAttempts: Int)

    // MARK: - Cryptographic Errors
    case encryptionFailed(reason: String)
    case decryptionFailed(reason: String)
    case keyDerivationFailed(reason: String)
    case hmacVerificationFailed
    case invalidKeySize(expected: Int, actual: Int)
    case cryptoOperationFailed(operation: String, reason: String)

    // MARK: - File System Errors
    case fileNotFound(path: String)
    case fileAlreadyExists(path: String)
    case directoryCreationFailed(path: String, reason: String)
    case fileWriteFailed(path: String, reason: String)
    case fileReadFailed(path: String, reason: String)
    case fileDeleteFailed(path: String, reason: String)
    case fileTooLarge(size: Int64, maxSize: Int64)
    case invalidFileFormat(reason: String)
    case thumbnailGenerationFailed(reason: String)

    // MARK: - Album Integrity Errors
    case albumCorrupted(reason: String)
    case metadataCorrupted(reason: String)
    case integrityCheckFailed(reason: String)
    case albumNotInitialized

    // MARK: - Security Errors
    case securityHealthCheckFailed(reason: String)
    case randomGenerationFailed(reason: String)
    case insecureEnvironment(reason: String)

    // MARK: - Rate Limiting Errors
    case rateLimitExceeded(retryAfter: TimeInterval)

    // MARK: - General Errors
    case operationCancelled
    // Lockdown mode prevents many potentially risky operations.
    case operationDeniedByLockdown
    case unknownError(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return "Invalid password"
        case .passwordTooShort(let minLength):
            return "Password must be at least \(minLength) characters long"
        case .passwordTooLong(let maxLength):
            return "Password cannot exceed \(maxLength) characters"
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .biometricCancelled:
            return "Biometric authentication was cancelled"
        case .biometricLockout:
            return "Biometric authentication is locked out due to too many failed attempts"
        case .tooManyBiometricAttempts(let maxAttempts):
            return "Too many biometric authentication attempts. Maximum allowed: \(maxAttempts)"
        case .encryptionFailed(let reason):
            return "Encryption failed: \(reason)"
        case .decryptionFailed(let reason):
            return "Decryption failed: \(reason)"
        case .keyDerivationFailed(let reason):
            return "Key derivation failed: \(reason)"
        case .hmacVerificationFailed:
            return "Data integrity verification failed"
        case .invalidKeySize(let expected, let actual):
            return "Invalid key size. Expected: \(expected) bytes, got: \(actual) bytes"
        case .cryptoOperationFailed(let operation, let reason):
            return "Cryptographic operation '\(operation)' failed: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileAlreadyExists(let path):
            return "File already exists: \(path)"
        case .directoryCreationFailed(let path, let reason):
            return "Failed to create directory '\(path)': \(reason)"
        case .fileWriteFailed(let path, let reason):
            return "Failed to write file '\(path)': \(reason)"
        case .fileReadFailed(let path, let reason):
            return "Failed to read file '\(path)': \(reason)"
        case .fileDeleteFailed(let path, let reason):
            return "Failed to delete file '\(path)': \(reason)"
        case .fileTooLarge(let size, let maxSize):
            return "File size (\(size) bytes) exceeds maximum allowed size (\(maxSize) bytes)"
        case .invalidFileFormat(let reason):
            return "Invalid file format: \(reason)"
        case .thumbnailGenerationFailed(let reason):
            return "Failed to generate thumbnail: \(reason)"
        case .albumCorrupted(let reason):
            return "Album is corrupted: \(reason)"
        case .metadataCorrupted(let reason):
            return "Album metadata is corrupted: \(reason)"
        case .integrityCheckFailed(let reason):
            return "Album integrity check failed: \(reason)"
        case .albumNotInitialized:
            return "Album has not been initialized"
        case .securityHealthCheckFailed(let reason):
            return "Security health check failed: \(reason)"
        case .randomGenerationFailed(let reason):
            return "Random data generation failed: \(reason)"
        case .insecureEnvironment(let reason):
            return "Insecure environment detected: \(reason)"
        case .rateLimitExceeded(let retryAfter):
            return "Rate limit exceeded. Please try again in \(Int(retryAfter)) seconds"
        case .operationCancelled:
            return "Operation was cancelled"
        case .operationDeniedByLockdown:
            return "Operation not allowed while Lockdown Mode is enabled"
        case .operationDeniedByLockdown:
            return "Operation not allowed while Lockdown Mode is enabled"
        case .unknownError(let reason):
            return "An unknown error occurred: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidPassword:
            return "Please check your password and try again"
        case .passwordTooShort:
            return "Please choose a longer password"
        case .passwordTooLong:
            return "Please choose a shorter password"
        case .biometricNotAvailable:
            return "Please use password authentication instead"
        case .biometricFailed, .biometricCancelled:
            return "Please try biometric authentication again or use password authentication"
        case .biometricLockout:
            return "Please enter your device passcode to re-enable biometrics"
        case .tooManyBiometricAttempts:
            return "Please use password authentication and wait before trying biometric authentication again"
        case .encryptionFailed, .decryptionFailed, .keyDerivationFailed, .cryptoOperationFailed:
            return "Please try the operation again. If the problem persists, contact support"
        case .hmacVerificationFailed:
            return "The file may be corrupted. Please verify the file integrity or restore from backup"
        case .invalidKeySize:
            return "This is an internal error. Please contact support"
        case .fileNotFound:
            return "Please check if the file exists and try again"
        case .fileAlreadyExists:
            return "Please choose a different name or location"
        case .directoryCreationFailed:
            return "Please check permissions and available disk space"
        case .fileWriteFailed:
            return "Please check permissions and available disk space"
        case .fileReadFailed:
            return "Please check file permissions and try again"
        case .fileDeleteFailed:
            return "Please check file permissions and try again"
        case .fileTooLarge:
            return "Please choose a smaller file"
        case .invalidFileFormat:
            return "Please ensure the file is in a supported format"
        case .thumbnailGenerationFailed:
            return "Please try again or check if the media file is valid"
        case .albumCorrupted, .metadataCorrupted, .integrityCheckFailed:
            return "Please restore from backup or reinitialize the album"
        case .albumNotInitialized:
            return "Please set up the album first"
        case .securityHealthCheckFailed:
            return "Please ensure the device is in a secure environment"
        case .randomGenerationFailed, .insecureEnvironment:
            return "Please restart the application in a secure environment"
        case .rateLimitExceeded:
            return "Please wait before attempting the operation again"
        case .operationCancelled:
            return "The operation was cancelled by the user"
        case .operationDeniedByLockdown:
            return "This operation is blocked while Lockdown Mode is enabled"
        case .unknownError:
            return "Please try again. If the problem persists, contact support"
        }
    }
}

extension AlbumError: Equatable {}
