import Foundation
import os

// Small lightweight AppLog for the Share Extension target so we avoid raw prints.
struct AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "EncryptedAlbum.ShareExtension"
    private static let defaultLogger = Logger(subsystem: subsystem, category: "share")

    static func error(_ message: String) {
        defaultLogger.error("\(message, privacy: .public)")
    }

    static func debugPrivate(_ message: String) {
        defaultLogger.debug("\(message, privacy: .private)")
    }

    static func debugPublic(_ message: String) {
        defaultLogger.debug("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        defaultLogger.warning("\(message, privacy: .public)")
    }
}
