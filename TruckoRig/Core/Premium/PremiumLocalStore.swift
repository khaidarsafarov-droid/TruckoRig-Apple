import Foundation

/// Local flags for the free-month reminder and the one-time first-launch offer.
///
/// The purchase id keys the notification and the dismissed banner. It does not unlock Premium.
final class PremiumLocalStore {
    static let suiteName = "com.truckorig.premium"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func standard() -> PremiumLocalStore {
        PremiumLocalStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
    }

    func read() -> TrialReminderState {
        let purchaseID = defaults.string(forKey: Key.purchaseID) ?? ""
        return TrialReminderState(
            purchaseID: purchaseID,
            trialEnd: date(Key.trialEnd),
            formattedPrice: defaults.string(forKey: Key.price)?.trimmed.nonEmpty,
            bannerDismissed: !purchaseID.isEmpty && tokens(Key.dismissed).contains(purchaseID),
            notificationSent: !purchaseID.isEmpty && tokens(Key.notified).contains(purchaseID),
            scheduledFire: date(Key.scheduled)
        )
    }

    func recordTrial(purchaseID: String, trialEnd: Date, price: String?) {
        guard !purchaseID.isEmpty else { return }
        let previousID = defaults.string(forKey: Key.purchaseID) ?? ""
        let previousEnd = date(Key.trialEnd)
        defaults.set(purchaseID, forKey: Key.purchaseID)
        defaults.set(trialEnd.timeIntervalSince1970, forKey: Key.trialEnd)
        if let price, !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(price, forKey: Key.price)
        }
        if previousID != purchaseID || previousEnd != trialEnd {
            defaults.removeObject(forKey: Key.scheduled)
        }
    }

    func markNotified(_ purchaseID: String) {
        guard !purchaseID.isEmpty else { return }
        addToken(Key.notified, purchaseID)
    }

    func dismissBanner(_ purchaseID: String) {
        guard !purchaseID.isEmpty else { return }
        addToken(Key.dismissed, purchaseID)
    }

    func markScheduled(_ date: Date?) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: Key.scheduled)
        } else {
            defaults.removeObject(forKey: Key.scheduled)
        }
    }

    /// Drops the active trial. Once-only flags for past purchase ids stay.
    func clearActiveTrial() {
        defaults.removeObject(forKey: Key.purchaseID)
        defaults.removeObject(forKey: Key.trialEnd)
        defaults.removeObject(forKey: Key.scheduled)
    }

    func wasOfferHandled() -> Bool {
        defaults.bool(forKey: Key.offerHandled)
    }

    func markOfferHandled() {
        defaults.set(true, forKey: Key.offerHandled)
    }

    private func date(_ key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let interval = defaults.double(forKey: key)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func tokens(_ key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private func addToken(_ key: String, _ token: String) {
        var next = tokens(key)
        next.insert(token)
        defaults.set(Array(next), forKey: key)
    }

    private enum Key {
        static let offerHandled = "offer_handled"
        static let purchaseID = "purchase_id"
        static let trialEnd = "trial_end"
        static let price = "formatted_price"
        static let scheduled = "scheduled_trigger"
        static let notified = "notified_purchase_ids"
        static let dismissed = "dismissed_purchase_ids"
    }
}
