import Foundation
import OSLog

/// Journal for tracking password change operations to enable recovery from crashes
struct PasswordChangeJournal: Codable {
    /// Journal format version for future compatibility
    let version: Int

    /// Current status of the password change operation
    var status: Status

    /// When the operation started
    let startedAt: Date

    /// First 8 characters of old password hash (for verification only, not the actual password)
    let oldPasswordHashPrefix: String

    /// First 8 characters of new password hash (for verification only)
    let newPasswordHashPrefix: String

    /// The new salt used for key derivation (stored in plaintext as salts are not encrypted)
    let newSalt: Data

    /// The new encryption key, encrypted with the OLD encryption key.
    /// This allows recovery if the app crashes before the keychain is updated.
    let encryptedNewKey: Data

    /// List of files that have been successfully re-encrypted
    var processedFiles: [String]

    /// Total number of files to process
    let totalFiles: Int

    enum Status: String, Codable {
        case inProgress = "in_progress"
        case completed = "completed"
        case failed = "failed"
    }

    init(
        oldPasswordHashPrefix: String,
        newPasswordHashPrefix: String,
        newSalt: Data,
        encryptedNewKey: Data,
        totalFiles: Int
    ) {
        self.version = 1
        self.status = .inProgress
        self.startedAt = Date()
        self.oldPasswordHashPrefix = oldPasswordHashPrefix
        self.newPasswordHashPrefix = newPasswordHashPrefix
        self.newSalt = newSalt
        self.encryptedNewKey = encryptedNewKey
        self.processedFiles = []
        self.totalFiles = totalFiles
    }

    /// Marks a file as successfully processed
    mutating func markProcessed(_ filename: String) {
        if !processedFiles.contains(filename) {
            processedFiles.append(filename)
        }
    }

    /// Checks if a specific file has been processed
    func isProcessed(_ filename: String) -> Bool {
        return processedFiles.contains(filename)
    }

    /// Returns progress as a percentage (0.0 to 1.0)
    var progress: Double {
        guard totalFiles > 0 else { return 1.0 }
        return Double(processedFiles.count) / Double(totalFiles)
    }
}

/// Service for managing password change journal persistence
class PasswordChangeJournalService {
    private let journalFilename = "password_change_journal.json"
    private let logger = Logger(subsystem: "biz.front-end.EncryptedAlbum", category: "journal")

    /// Returns the URL for the journal file in the album directory
    private func journalURL(in albumDirectory: URL) -> URL {
        return albumDirectory.appendingPathComponent(journalFilename)
    }

    /// Writes the journal to disk
    func writeJournal(_ journal: PasswordChangeJournal, to albumDirectory: URL) throws {
        let url = journalURL(in: albumDirectory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(journal)
        try data.write(to: url, options: .atomic)

        logger.debug("[Journal] Written to \(url.path)")
        logger.debug("[Journal] Progress: \(journal.processedFiles.count)/\(journal.totalFiles)")
    }

    /// Reads the journal from disk if it exists
    func readJournal(from albumDirectory: URL) throws -> PasswordChangeJournal? {
        let url = journalURL(in: albumDirectory)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let journal = try decoder.decode(PasswordChangeJournal.self, from: data)

        logger.debug("[Journal] Read from \(url.path)")
        logger.debug("[Journal] Status: \(journal.status.rawValue)")
        logger.debug("[Journal] Progress: \(journal.processedFiles.count)/\(journal.totalFiles)")

        return journal
    }

    /// Deletes the journal file
    func deleteJournal(from albumDirectory: URL) throws {
        let url = journalURL(in: albumDirectory)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.removeItem(at: url)
        logger.debug("[Journal] Deleted from \(url.path)")
    }

    /// Checks if a journal exists
    func journalExists(in albumDirectory: URL) -> Bool {
        let url = journalURL(in: albumDirectory)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
