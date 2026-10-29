import Foundation

/// The dispute fields that decide whether a claimed amount is added to the load rate.
///
/// Mirrors Android `DisputePayout`: completing a dispute can add the claim once, and turning the
/// dispute back off subtracts it so the rate does not stay inflated.
public struct DisputeSnapshot: Equatable, Sendable {
    public var totalRate: Double
    public var disputeCompleted: Bool
    public var disputeApplyToLoad: Bool
    public var disputeAmountApplied: Bool
    public var disputeAmount: Double?
    public var updatedAt: Date

    public init(
        totalRate: Double,
        disputeCompleted: Bool,
        disputeApplyToLoad: Bool,
        disputeAmountApplied: Bool,
        disputeAmount: Double?,
        updatedAt: Date
    ) {
        self.totalRate = totalRate
        self.disputeCompleted = disputeCompleted
        self.disputeApplyToLoad = disputeApplyToLoad
        self.disputeAmountApplied = disputeAmountApplied
        self.disputeAmount = disputeAmount
        self.updatedAt = updatedAt
    }
}

public enum DisputePayout {
    /// A stale in-flight save must not un-complete a dispute or roll the rate backwards.
    /// A newer snapshot that clears completion is the driver turning the dispute off.
    public static func merge(previous: DisputeSnapshot, incoming: DisputeSnapshot) -> DisputeSnapshot {
        if previous.disputeCompleted && !incoming.disputeCompleted {
            if incoming.updatedAt > previous.updatedAt {
                var copy = incoming
                copy.totalRate = previous.totalRate
                return copy
            }
            var copy = previous
            copy.disputeAmount = incoming.disputeAmount ?? previous.disputeAmount
            return copy
        }
        if previous.disputeCompleted {
            var copy = previous
            copy.disputeAmount = incoming.disputeAmount ?? previous.disputeAmount
            return copy
        }
        var copy = incoming
        copy.totalRate = previous.totalRate
        return copy
    }

    /// Journal edit. Android `EditLoadViewModel.save` calls `settleFrom` only.
    /// `merge` guards a stale detail-screen snapshot and must not run on this path:
    /// when the stored dispute is not completed it replaces the typed rate with the old one.
    public static func applyEdit(previous: DisputeSnapshot, incoming: DisputeSnapshot) -> DisputeSnapshot {
        settle(previous: previous, next: incoming)
    }

    public static func settle(previous: DisputeSnapshot, next: DisputeSnapshot) -> DisputeSnapshot {
        if !next.disputeCompleted {
            if previous.disputeAmountApplied {
                let amount = previous.disputeAmount ?? next.disputeAmount ?? 0
                var copy = next
                copy.totalRate = amount > 0 ? max(0, previous.totalRate - amount) : next.totalRate
                copy.disputeAmountApplied = false
                return copy
            }
            var copy = next
            copy.disputeAmountApplied = false
            return copy
        }
        if previous.disputeAmountApplied {
            var copy = next
            copy.disputeAmountApplied = true
            return copy
        }
        let amount = next.disputeAmount ?? 0
        if !next.disputeApplyToLoad || amount <= 0 {
            var copy = next
            copy.disputeAmountApplied = false
            return copy
        }
        var copy = next
        copy.totalRate = next.totalRate + amount
        copy.disputeAmountApplied = true
        return copy
    }
}
