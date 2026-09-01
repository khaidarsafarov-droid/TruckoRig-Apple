import Foundation
import SwiftData
import UniformTypeIdentifiers

/// JSON backup and restore.
///
/// The backup uses the same snapshot shape as cloud sync, so a file exported from one device can
/// be restored on another — or on Android — without a second format to keep in step.
enum BackupService {

    static let fileExtension = "truckorig.json"

    @MainActor
    static func exportSnapshot(from context: ModelContext, scope: AccountScope) throws -> URL {
        let snapshot = try SnapshotBuilder.build(from: context)
        let data = try JSONEncoder.api.encode(snapshot)
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
        let snapshot = try JSONDecoder.api.decode(AccountCloudSnapshot.self, from: data)
        return try SnapshotApplier.apply(snapshot, to: context, week: week)
    }
}
