import Foundation

/// What StoreKit already reported about the current subscription period.
///
/// `transactionExpiration` is `Transaction.expirationDate`. `renewalDate` is
/// `Product.SubscriptionInfo.RenewalInfo.renewalDate`. Neither value is derived here.
public struct SubscriptionPeriodFacts: Equatable, Sendable {
    public var isEntitled: Bool
    public var introductoryFreeTrial: Bool
    public var transactionExpiration: Date?
    public var renewalDate: Date?

    public init(
        isEntitled: Bool,
        introductoryFreeTrial: Bool,
        transactionExpiration: Date?,
        renewalDate: Date?
    ) {
        self.isEntitled = isEntitled
        self.introductoryFreeTrial = introductoryFreeTrial
        self.transactionExpiration = transactionExpiration
        self.renewalDate = renewalDate
    }
}

/// The free-month end StoreKit reported. A missing date stays missing — nothing is added locally.
public enum StoreKitTrialEnd {
    public static func date(from facts: SubscriptionPeriodFacts) -> Date? {
        guard facts.introductoryFreeTrial else { return nil }
        return facts.transactionExpiration ?? facts.renewalDate
    }
}

/// Local reminder bookkeeping. The purchase id only keys the one notification and the dismissed banner.
public struct TrialReminderState: Equatable, Sendable {
    public var purchaseID: String
    public var trialEnd: Date?
    public var formattedPrice: String?
    public var bannerDismissed: Bool
    public var notificationSent: Bool
    public var scheduledFire: Date?

    public init(
        purchaseID: String = "",
        trialEnd: Date? = nil,
        formattedPrice: String? = nil,
        bannerDismissed: Bool = false,
        notificationSent: Bool = false,
        scheduledFire: Date? = nil
    ) {
        self.purchaseID = purchaseID
        self.trialEnd = trialEnd
        self.formattedPrice = formattedPrice
        self.bannerDismissed = bannerDismissed
        self.notificationSent = notificationSent
        self.scheduledFire = scheduledFire
    }
}

public enum TrialWorkAction: Equatable, Sendable {
    /// Remove the pending notification. Used when the trial or the subscription is over.
    case cancel
    /// Submit the one calendar notification.
    case enqueue
    /// The pending notification is already the right one, or it was already submitted.
    case keep
}

public struct TrialReminderDecision: Equatable, Sendable {
    public var onTrial: Bool
    public var showBanner: Bool
    public var postNotification: Bool
    public var work: TrialWorkAction
    public var triggerAt: Date?

    public init(
        onTrial: Bool,
        showBanner: Bool,
        postNotification: Bool,
        work: TrialWorkAction,
        triggerAt: Date?
    ) {
        self.onTrial = onTrial
        self.showBanner = showBanner
        self.postNotification = postNotification
        self.work = work
        self.triggerAt = triggerAt
    }
}

/// Three days before the free month ends, while Premium is still active.
public enum TrialReminderPolicy {
    public static let lead: TimeInterval = 3 * 24 * 60 * 60

    /// Inclusive of the instant three days before `trialEnd`, exclusive of the end.
    public static func inReminderWindow(now: Date, trialEnd: Date) -> Bool {
        let opens = triggerDate(trialEnd: trialEnd)
        return now >= opens && now < trialEnd
    }

    public static func triggerDate(trialEnd: Date) -> Date {
        trialEnd.addingTimeInterval(-lead)
    }

    public static func decide(
        premiumActive: Bool,
        state: TrialReminderState,
        now: Date
    ) -> TrialReminderDecision {
        let hasRecord = !state.purchaseID.isEmpty && state.trialEnd != nil
        let end = state.trialEnd
        let onTrial = premiumActive && hasRecord && now < end!
        let inWindow = onTrial && inReminderWindow(now: now, trialEnd: end!)
        let trigger = hasRecord ? triggerDate(trialEnd: end!) : nil
        let alreadyQueued = trigger != nil && state.scheduledFire == trigger
        let work: TrialWorkAction
        if !onTrial {
            work = .cancel
        } else if state.notificationSent || alreadyQueued {
            // Already submitted. Removing it here would delete the notification before iOS delivers it.
            work = .keep
        } else {
            work = .enqueue
        }
        return TrialReminderDecision(
            onTrial: onTrial,
            showBanner: inWindow && !state.bannerDismissed,
            postNotification: inWindow && !state.notificationSent,
            work: work,
            triggerAt: onTrial ? trigger : nil
        )
    }
}
