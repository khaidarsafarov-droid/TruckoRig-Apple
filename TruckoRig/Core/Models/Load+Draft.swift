import Foundation

extension LoadDraft {
    /// Form state for an existing load.
    init(load: Load) {
        self.init(
            tripId: load.tripId,
            date: load.date,
            totalRate: load.totalRate,
            totalMiles: load.totalMiles,
            stops: load.sortedStops.map(\.draft),
            actualFinishDate: load.actualFinishDate,
            isDispute: load.isDispute,
            disputeCompleted: load.disputeCompleted,
            disputeResponseDate: load.disputeResponseDate,
            disputeAmount: load.disputeAmount,
            disputeApplyToLoad: load.disputeApplyToLoad,
            disputeAmountApplied: load.disputeAmountApplied,
            equipmentType: load.equipmentType,
            deadheadMiles: load.deadheadMiles,
            rawMessage: load.rawMessage
        )
    }
}
