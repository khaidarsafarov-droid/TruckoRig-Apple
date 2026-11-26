import Foundation

/// The part of a load that a broker or shipper cancellation changes. Android `LoadCancellation`.
public struct LoadCancellationState: Equatable, Sendable {
    public var totalRate: Double
    public var totalMiles: Double
    public var deadheadMiles: Double
    public var isCancelled: Bool
    public var cancelledAt: Date?
    /// Rate before the cancellation, restored by undo. Nil while the load is active.
    public var originalRate: Double?
    /// Loaded miles before the cancellation, restored by undo. Nil while the load is active.
    public var originalMiles: Double?

    public init(
        totalRate: Double,
        totalMiles: Double,
        deadheadMiles: Double = 0,
        isCancelled: Bool = false,
        cancelledAt: Date? = nil,
        originalRate: Double? = nil,
        originalMiles: Double? = nil
    ) {
        self.totalRate = totalRate
        self.totalMiles = totalMiles
        self.deadheadMiles = deadheadMiles
        self.isCancelled = isCancelled
        self.cancelledAt = cancelledAt
        self.originalRate = originalRate
        self.originalMiles = originalMiles
    }

    /// TONU pay of a cancelled load; nil while the load is active.
    public var tonuAmount: Double? { isCancelled ? totalRate : nil }

    /// Loaded miles plus deadhead, same as `Load.drivenMiles`.
    public var drivenMiles: Double { totalMiles + max(0, deadheadMiles) }
}

/// Broker or shipper cancelled a booked load (TONU: truck ordered, not used).
///
/// The load stays in the journal. Its rate becomes the TONU pay the driver typed (0 when the
/// broker pays nothing), loaded miles become 0, and deadhead stays. The original rate and miles
/// are kept so `undo` restores the load exactly.
public enum LoadCancellation {

    /// Cancellations this close to pickup, or later, usually pay TONU.
    public static let tonuWindow: TimeInterval = 2 * 60 * 60

    /// Quick picks: Amazon Relay usually pays $175, many brokers $225. Any amount can be typed.
    public static let suggestedTonu: [Double] = [175, 225]

    /// Guards against a mistyped extra digit.
    public static let maxTonu: Double = 10_000

    /// Marks the load cancelled with `tonu` pay. On an already cancelled load only the TONU
    /// amount changes; the stored original rate and miles are kept.
    public static func cancel(_ state: LoadCancellationState, tonu: Double, now: Date) -> LoadCancellationState {
        let pay = max(0, MoneyCents.fromDollars(tonu).dollars)
        var next = state
        if !state.isCancelled {
            next.isCancelled = true
            next.cancelledAt = now
            next.originalRate = state.totalRate
            next.originalMiles = state.totalMiles
        }
        next.totalRate = pay
        next.totalMiles = 0
        return next
    }

    /// Restores the rate and loaded miles from before `cancel`. Deadhead is untouched.
    public static func undo(_ state: LoadCancellationState) -> LoadCancellationState {
        guard state.isCancelled else { return state }
        var next = state
        next.totalRate = state.originalRate ?? state.totalRate
        next.totalMiles = state.originalMiles ?? state.totalMiles
        next.isCancelled = false
        next.cancelledAt = nil
        next.originalRate = nil
        next.originalMiles = nil
        return next
    }

    /// True when the cancellation comes within two hours of pickup, or after it.
    /// An unknown pickup time returns false: the driver decides.
    public static func isWithinTonuWindow(pickup: Date?, now: Date) -> Bool {
        guard let pickup else { return false }
        return now >= pickup.addingTimeInterval(-tonuWindow)
    }

    /// Amount the TONU form starts with: the current TONU of a cancelled load, the first quick
    /// pick inside the TONU window, otherwise nothing.
    public static func suggestedAmount(for state: LoadCancellationState, pickup: Date?, now: Date) -> Double? {
        if state.isCancelled { return state.totalRate }
        if isWithinTonuWindow(pickup: pickup, now: now) { return suggestedTonu.first }
        return nil
    }

    /// 0 is allowed (cancelled without pay); negatives, NaN and absurd amounts are not.
    public static func isValidTonu(_ amount: Double?) -> Bool {
        guard let amount, amount.isFinite else { return false }
        return amount >= 0 && amount <= maxTonu
    }
}
