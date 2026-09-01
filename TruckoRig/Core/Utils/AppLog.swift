import Foundation
import OSLog

/// App logging.
///
/// Nothing sensitive ever reaches the log: JWTs, presigned URLs and OCR text can all end up in a
/// sysdiagnose the driver emails to support. `redact` exists so a URL or token can still be
/// mentioned in a diagnostic line without leaking its contents.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.truckorig"

    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let parser = Logger(subsystem: subsystem, category: "parser")

    /// Keeps a value's shape (length, host) without its content.
    static func redact(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "<empty>" }
        return "<redacted \(value.count) chars>"
    }

    /// Host and path of a URL, with query and credentials removed — presigned URLs carry their
    /// signature in the query string.
    static func redact(_ url: URL?) -> String {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<no url>"
        }
        let host = components.host ?? "?"
        return "\(components.scheme ?? "?")://\(host)\(components.path)"
    }
}
