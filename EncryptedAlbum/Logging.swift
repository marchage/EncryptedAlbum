import Foundation
import os

/// A small wrapper around `os.Logger` that provides helpers for public and private logs.
/// Use `AppLog.public` for non-sensitive messages and `AppLog.private` for messages containing
/// filenames, paths or other user data. This keeps release logs from accidentally exposing
/// sensitive information.
struct AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "EncryptedAlbum"
    private static let defaultLogger = Logger(subsystem: subsystem, category: "app")

    static func info(_ message: String) {
        defaultLogger.info("\(message, privacy: .public)")
    }

    static func debugPublic(_ message: String) {
        #if DEBUG
        defaultLogger.debug("\(message, privacy: .public)")
        #else
        // In release keep noise minimal
        defaultLogger.debug("\(message, privacy: .public)")
        #endif
    }

    static func debugPrivate(_ message: String) {
        // Use private privacy to avoid putting secrets/paths in system logs
        defaultLogger.debug("\(message, privacy: .private)")
    }

    static func warning(_ message: String) {
        defaultLogger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        defaultLogger.error("\(message, privacy: .public)")
    }
}
