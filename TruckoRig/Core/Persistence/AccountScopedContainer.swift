import Foundation

/// Which account's database is open.
enum AccountScope: Equatable, Hashable {
    /// The only store the app opens: everything stays on this phone.
    case local
    case user(String)

    /// File-safe fragment used in the store name.
    var storeKey: String {
        switch self {
        case .local: return "local"
        case .user(let id): return AccountScope.sanitize(id)
        }
    }

    /// Keeps leftover Apple user IDs from older installs out of file paths.
    static func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = cleaned.isEmpty ? "unknown" : cleaned
        // Long provider IDs would blow past filesystem name limits; a stable hash suffix keeps
        // truncated names unique.
        guard trimmed.count > 48 else { return trimmed }
        return "\(trimmed.prefix(40))_\(abs(raw.hashValue))"
    }
}

enum AccountScopedContainerError: Error {
    case storeDirectoryUnavailable
}

/// Paths for the encrypted database and the SwiftData file it replaces.
enum AccountScopedContainer {

    static let directoryName = "TruckoRig"

    static func storeDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AccountScopedContainerError.storeDirectoryUnavailable
        }
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Plaintext SwiftData file written by builds before SQLCipher (`TruckoRig_local.store`).
    static func storeURL(for scope: AccountScope) throws -> URL {
        try storeDirectory().appendingPathComponent("TruckoRig_\(scope.storeKey).store")
    }

    /// SQLCipher database (`TruckoRig_local.sqlite`).
    static func databaseURL(for scope: AccountScope) throws -> URL {
        try storeDirectory().appendingPathComponent("TruckoRig_\(scope.storeKey).sqlite")
    }

    /// Deletes a SwiftData store and its SQLite sidecar files. Does not touch the encrypted file.
    static func destroyStore(for scope: AccountScope) throws {
        let url = try storeURL(for: scope)
        let sidecars = ["", "-wal", "-shm"].map { suffix in
            URL(fileURLWithPath: url.path + suffix)
        }
        for file in sidecars where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
