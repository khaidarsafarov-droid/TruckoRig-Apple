import Foundation
import Observation

/// Runs classification in the extension, then either writes the inbox or adds nothing.
@MainActor
@Observable
final class ShareExtensionModel {
    enum Phase: Equatable {
        case checking
        case added(partial: Bool, many: Bool)
        case duplicate
        case rejected
        case unavailable
        case failed
    }

    var phase: Phase = .checking

    private var context: NSExtensionContext?
    private var didFinish = false
    private var didStart = false

    func start(context: NSExtensionContext?) {
        guard !didStart else { return }
        didStart = true
        self.context = context
        Task { await run() }
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        context?.completeRequest(returningItems: [])
    }

    func openHost() {
        guard let context, let url = URL(string: ShareImportLocation.openURLString) else {
            finish()
            return
        }
        context.open(url) { [weak self] accepted in
            Task { @MainActor in
                if accepted {
                    self?.finish()
                }
            }
        }
    }

    private func run() async {
        guard let root = ShareImportContainer.rootURL() else {
            phase = .unavailable
            return
        }
        let pieces = await SharePayloadReader.pieces(from: context)
        guard !pieces.isEmpty else {
            phase = .failed
            return
        }

        let inbox = ShareImportInbox(root: root)
        var saved = ShareImportIndexStore.load(from: root)
        if let pending = try? inbox.pending() {
            saved.append(contentsOf: pending.map(\.fingerprint))
        }
        var batch: [ShareImportFingerprint] = []
        var tally = Tally()
        for piece in pieces {
            await accept(piece, inbox: inbox, saved: saved, batch: &batch, tally: &tally)
        }
        if tally.added == 0, pieces.count > 1 {
            let joined = pieces.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
            let carrier = pieces.first { $0.fileBytes != nil } ?? pieces[0]
            let combined = SharePiece(text: joined, fileBytes: carrier.fileBytes, fileName: carrier.fileName, pageCount: carrier.pageCount)
            await accept(combined, inbox: inbox, saved: saved, batch: &batch, tally: &tally)
        }

        if tally.added > 0 {
            ShareImportNotifier.shared.post()
            phase = .added(partial: tally.partial, many: tally.added > 1)
            try? await Task.sleep(nanoseconds: 900_000_000)
            openHost()
            return
        }
        phase = tally.duplicates > 0 ? .duplicate : .rejected
    }

    private struct Tally {
        var added = 0
        var duplicates = 0
        var partial = false
    }

    private func accept(
        _ piece: SharePiece,
        inbox: ShareImportInbox,
        saved: [ShareImportFingerprint],
        batch: inout [ShareImportFingerprint],
        tally: inout Tally
    ) async {
        let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch ShareLoadClassifier.classify(text: text, fileName: piece.fileName) {
        case .rejected:
            break
        case .accepted(let loads):
            let hash = await Self.fileHash(piece.fileBytes)
            for fields in loads {
                let fingerprint = ShareImportFingerprint(tripId: fields.tripId, broker: fields.broker, fileSHA256: hash)
                if ShareImportDeduper.isDuplicate(fingerprint, saved: saved, batch: batch) {
                    tally.duplicates += 1
                    continue
                }
                let record = ShareImportRecord(
                    sourceText: text,
                    fileSHA256: hash,
                    originalFileName: piece.fileName,
                    pageCount: piece.pageCount,
                    load: fields
                )
                let bytes = piece.fileBytes
                let stored = await Task.detached(priority: .userInitiated) {
                    (try? inbox.enqueue(record, bytes: bytes)) != nil
                }.value
                guard stored else { continue }
                batch.append(fingerprint)
                tally.added += 1
                if !fields.missing.isEmpty { tally.partial = true }
            }
        }
    }

    private static func fileHash(_ bytes: Data?) async -> String? {
        guard let bytes else { return nil }
        return await Task.detached(priority: .userInitiated) {
            ShareFileHash.sha256Hex(data: bytes)
        }.value
    }

}
