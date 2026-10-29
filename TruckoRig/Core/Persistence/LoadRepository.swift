import Foundation

enum LoadRepositoryError: Error, LocalizedError, Equatable {
    case duplicateTripId(String)
    case invalidDraft([LoadDraft.ValidationError])

    var errorDescription: String? {
        switch self {
        case .duplicateTripId(let tripId):
            return String(localized: "load.error.duplicate \(tripId)")
        case .invalidDraft(let errors):
            return errors.first?.localizedMessage
        }
    }
}

/// Every write path for loads.
///
/// The encrypted write is saved, then the home-screen widget is refreshed. Nothing in the UI
/// writes loads directly.
@MainActor
struct LoadRepository {

    let database: AppDatabase
    let week: TruckingWeek
    /// Called after a successful save so the catalog and the home-screen widget can catch up.
    let onDidSave: (() -> Void)?

    init(
        database: AppDatabase,
        week: TruckingWeek = TruckingWeek(),
        onDidSave: (() -> Void)? = nil
    ) {
        self.database = database
        self.week = week
        self.onDidSave = onDidSave
    }

    private func persist(_ load: Load) throws {
        try database.save(load)
        onDidSave?()
    }

    // MARK: - Queries

    func load(tripId: String) throws -> Load? {
        try database.load(tripId: tripId)
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
            disputeCompleted: false,
            disputeResponseDate: draft.disputeResponseDate,
            disputeAmount: draft.disputeAmount,
            disputeApplyToLoad: draft.disputeApplyToLoad,
            equipmentType: draft.equipmentType,
            deadheadMiles: draft.deadheadMiles,
            actualFinishDate: draft.actualFinishDate
        )
        applyDispute(to: load, draft: draft, previousRate: draft.totalRate, previousApplied: false, now: now)
        load.stops = draft.normalizedStops.map(Stop.init(draft:))
        load.refreshDerivedFields(week: week)

        try persist(load)
        PickupAlarmCenter.schedule(for: load)
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

        let previousRate = load.totalRate
        let previousApplied = load.disputeAmountApplied
        let previousCompleted = load.disputeCompleted
        let previousUpdated = load.updatedAt
        load.tripId = tripId
        load.date = draft.date
        load.totalMiles = draft.totalMiles
        load.actualFinishDate = draft.actualFinishDate
        load.equipmentType = draft.equipmentType
        load.deadheadMiles = draft.deadheadMiles
        load.isDispute = draft.isDispute
        load.disputeResponseDate = draft.disputeResponseDate
        applyDispute(
            to: load,
            draft: draft,
            previousRate: previousRate,
            previousApplied: previousApplied,
            previousCompleted: previousCompleted,
            previousUpdated: previousUpdated,
            now: Date()
        )

        load.stops = draft.normalizedStops.map(Stop.init(draft:))

        // parsedAt stays untouched — it is when the trip entered the journal, not when it was
        // last edited.
        load.touch()
        load.refreshDerivedFields(week: week)

        try persist(load)
        PickupAlarmCenter.schedule(for: load)
    }

    /// Applies Android `DisputePayout` using the rate that was already stored.
    private func applyDispute(
        to load: Load,
        draft: LoadDraft,
        previousRate: Double,
        previousApplied: Bool,
        previousCompleted: Bool = false,
        previousUpdated: Date = .distantPast,
        now: Date
    ) {
        let previous = DisputeSnapshot(
            totalRate: previousRate,
            disputeCompleted: previousCompleted,
            disputeApplyToLoad: load.disputeApplyToLoad,
            disputeAmountApplied: previousApplied,
            disputeAmount: load.disputeAmount,
            updatedAt: previousUpdated
        )
        let incoming = DisputeSnapshot(
            totalRate: draft.totalRate,
            disputeCompleted: draft.disputeCompleted,
            disputeApplyToLoad: draft.disputeApplyToLoad,
            disputeAmountApplied: draft.disputeAmountApplied,
            disputeAmount: draft.disputeAmount,
            updatedAt: now
        )
        // Edit saves are synchronous, same as Android `EditLoadViewModel.save`.
        // `DisputePayout.merge` is only for a stale in-flight dispute snapshot and would
        // throw away a normal rate change.
        let settled = DisputePayout.applyEdit(previous: previous, incoming: incoming)
        load.totalRate = settled.totalRate
        load.disputeCompleted = settled.disputeCompleted
        load.disputeApplyToLoad = settled.disputeApplyToLoad
        load.disputeAmountApplied = settled.disputeAmountApplied
        load.disputeAmount = settled.disputeAmount
    }

    func addPenalty(to load: Load, summary: String, amount: Double, date: Date) throws {
        let penalty = Penalty(summary: summary, amount: amount, date: date)
        penalty.load = load
        load.penalties = (load.penalties ?? []) + [penalty]
        load.touch()
        try persist(load)
    }

    func remove(_ penalty: Penalty) throws {
        let load = penalty.load
        if let load {
            load.penalties = (load.penalties ?? []).filter { $0.id != penalty.id }
            load.touch()
            try persist(load)
        }
    }

    // MARK: - Delete

    func delete(_ load: Load, mediaStore: MediaStore? = nil) throws {
        let removed = try database.delete(load)
        PickupAlarmCenter.cancel(loadID: load.id)
        if let mediaStore {
            for photo in removed.photos {
                mediaStore.delete(fileName: photo.fileName, filePath: photo.filePath, kind: .photo)
            }
            for scan in removed.scans {
                mediaStore.delete(fileName: scan.fileName, filePath: scan.filePath, kind: .scan)
            }
        }
        onDidSave?()
    }
}
