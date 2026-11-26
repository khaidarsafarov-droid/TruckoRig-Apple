import Foundation

extension Load {

    /// Fields a cancellation (TONU) reads and writes.
    var cancellationState: LoadCancellationState {
        LoadCancellationState(
            totalRate: totalRate,
            totalMiles: totalMiles,
            deadheadMiles: deadheadMiles,
            isCancelled: isCancelled,
            cancelledAt: cancelledAt,
            originalRate: originalRate,
            originalMiles: originalMiles
        )
    }

    func apply(_ state: LoadCancellationState) {
        totalRate = state.totalRate
        totalMiles = state.totalMiles
        deadheadMiles = state.deadheadMiles
        isCancelled = state.isCancelled
        cancelledAt = state.cancelledAt
        originalRate = state.originalRate
        originalMiles = state.originalMiles
    }

    /// TONU pay of a cancelled load; nil while the load is active.
    var tonuAmount: Double? { isCancelled ? totalRate : nil }

    /// Earliest scheduled pickup, used to suggest TONU when the cancellation is within two hours.
    var scheduledPickupAt: Date? {
        pickups.compactMap(\.scheduledTime).min() ?? firstPickupAt
    }
}
