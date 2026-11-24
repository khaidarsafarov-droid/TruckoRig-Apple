import Foundation
import UIKit

/// Copies accepted shares out of the App Group into the encrypted journal.
@MainActor
enum ShareImportProcessor {
    struct Outcome: Equatable {
        var inserted: [UUID] = []
        var duplicates = 0
    }

    private static var highlightClear: Task<Void, Never>?

    /// Imports the inbox and asks the journal to stroke the new rows for a few seconds.
    static func receive(
        loads: [Load],
        repository: LoadRepository,
        media: MediaRepository,
        highlight: @escaping (Set<UUID>) -> Void,
        showJournal: @escaping () -> Void
    ) {
        let outcome = importPending(loads: loads, repository: repository, media: media)
        guard !outcome.inserted.isEmpty else { return }
        highlight(Set(outcome.inserted))
        showJournal()
        highlightClear?.cancel()
        highlightClear = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            highlight([])
        }
    }

    static func importPending(
        loads: [Load],
        repository: LoadRepository,
        media: MediaRepository,
        inboxRoot: URL? = nil
    ) -> Outcome {
        guard let root = inboxRoot ?? ShareImportContainer.rootURL() else { return Outcome() }
        let inbox = ShareImportInbox(root: root)
        inbox.sweep()
        let pending: [ShareImportRecord]
        do {
            pending = try inbox.pending()
        } catch {
            return Outcome()
        }
        guard !pending.isEmpty else {
            ShareImportIndexPublisher.publish(loads: loads, root: root)
            return Outcome()
        }

        var saved = loads.map {
            ShareImportNote.fingerprint(storageTripId: $0.tripId, rawMessage: $0.rawMessage)
        }
        var taken = Set(loads.map(\.tripId))
        var batch: [ShareImportFingerprint] = []
        var outcome = Outcome()

        repository.batch {
        for record in pending {
            let plan = ShareLoadCommit.plan(
                fields: record.load,
                fileSHA256: record.fileSHA256,
                sourceText: record.sourceText,
                existing: saved + batch.map {
                    ShareImportFingerprint(tripId: $0.tripId, broker: $0.broker, fileSHA256: nil)
                },
                takenStorageIds: taken
            )
            if ShareImportDeduper.isDuplicate(record.fingerprint, saved: saved, batch: batch) {
                outcome.duplicates += 1
                try? inbox.remove(record.id)
                continue
            }
            switch plan {
            case .duplicate:
                outcome.duplicates += 1
                try? inbox.remove(record.id)
            case .insert(let draft):
                do {
                    let load = try repository.create(draft)
                    attach(record, inbox: inbox, to: load, media: media)
                    outcome.inserted.append(load.id)
                    taken.insert(load.tripId)
                    let recovered = ShareImportNote.fingerprint(storageTripId: load.tripId, rawMessage: load.rawMessage)
                    saved.append(ShareImportFingerprint(tripId: recovered.tripId, broker: recovered.broker, fileSHA256: nil))
                    batch.append(record.fingerprint)
                    try? inbox.remove(record.id)
                } catch LoadRepositoryError.duplicateTripId {
                    outcome.duplicates += 1
                    try? inbox.remove(record.id)
                } catch {
                    try? inbox.remove(record.id)
                }
            }
        }
        }
        return outcome
    }

    private static func attach(
        _ record: ShareImportRecord,
        inbox: ShareImportInbox,
        to load: Load,
        media: MediaRepository
    ) {
        guard let data = try? inbox.fileData(for: record), !data.isEmpty else { return }
        guard let url = inbox.fileURL(for: record) else { return }
        let ext = url.pathExtension.lowercased()
        let day = MediaClock.format(load.date, pattern: "yyyy-MM-dd", timeZone: .current)
        let images: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff"]
        if images.contains(ext), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) {
            let fields = StoredPhotoFields.make(
                tripId: load.tripId,
                loadDate: day,
                location: LocationStamp(),
                timestamp: Date(),
                loadId: load.id.uuidString
            )
            try? media.savePhoto(fields: fields, jpeg: jpeg, load: load)
            return
        }
        let isPDF = ext == "pdf" || data.starts(with: Data("%PDF".utf8))
        guard isPDF else { return }
        let fields = StoredScanFields.make(
            tripId: load.tripId,
            loadDate: day,
            timestamp: Date(),
            fileSizeBytes: Int64(data.count),
            pageCount: max(record.pageCount, 1),
            ocrText: String(record.sourceText.prefix(ShareImportNote.bodyLimit)),
            loadId: load.id.uuidString,
            category: .load
        )
        try? media.saveScan(fields: fields, pdf: data, load: load)
    }
}

enum ShareImportIndexPublisher {
    static func publish(loads: [Load]) {
        guard let root = ShareImportContainer.rootURL() else { return }
        publish(loads: loads, root: root)
    }

    static func publish(loads: [Load], root: URL) {
        let fingerprints = loads.map {
            ShareImportNote.fingerprint(storageTripId: $0.tripId, rawMessage: $0.rawMessage)
        }
        try? ShareImportIndexStore.save(fingerprints, to: root)
    }
}
