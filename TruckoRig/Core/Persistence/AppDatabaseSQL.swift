import Foundation
import GRDB

/// Shared SQL helpers.
extension AppDatabase {
    static func execute(_ db: Database, _ sql: String, _ values: [(any DatabaseValueConvertible)?]) throws {
        try db.execute(sql: sql, arguments: StatementArguments(values))
    }


    static func marks(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }


    static func string(_ row: Row, _ column: String) -> String? { row[column] }
    static func double(_ row: Row, _ column: String) -> Double? { row[column] }
    static func int(_ row: Row, _ column: String) -> Int? { row[column] }
    static func int64(_ row: Row, _ column: String) -> Int64? { row[column] }

    static func uuid(_ row: Row, _ column: String) -> UUID? {
        string(row, column).flatMap(UUID.init(uuidString:))
    }

    static func date(_ row: Row, _ column: String) -> Date? {
        double(row, column).map { Date(timeIntervalSince1970: $0) }
    }

    static func bool(_ row: Row, _ column: String) -> Bool {
        (int(row, column) ?? 0) != 0
    }
}
