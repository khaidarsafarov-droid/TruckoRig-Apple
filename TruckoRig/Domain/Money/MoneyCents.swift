import Foundation

/// Whole cents, matching Android `Money`.
///
/// Arithmetic stays on `Int64` so a rate added many times does not drift. Rounding is half away
/// from zero, the same direction as `kotlin.math.round` and Java `Math.round` for these values.
public struct MoneyCents: Equatable, Sendable, Comparable, Hashable {
    public var cents: Int64

    public init(cents: Int64) {
        self.cents = cents
    }

    public static let zero = MoneyCents(cents: 0)

    public var dollars: Double { Double(cents) / 100 }

    /// US dollar text with exactly two decimals and no thousands separator.
    /// Matches Android `Money.formatPlain`.
    public func formatPlain() -> String {
        let negative = cents < 0
        let absCents = abs(cents)
        let dollars = absCents / 100
        let fraction = String(format: "%02d", absCents % 100)
        return "\(negative ? "-" : "")\(dollars).\(fraction)"
    }

    public static func < (lhs: MoneyCents, rhs: MoneyCents) -> Bool {
        lhs.cents < rhs.cents
    }

    public static func + (lhs: MoneyCents, rhs: MoneyCents) -> MoneyCents {
        MoneyCents(cents: lhs.cents + rhs.cents)
    }

    public static func - (lhs: MoneyCents, rhs: MoneyCents) -> MoneyCents {
        MoneyCents(cents: lhs.cents - rhs.cents)
    }

    public func coerceAtLeast(_ minimum: MoneyCents) -> MoneyCents {
        self < minimum ? minimum : self
    }

    /// Scales by a factor such as 1.05 and rounds half-up to the nearest cent.
    public func scaledBy(_ factor: Double) -> MoneyCents {
        if factor == 0 || cents == 0 { return .zero }
        let scaled = (Double(cents) * factor).rounded(.toNearestOrAwayFromZero)
        return MoneyCents(cents: Int64(scaled))
    }

    public func dividedBy(_ divisor: Int) -> MoneyCents {
        if divisor == 0 { return .zero }
        let negative = (cents < 0) != (divisor < 0)
        let dividend = abs(cents)
        let divider = abs(Int64(divisor))
        let rounded = (dividend + divider / 2) / divider
        return MoneyCents(cents: negative ? -rounded : rounded)
    }

    /// Android `Money.fromDollars`: half-up to the nearest cent.
    public static func fromDollars(_ value: Double) -> MoneyCents {
        guard value.isFinite else { return .zero }
        let sign: Int64 = value < 0 ? -1 : 1
        let scaled = abs(value) * 100
        let cents = Int64((scaled + 1e-8).rounded(.toNearestOrAwayFromZero))
        return MoneyCents(cents: sign * cents)
    }
}
