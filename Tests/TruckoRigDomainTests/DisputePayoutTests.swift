import XCTest
@testable import TruckoRigDomain

final class DisputePayoutTests: XCTestCase {

    private func snapshot(
        rate: Double,
        completed: Bool = false,
        apply: Bool = false,
        applied: Bool = false,
        amount: Double? = nil,
        updated: TimeInterval = 0
    ) -> DisputeSnapshot {
        DisputeSnapshot(
            totalRate: rate,
            disputeCompleted: completed,
            disputeApplyToLoad: apply,
            disputeAmountApplied: applied,
            disputeAmount: amount,
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    func testCompletingAddsTheClaimOnce() {
        let previous = snapshot(rate: 2500)
        let incoming = snapshot(rate: 2500, completed: true, apply: true, amount: 200, updated: 10)
        let merged = DisputePayout.merge(previous: previous, incoming: incoming)
        let settled = DisputePayout.settle(previous: previous, next: merged)

        XCTAssertEqual(settled.totalRate, 2700, accuracy: 0.001)
        XCTAssertTrue(settled.disputeAmountApplied)
    }

    func testSecondSaveDoesNotAddAgain() {
        let previous = snapshot(rate: 2700, completed: true, apply: true, applied: true, amount: 200, updated: 10)
        let incoming = snapshot(rate: 2700, completed: true, apply: true, amount: 200, updated: 20)
        let merged = DisputePayout.merge(previous: previous, incoming: incoming)
        let settled = DisputePayout.settle(previous: previous, next: merged)

        XCTAssertEqual(settled.totalRate, 2700, accuracy: 0.001)
        XCTAssertTrue(settled.disputeAmountApplied)
    }

    func testTurningTheDisputeOffRemovesTheClaim() {
        let previous = snapshot(rate: 2700, completed: true, apply: true, applied: true, amount: 200, updated: 10)
        let incoming = snapshot(rate: 2700, completed: false, apply: false, amount: 200, updated: 20)
        let merged = DisputePayout.merge(previous: previous, incoming: incoming)
        let settled = DisputePayout.settle(previous: previous, next: merged)

        XCTAssertEqual(settled.totalRate, 2500, accuracy: 0.001)
        XCTAssertFalse(settled.disputeAmountApplied)
    }
}
