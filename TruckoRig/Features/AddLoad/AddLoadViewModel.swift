import Foundation
import Observation
import SwiftData

/// Backs both the paste-from-Relay flow and manual entry on the add screen.
@MainActor
@Observable
final class AddLoadViewModel {

    var draft = LoadDraft()
    var relayText = ""
    var parseMessage: String?
    var errorMessage: String?
    /// Trip ID that already exists, driving the duplicate alert.
    var duplicateTripId: String?
    var isSaving = false
    /// Extra trips found in the same paste, offered as a bulk import.
    private(set) var additionalParsed: [ParsedLoad] = []

    var canSave: Bool { draft.isValid && !isSaving }

    // MARK: - Relay paste

    /// Parses pasted text into the form.
    ///
    /// The first trip fills the form so the driver can check it before saving; any extra trips in
    /// the same paste are kept aside and imported in one go.
    func parseRelayText(now: Date = Date()) {
        parseMessage = nil
        errorMessage = nil
        additionalParsed = []

        let results = AmazonRelayParser.parseAll(relayText, reference: now)
        guard let first = results.first else {
            errorMessage = AmazonRelayParser.diagnose(relayText).localizedMessage
            return
        }

        draft = LoadDraft(parsed: first.load, fallbackDate: now)
        additionalParsed = results.dropFirst().map(\.load)
        parseMessage = additionalParsed.isEmpty
            ? String(localized: "relay.parsed.one \(first.tripId)")
            : String(localized: "relay.parsed.many \(results.count)")
    }

    func clearRelayText() {
        relayText = ""
        parseMessage = nil
        errorMessage = nil
        additionalParsed = []
    }

    // MARK: - Stops

    func addStop(_ type: StopType) {
        draft.stops.append(StopDraft(type: type, stopNumber: draft.stops.count + 1))
    }

    func removeStops(at offsets: IndexSet) {
        draft.stops.remove(atOffsets: offsets)
        draft.renumberStops()
    }

    func moveStops(from source: IndexSet, to destination: Int) {
        draft.stops.move(fromOffsets: source, toOffset: destination)
        draft.renumberStops()
    }

    // MARK: - Save

    /// Saves the form and any extra parsed trips.
    ///
    /// - Returns: `true` when the sheet should close.
    func save(using repository: LoadRepository) -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }

        do {
            try repository.create(draft)
        } catch LoadRepositoryError.duplicateTripId(let tripId) {
            duplicateTripId = tripId
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        if !additionalParsed.isEmpty {
            let outcome = repository.importParsed(additionalParsed)
            if !outcome.duplicates.isEmpty {
                AppLog.parser.notice("Skipped \(outcome.duplicates.count, privacy: .public) duplicate trips on import")
            }
        }
        return true
    }
}
