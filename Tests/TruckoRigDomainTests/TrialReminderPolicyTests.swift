import XCTest
@testable import TruckoRigDomain

final class TrialReminderPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    /// StoreKit said the free month ends on this instant. The policy must not move it.
    private let trialEnd = makeDate(2026, 2, 28, 0, 0, timeZone: TimeZone(secondsFromGMT: 0) ?? .current)

    func testTrialEndIsTheStoreKitDateUnchanged() {
        let renewal = makeDate(2026, 3, 28, 0, 0, timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        let facts = SubscriptionPeriodFacts(
            isEntitled: true,
            introductoryFreeTrial: true,
            transactionExpiration: trialEnd,
            renewalDate: renewal
        )
        XCTAssertEqual(StoreKitTrialEnd.date(from: facts), trialEnd)

        let onlyRenewal = SubscriptionPeriodFacts(
            isEntitled: true,
            introductoryFreeTrial: true,
            transactionExpiration: nil,
            renewalDate: renewal
        )
        XCTAssertEqual(StoreKitTrialEnd.date(from: onlyRenewal), renewal)

        let paid = SubscriptionPeriodFacts(
            isEntitled: true,
            introductoryFreeTrial: false,
            transactionExpiration: trialEnd,
            renewalDate: renewal
        )
        XCTAssertNil(StoreKitTrialEnd.date(from: paid))
        XCTAssertNil(StoreKitTrialEnd.date(from: SubscriptionPeriodFacts(
            isEntitled: true,
            introductoryFreeTrial: true,
            transactionExpiration: nil,
            renewalDate: nil
        )))
    }

    func testTriggerIsThreeDaysBeforeTheStoreKitEnd() {
        let trigger = TrialReminderPolicy.triggerDate(trialEnd: trialEnd)
        XCTAssertEqual(trigger.timeIntervalSince(trialEnd), -TrialReminderPolicy.lead)
        XCTAssertEqual(TrialReminderPolicy.lead, 3 * 24 * 60 * 60)
        let parts = calendar.dateComponents([.year, .month, .day], from: trigger)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 2)
        XCTAssertEqual(parts.day, 25)
    }

    func testReminderWindowIsTheThreeDaysBeforeTrialEnd() {
        let opens = TrialReminderPolicy.triggerDate(trialEnd: trialEnd)
        XCTAssertFalse(TrialReminderPolicy.inReminderWindow(now: opens.addingTimeInterval(-1), trialEnd: trialEnd))
        XCTAssertTrue(TrialReminderPolicy.inReminderWindow(now: opens, trialEnd: trialEnd))
        XCTAssertTrue(TrialReminderPolicy.inReminderWindow(now: trialEnd.addingTimeInterval(-1), trialEnd: trialEnd))
        XCTAssertFalse(TrialReminderPolicy.inReminderWindow(now: trialEnd, trialEnd: trialEnd))
    }

    func testBannerShowsOnlyInsideTheWindowWhilePremiumIsActive() {
        let inside = TrialReminderPolicy.decide(
            premiumActive: true,
            state: state(),
            now: trialEnd.addingTimeInterval(-24 * 60 * 60)
        )
        XCTAssertTrue(inside.onTrial)
        XCTAssertTrue(inside.showBanner)
        XCTAssertTrue(inside.postNotification)

        let tooEarly = TrialReminderPolicy.decide(
            premiumActive: true,
            state: state(),
            now: TrialReminderPolicy.triggerDate(trialEnd: trialEnd).addingTimeInterval(-1)
        )
        XCTAssertTrue(tooEarly.onTrial)
        XCTAssertFalse(tooEarly.showBanner)
        XCTAssertEqual(tooEarly.work, .enqueue)

        let inactive = TrialReminderPolicy.decide(
            premiumActive: false,
            state: state(),
            now: trialEnd.addingTimeInterval(-24 * 60 * 60)
        )
        XCTAssertFalse(inactive.onTrial)
        XCTAssertFalse(inactive.showBanner)
        XCTAssertFalse(inactive.postNotification)
        XCTAssertEqual(inactive.work, .cancel)
    }

    func testDismissHidesTheBannerAndLeavesTheNotification() {
        var dismissed = state()
        dismissed.bannerDismissed = true
        let decision = TrialReminderPolicy.decide(
            premiumActive: true,
            state: dismissed,
            now: trialEnd.addingTimeInterval(-24 * 60 * 60)
        )
        XCTAssertFalse(decision.showBanner)
        XCTAssertTrue(decision.postNotification)
    }

    func testNotificationIsOncePerPurchaseWhileTheTrialContinues() {
        let now = trialEnd.addingTimeInterval(-24 * 60 * 60)
        let first = TrialReminderPolicy.decide(premiumActive: true, state: state(), now: now)
        XCTAssertTrue(first.postNotification)

        var sent = state()
        sent.notificationSent = true
        let again = TrialReminderPolicy.decide(premiumActive: true, state: sent, now: now)
        XCTAssertFalse(again.postNotification)
        XCTAssertTrue(again.showBanner)
        XCTAssertEqual(again.work, .keep)
    }

    func testWorkIsCanceledWhenTheTrialOrSubscriptionEnds() {
        let expired = TrialReminderPolicy.decide(premiumActive: true, state: state(), now: trialEnd)
        XCTAssertFalse(expired.onTrial)
        XCTAssertEqual(expired.work, .cancel)

        let missing = TrialReminderPolicy.decide(
            premiumActive: true,
            state: TrialReminderState(),
            now: trialEnd.addingTimeInterval(-24 * 60 * 60)
        )
        XCTAssertEqual(missing.work, .cancel)
    }

    func testWorkStaysQueuedWhenTheTriggerIsUnchanged() {
        let trigger = TrialReminderPolicy.triggerDate(trialEnd: trialEnd)
        var queued = state()
        queued.scheduledFire = trigger
        let decision = TrialReminderPolicy.decide(
            premiumActive: true,
            state: queued,
            now: trialEnd.addingTimeInterval(-10 * 24 * 60 * 60)
        )
        XCTAssertEqual(decision.work, .keep)
        XCTAssertEqual(decision.triggerAt, trigger)
    }

    func testPriceFallsBackToTheUsCatalogPrice() {
        XCTAssertEqual(PremiumPolicy.usMonthlyPrice, "$2.99")
        XCTAssertEqual(PremiumPolicy.displayPrice(nil), "$2.99")
        XCTAssertEqual(PremiumPolicy.displayPrice("  "), "$2.99")
        XCTAssertEqual(PremiumPolicy.displayPrice(" 2,99 € "), "2,99 €")
    }

    func testFirstRunIsShownOnceBeforeAnySubscription() {
        XCTAssertTrue(PremiumPolicy.shouldPromptForSubscription(subscribed: false, offerAlreadyHandled: false))
        XCTAssertFalse(PremiumPolicy.shouldPromptForSubscription(subscribed: false, offerAlreadyHandled: true))
        XCTAssertFalse(PremiumPolicy.shouldPromptForSubscription(subscribed: true, offerAlreadyHandled: false))
    }

    private func state() -> TrialReminderState {
        TrialReminderState(
            purchaseID: "1001",
            trialEnd: trialEnd,
            formattedPrice: "$2.99"
        )
    }
}
