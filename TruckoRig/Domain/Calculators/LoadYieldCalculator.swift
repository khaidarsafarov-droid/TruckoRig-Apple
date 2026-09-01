import Foundation

/// Per-load and per-week "dollars per day in transit" math.
///
/// Active days are always measured from the first pickup to the load's finish — either the
/// driver's `actualFinishAt` override or the last delivery — rounded up, never below one day.
public enum LoadYieldCalculator {

    private static let secondsPerDay: Double = 86_400

    /// End of the load: driver override when present, otherwise the last delivery.
    public static func finishDate(of load: LoadSummary) -> Date? {
        load.actualFinishAt ?? load.lastDeliveryAt
    }

    /// Whole days spent on a load, rounded up, minimum 1.
    public static func activeDurationDays(of load: LoadSummary) -> Double {
        guard let start = load.firstPickupAt, let end = finishDate(of: load) else { return 1 }
        let seconds = end.timeIntervalSince(start)
        guard seconds > 0 else { return 1 }
        return max(1, (seconds / secondsPerDay).rounded(.up))
    }

    /// Active days for a load that may not have its stops hydrated.
    ///
    /// Recomputes whenever schedule data is available and only falls back to the stored value
    /// for rows loaded without stops (list projections, cloud snapshots).
    public static func resolvedDurationDays(of load: LoadSummary) -> Double {
        if load.firstPickupAt != nil || load.actualFinishAt != nil {
            return activeDurationDays(of: load)
        }
        if load.storedDurationDays > 0 {
            return max(1, load.storedDurationDays)
        }
        return activeDurationDays(of: load)
    }

    /// Week pace: total gross divided by total days in transit.
    public static func actualDailyYield(_ loads: [LoadSummary]) -> Double {
        guard !loads.isEmpty else { return 0 }
        let gross = loads.reduce(0) { $0 + $1.totalRate }
        guard gross > 0 else { return 0 }
        let days = totalActiveDays(loads)
        guard days > 0 else { return 0 }
        return GoalMoneyMath.roundMoney(gross / days)
    }

    public static func totalActiveDays(_ loads: [LoadSummary]) -> Double {
        loads.reduce(0) { $0 + resolvedDurationDays(of: $1) }
    }

    /// Dollars per day for a single load.
    public static func pace(of load: LoadSummary) -> Double {
        let days = activeDurationDays(of: load)
        guard days > 0 else { return 0 }
        return GoalMoneyMath.roundMoney(load.totalRate / days)
    }
}
