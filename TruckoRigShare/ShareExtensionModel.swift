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
        defer { deleteTemps(pieces) }
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
            accept(piece, inbox: inbox, saved: saved, batch: &batch, tally: &tally)
        }
        if tally.added == 0, pieces.count > 1 {
            let joined = pieces.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
            let carrier = pieces.first { $0.fileURL != nil } ?? pieces[0]
            let combined = SharePiece(text: joined, fileURL: carrier.fileURL, fileName: carrier.fileName, pageCount: carrier.pageCount)
            accept(combined, inbox: inbox, saved: saved, batch: &batch, tally: &tally)
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
    ) {
        let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch ShareLoadClassifier.classify(text: text, fileName: piece.fileName) {
        case .rejected:
            break
        case .accepted(let loads):
            let hash = piece.fileURL.flatMap { ShareFileHash.sha256Hex(file: $0) }
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
                guard (try? inbox.enqueue(record, file: piece.fileURL)) != nil else {
                    continue
                }
                batch.append(fingerprint)
                tally.added += 1
                if !fields.missing.isEmpty { tally.partial = true }
            }
        }
    }

    private func deleteTemps(_ pieces: [SharePiece]) {
        for piece in pieces {
            guard let url = piece.fileURL else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
