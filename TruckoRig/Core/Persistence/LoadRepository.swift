import Foundation
import SwiftData

enum LoadRepositoryError: Error, LocalizedError, Equatable {
    case duplicateTripId(String)
    case invalidDraft([LoadDraft.ValidationError])

    var errorDescription: String? {
        switch self {
        case .duplicateTripId(let tripId):
            return String(localized: "load.error.duplicate \(tripId)")
        case .invalidDraft(let errors):
            return errors.first.map { String(localized: String.LocalizationValue($0.messageKey)) }
        }
    }
}

/// Every write path for loads.
///
/// Local-first by construction: the SwiftData write and its outbox row are saved together, and
/// only then does anything reach the network. Nothing in the UI writes loads directly.
@MainActor
struct LoadRepository {

    let context: ModelContext
    let sync: SyncEngine
    let week: TruckingWeek

    init(context: ModelContext, sync: SyncEngine, week: TruckingWeek = TruckingWeek()) {
        self.context = context
        self.sync = sync
        self.week = week
    }

    // MARK: - Queries

    func load(tripId: String) throws -> Load? {
        let normalized = TripID.normalize(tripId)
        var descriptor = FetchDescriptor<Load>(predicate: #Predicate { $0.tripId == normalized })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func exists(tripId: String) -> Bool {
        ((try? load(tripId: tripId)) ?? nil) != nil
    }

    // MARK: - Create

    /// Inserts a new load.
    ///
    /// A trip ID already in the journal is rejected rather than merged: Relay reposts the same
    /// trip constantly, and silently creating a second row is how a week's gross doubles.
    @discardableResult
    func create(_ draft: LoadDraft) throws -> Load {
        guard draft.isValid else { throw LoadRepositoryError.invalidDraft(draft.validationErrors) }
        let tripId = TripID.normalize(draft.tripId)
        if try load(tripId: tripId) != nil {
            throw LoadRepositoryError.duplicateTripId(tripId)
        }

        let now = Date()
        let load = Load(
            tripId: tripId,
            date: draft.date,
            totalRate: draft.totalRate,
            totalMiles: draft.totalMiles,
            rawMessage: draft.rawMessage,
            parsedAt: now,
            updatedAt: now,
            isDispute: draft.isDispute,
            disputeCompleted: draft.disputeCompleted,
            disputeResponseDate: draft.disputeResponseDate,
            disputeAmount: draft.disputeAmount,
            actualFinishDate: draft.actualFinishDate
        )
        load.stops = draft.normalizedStops.map(Stop.init(draft:))
        context.insert(load)
        load.refreshDerivedFields(week: week)

        sync.enqueue(.load, id: load.id, operation: .create, in: context)
        try context.save()
        return load
    }

    /// Imports parsed trips, skipping ones already in the journal.
    struct ImportOutcome: Equatable {
        var imported: [String] = []
        var duplicates: [String] = []
        var rejected: [String] = []
    }

    @discardableResult
    func importParsed(_ parsed: [ParsedLoad]) -> ImportOutcome {
        var outcome = ImportOutcome()
        for item in parsed {
            let draft = LoadDraft(parsed: item)
            do {
                try create(draft)
                outcome.imported.append(item.tripId)
            } catch LoadRepositoryError.duplicateTripId {
                outcome.duplicates.append(item.tripId)
            } catch {
                outcome.rejected.append(item.tripId)
            }
        }
        return outcome
    }

    // MARK: - Update

    func update(_ load: Load, with draft: LoadDraft) throws {
        guard draft.isValid else { throw LoadRepositoryError.invalidDraft(draft.validationErrors) }
        let tripId = TripID.normalize(draft.tripId)
        if tripId != load.tripId, try self.load(tripId: tripId) != nil {
            throw LoadRepositoryError.duplicateTripId(tripId)
        }

        load.tripId = tripId
        load.date = draft.date
        load.totalRate = draft.totalRate
        load.totalMiles = draft.totalMiles
        load.actualFinishDate = draft.actualFinishDate
        load.isDispute = draft.isDispute
        load.disputeCompleted = draft.disputeCompleted
        load.disputeResponseDate = draft.disputeResponseDate
        load.disputeAmount = draft.disputeAmount

        for stop in load.stops ?? [] { context.delete(stop) }
        load.stops = draft.normalizedStops.map(Stop.init(draft:))

        // parsedAt stays untouched — it is when the trip entered the journal, not when it was
        // last edited.
        load.touch()
        load.refreshDerivedFields(week: week)

        sync.enqueue(.load, id: load.id, operation: .update, in: context)
        try context.save()
    }

    func setDispute(_ load: Load, isDispute: Bool, completed: Bool, amount: Double?, responseDate: Date?) throws {
        load.isDispute = isDispute
        load.disputeCompleted = completed
        load.disputeAmount = amount
        load.disputeResponseDate = responseDate
        load.touch()
        sync.enqueue(.load, id: load.id, operation: .update, in: context)
        try context.save()
    }

    func addPenalty(to load: Load, summary: String, amount: Double, date: Date) throws {
        let penalty = Penalty(summary: summary, amount: amount, date: date)
        penalty.load = load
        context.insert(penalty)
        load.touch()
        sync.enqueue(.load, id: load.id, operation: .update, in: context)
        try context.save()
    }

    func remove(_ penalty: Penalty) throws {
        let load = penalty.load
        context.delete(penalty)
        if let load {
            load.touch()
            sync.enqueue(.load, id: load.id, operation: .update, in: context)
        }
        try context.save()
    }

    // MARK: - Delete

    func delete(_ load: Load) throws {
        let id = load.id
        context.delete(load)
        sync.enqueue(.load, id: id, operation: .delete, in: context)
        try context.save()
    }
}
