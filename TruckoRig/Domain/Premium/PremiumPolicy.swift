import Foundation

/// The App Store subscription. The free month is an introductory offer, not a timer in the app.
public enum PremiumPolicy {
    /// App Store product id. Same id the Android app uses in Play Console.
    public static let productID = "premium_monthly_subscription"

    /// Introductory offer. StoreKit reports it on the transaction; the app does not invent the end date.
    public static let freeMonthOfferID = "free-month"

    /// United States catalog price when StoreKit has not returned a localized price.
    public static let usMonthlyPrice = "$2.99"

    /// StoreKit's formatted price when it is present, otherwise the US catalog price.
    public static func displayPrice(_ storePrice: String?) -> String {
        let trimmed = storePrice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? usMonthlyPrice : trimmed
    }

    /// Ask once, before any purchase. Opening the app does not start the free month.
    public static func shouldPromptForSubscription(subscribed: Bool, offerAlreadyHandled: Bool) -> Bool {
        !subscribed && !offerAlreadyHandled
    }
}
