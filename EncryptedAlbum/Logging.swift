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

    /// Debug-level public message. Message is an @autoclosure so it is only evaluated
    /// when debug logging is enabled (DEBUG); in Release builds the closure isn't
    /// evaluated and no work is done.
    static func debugPublic(_ message: @autoclosure () -> String) {
        #if DEBUG
        defaultLogger.debug("\(message(), privacy: .public)")
        #else
        // Release: no-op so debug logs don't show in Release builds. The @autoclosure
        // ensures the message expression is not evaluated when logging is disabled.
        #endif
    }

    /// Debug-level private message. Same as `debugPublic` but uses private privacy
    /// to avoid exposing sensitive data in system logs.
    static func debugPrivate(_ message: @autoclosure () -> String) {
        #if DEBUG
        // Use private privacy to avoid putting secrets/paths in system logs
        defaultLogger.debug("\(message(), privacy: .private)")
        #else
        // Release: no-op
        #endif
    }

    static func warning(_ message: String) {
        defaultLogger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        defaultLogger.error("\(message, privacy: .public)")
    }
}
