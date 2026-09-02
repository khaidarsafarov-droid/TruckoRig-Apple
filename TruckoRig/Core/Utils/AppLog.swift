import Foundation
import OSLog

/// App logging.
///
/// OCR text never reaches the log: a sysdiagnose the driver emails to support must not contain
/// the contents of scanned paperwork.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.truckorig"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let parser = Logger(subsystem: subsystem, category: "parser")
}
