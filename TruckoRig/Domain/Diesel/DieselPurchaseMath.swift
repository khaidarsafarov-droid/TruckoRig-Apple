import Foundation

/// Pure diesel fill math: paid total and discount savings from gallons plus prices.
///
/// Example: 500 gal @ $5.10 list / $4.09 discount → paid $2,045, saved $505.
public enum DieselPurchaseMath {

    /// Gallons times the price actually paid. Discount wins when it is present and positive.
    public static func paidTotal(gallons: Double?, pricePerGallon: Double?, discountPricePerGallon: Double?) -> Double? {
        guard let gallons, gallons > 0 else { return nil }
        let paidPrice: Double
        if let discountPricePerGallon, discountPricePerGallon > 0 {
            paidPrice = discountPricePerGallon
        } else if let pricePerGallon, pricePerGallon > 0 {
            paidPrice = pricePerGallon
        } else {
            return nil
        }
        return paidPrice * gallons
    }

    /// Dollars saved versus list price. Zero when the discount is not actually lower.
    public static func savings(gallons: Double?, pricePerGallon: Double?, discountPricePerGallon: Double?) -> Double? {
        guard let gallons, gallons > 0,
              let list = pricePerGallon, list > 0,
              let discount = discountPricePerGallon, discount > 0
        else { return nil }
        let gap = list - discount
        if gap <= 0 { return 0 }
        return gap * gallons
    }
}

/// What the diesel form rejects before it writes a row. Strings live in the UI layer.
public enum DieselFormError: Equatable, Sendable {
    case gallons
    case price
    case discountInvalid
    case discountAbovePrice
    case amount
}

public enum DieselFormValidation {

    public static func validate(
        gallonsText: String,
        priceText: String,
        discountText: String
    ) -> DieselFormError? {
        let gallons = DecimalInput.parse(gallonsText).flatMap { $0 > 0 ? $0 : nil }
        if gallons == nil { return .gallons }
        let price = DecimalInput.parse(priceText).flatMap { $0 > 0 ? $0 : nil }
        if price == nil { return .price }
        let discountRaw = discountText.trimmingCharacters(in: .whitespacesAndNewlines)
        let discount = DecimalInput.parse(discountRaw).flatMap { $0 > 0 ? $0 : nil }
        if !discountRaw.isEmpty && discount == nil { return .discountInvalid }
        if let discount, let price, discount > price { return .discountAbovePrice }
        if DieselPurchaseMath.paidTotal(gallons: gallons, pricePerGallon: price, discountPricePerGallon: discount) == nil {
            return .amount
        }
        return nil
    }
}
