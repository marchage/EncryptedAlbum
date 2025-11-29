import Foundation

// MARK: - Constants

/// Cryptographic constants for the EncryptedAlbum application
enum CryptoConstants {
    /// Key sizes
    static let masterKeySize = 32
    static let encryptionKeySize = 32
    static let hmacKeySize = 32
    static let saltSize = 32

    /// Password constraints
    static let minPasswordLength = 8
    static let maxPasswordLength = 128

    /// Key derivation parameters
    static let pbkdf2Iterations = 600001
    static let hkdfInfoEncryption = "EncryptedAlbum-Encryption"
    static let hkdfInfoHMAC = "EncryptedAlbum-HMAC"
    static let hkdfInfoVerifier = "EncryptedAlbum-Verifier"

    /// File size limits
    static let maxMediaFileSize: Int64 = 500 * 1024 * 1024 * 1024  // 5000MB (~500GB)
    static let maxThumbnailFileSize: Int64 = 100 * 1024 * 1024  // 100MB
    static let maxSecureDeleteSize: Int64 = 100 * 1024 * 1024  // 100MB

    /// Streaming encryption
    static let streamingMagic = "SVSTRM01"
    static let streamingVersion: UInt8 = 3  // Bumped to 3 for completion marker trailer
    static let streamingChunkSize = 4 * 1024 * 1024  // 4MB chunks
    static let streamingNonceSize = 12
    static let streamingTagSize = 16
    static let streamingCompletionMarker = "SVF2DONE"  // Indicates encrypt completed successfully

    /// Thumbnail dimensions
    static let maxThumbnailDimension: CGFloat = 300

    /// Security timeouts and limits
    static let idleTimeout: TimeInterval = 600  // 10 minutes
    static let biometricMaxAttempts = 3
    static let rateLimitBaseDelay: TimeInterval = 5
    static let rateLimitMaxDelay: TimeInterval = 300  // 5 minutes

    /// Compression quality
    static let thumbnailCompressionQuality: CGFloat = 0.8
}

/// File system constants
enum FileConstants {
    static let photosDirectoryName = "photos"
    static let photosMetadataFileName = "hidden_photos.json"
    static let settingsFileName = "settings.json"
    static let encryptedFileExtension = "enc"
    static let hmacFileExtension = "hmac"
    static let thumbnailFileExtension = "jpg"
    static let encryptedThumbnailSuffix = "_thumb.enc"
    static let thumbnailSuffix = "_thumb.jpg"
    static let tempWorkingDirectoryName = "EncryptedAlbumTemp"
    static let decryptedTempPrefix = "sv-decrypted"

    // TODO: Replace with your actual App Group ID
    // Use the new shared app group for extension -> app communication
    static let appGroupIdentifier = "group.biz.front-end.EncryptedAlbum.shared"
    /// CloudKit container identifier used for encrypted sync
    static let iCloudContainerIdentifier = "iCloud.biz.front-end.EncryptedAlbum"
    static let appGroupInboxName = "ImportInbox"
}

/// Security validation constants
enum SecurityConstants {
    static let randomValidationSampleSize = 100
    static let minRandomEntropy = 0.8
    static let cryptoTestData = "EncryptedAlbum crypto validation test data"
}

/// Shared UI layout metrics
enum UIConstants {
    static let progressCardWidth: CGFloat = 320
}
