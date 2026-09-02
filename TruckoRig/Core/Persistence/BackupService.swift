import Foundation
import SwiftData
import UniformTypeIdentifiers

/// JSON backup and restore.
///
/// A file exported from one device can be restored on another without a second format.
enum BackupService {

    static let fileExtension = "truckorig.json"

    @MainActor
    static func exportSnapshot(from context: ModelContext, scope: AccountScope) throws -> URL {
        let snapshot = try SnapshotBuilder.build(from: context)
        let data = try JSONEncoder.snapshot.encode(snapshot)
        let name = "TruckoRig_\(scope.storeKey)_\(DateUtils.isoDay(Date())).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Restores a backup, merging by last-write-wins rather than replacing the database.
    ///
    /// Replacing would throw away anything recorded since the backup, which is the opposite of
    /// what a driver restoring after a phone swap expects.
    @MainActor
    @discardableResult
    static func restore(from url: URL, into context: ModelContext, week: TruckingWeek) throws -> SnapshotApplier.Report {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer { if needsScopedAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder.snapshot.decode(AccountSnapshot.self, from: data)
        return try SnapshotApplier.apply(snapshot, to: context, week: week)
    }
}
