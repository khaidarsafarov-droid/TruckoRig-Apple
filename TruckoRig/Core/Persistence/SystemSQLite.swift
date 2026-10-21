import Darwin
import Foundation

/// Read/write access to the system SQLite, loaded with `dlopen` so it does not clash with
/// SQLCipher's `sqlite3_*` symbols inside the app process.
///
/// SwiftData stores are ordinary SQLite files. SQLCipher cannot be linked next to the system
/// library, and it will not reliably open a plaintext Core Data file, so the one-time import
/// uses this handle instead.
enum SystemSQLite {

    struct Failure: Error, CustomStringConvertible {
        var message: String
        var description: String { message }
    }

    enum Value: Equatable {
        case null
        case int(Int64)
        case double(Double)
        case text(String)
        case blob(Data)

        var int: Int64? {
            if case .int(let value) = self { return value }
            if case .double(let value) = self { return Int64(value) }
            return nil
        }

        var double: Double? {
            if case .double(let value) = self { return value }
            if case .int(let value) = self { return Double(value) }
            return nil
        }

        var text: String? {
            if case .text(let value) = self { return value }
            return nil
        }

        var blob: Data? {
            if case .blob(let value) = self { return value }
            return nil
        }
    }

    final class Connection {
        private let db: OpaquePointer
        private let api: API

        private init(db: OpaquePointer, api: API) {
            self.db = db
            self.api = api
        }

        deinit {
            _ = api.close(db)
        }

        func execute(_ sql: String) throws {
            _ = try query(sql)
        }

        func query(_ sql: String) throws -> [[String: Value]] {
            var statement: OpaquePointer?
            let status = sql.withCString { cString in
                api.prepare(db, cString, -1, &statement, nil)
            }
            guard status == SQLITE_OK, let statement else {
                throw Failure(message: message(fallback: "SQLite prepare failed (\(status))"))
            }
            defer { _ = api.finalize(statement) }

            var rows: [[String: Value]] = []
            while true {
                let step = api.step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else {
                    throw Failure(message: message(fallback: "SQLite step failed (\(step))"))
                }
                var row: [String: Value] = [:]
                let count = Int(api.columnCount(statement))
                for index in 0..<count {
                    guard let namePointer = api.columnName(statement, Int32(index)) else { continue }
                    let name = String(cString: namePointer)
                    row[name] = value(statement, column: Int32(index))
                }
                rows.append(row)
            }
            return rows
        }

        private func value(_ statement: OpaquePointer, column: Int32) -> Value {
            switch api.columnType(statement, column) {
            case SQLITE_INTEGER:
                return .int(api.columnInt64(statement, column))
            case SQLITE_FLOAT:
                return .double(api.columnDouble(statement, column))
            case SQLITE_TEXT:
                guard let pointer = api.columnText(statement, column) else { return .null }
                return .text(String(cString: pointer))
            case SQLITE_BLOB:
                guard let pointer = api.columnBlob(statement, column) else { return .null }
                let count = Int(api.columnBytes(statement, column))
                return .blob(Data(bytes: pointer, count: count))
            default:
                return .null
            }
        }

        private func message(fallback: String) -> String {
            guard let pointer = api.errmsg(db) else { return fallback }
            let text = String(cString: pointer)
            return text.isEmpty ? fallback : text
        }
    }

    static func open(path: String, readOnly: Bool) throws -> Connection {
        let api = try sharedAPI()
        var db: OpaquePointer?
        let flags: Int32 = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let status = path.withCString { cString in
            api.open(cString, &db, flags, nil)
        }
        guard status == SQLITE_OK, let db else {
            throw Failure(message: "Could not open \(path) (\(status))")
        }
        return Connection(db: db, api: api)
    }

    // MARK: - Dynamic loading

    private static let SQLITE_OK: Int32 = 0
    private static let SQLITE_ROW: Int32 = 100
    private static let SQLITE_DONE: Int32 = 101
    private static let SQLITE_INTEGER: Int32 = 1
    private static let SQLITE_FLOAT: Int32 = 2
    private static let SQLITE_TEXT: Int32 = 3
    private static let SQLITE_BLOB: Int32 = 4
    private static let SQLITE_OPEN_READONLY: Int32 = 0x0000_0001
    private static let SQLITE_OPEN_READWRITE: Int32 = 0x0000_0002
    private static let SQLITE_OPEN_CREATE: Int32 = 0x0000_0004

    private struct API {
        var open: @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<OpaquePointer?>?, Int32, UnsafePointer<CChar>?) -> Int32
        var close: @convention(c) (OpaquePointer?) -> Int32
        var prepare: @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<OpaquePointer?>?, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
        var step: @convention(c) (OpaquePointer?) -> Int32
        var finalize: @convention(c) (OpaquePointer?) -> Int32
        var columnCount: @convention(c) (OpaquePointer?) -> Int32
        var columnName: @convention(c) (OpaquePointer?, Int32) -> UnsafePointer<CChar>?
        var columnType: @convention(c) (OpaquePointer?, Int32) -> Int32
        var columnInt64: @convention(c) (OpaquePointer?, Int32) -> Int64
        var columnDouble: @convention(c) (OpaquePointer?, Int32) -> Double
        var columnText: @convention(c) (OpaquePointer?, Int32) -> UnsafePointer<UInt8>?
        var columnBlob: @convention(c) (OpaquePointer?, Int32) -> UnsafeRawPointer?
        var columnBytes: @convention(c) (OpaquePointer?, Int32) -> Int32
        var errmsg: @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    }

    private static var cachedAPI: API?

    private static func sharedAPI() throws -> API {
        if let cachedAPI { return cachedAPI }
        let handle = try loadLibrary()
        let api = API(
            open: try symbol(handle, "sqlite3_open_v2"),
            close: try symbol(handle, "sqlite3_close"),
            prepare: try symbol(handle, "sqlite3_prepare_v2"),
            step: try symbol(handle, "sqlite3_step"),
            finalize: try symbol(handle, "sqlite3_finalize"),
            columnCount: try symbol(handle, "sqlite3_column_count"),
            columnName: try symbol(handle, "sqlite3_column_name"),
            columnType: try symbol(handle, "sqlite3_column_type"),
            columnInt64: try symbol(handle, "sqlite3_column_int64"),
            columnDouble: try symbol(handle, "sqlite3_column_double"),
            columnText: try symbol(handle, "sqlite3_column_text"),
            columnBlob: try symbol(handle, "sqlite3_column_blob"),
            columnBytes: try symbol(handle, "sqlite3_column_bytes"),
            errmsg: try symbol(handle, "sqlite3_errmsg")
        )
        cachedAPI = api
        return api
    }

    private static func loadLibrary() throws -> UnsafeMutableRawPointer {
        let candidates = ["/usr/lib/libsqlite3.dylib", "libsqlite3.dylib"]
        for path in candidates {
            if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                return handle
            }
        }
        let reason = dlerror().map { String(cString: $0) } ?? "dlopen failed"
        throw Failure(message: "System SQLite is unavailable (\(reason))")
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> T {
        guard let pointer = dlsym(handle, name) else {
            throw Failure(message: "System SQLite is missing \(name)")
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}
