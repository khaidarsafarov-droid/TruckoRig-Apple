import Foundation
import SwiftData

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

/// Builds the SwiftData container for the active store file.
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

    static func storeURL(for scope: AccountScope) throws -> URL {
        try storeDirectory().appendingPathComponent("TruckoRig_\(scope.storeKey).store")
    }

    static func make(for scope: AccountScope) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TruckoRig_\(scope.storeKey)",
            schema: TruckoRigSchema.schema,
            url: try storeURL(for: scope),
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: TruckoRigSchema.schema, configurations: configuration)
    }

    /// In-memory container for previews and tests.
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: TruckoRigSchema.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: TruckoRigSchema.schema, configurations: configuration)
    }

    /// Deletes an account's store and its SQLite sidecar files.
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
