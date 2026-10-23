import Foundation

/// Cents, matching Android `Money` for the map's rate math.
///
/// `fromDollars` rounds half away from zero. `scaledBy` does the same on `cents * factor`,
/// which is how Android rebuilds a lane's gross from RPM × miles.
public struct MapMoney: Equatable, Sendable {
    public var cents: Int64

    public static let zero = MapMoney(cents: 0)

    public init(cents: Int64) {
        self.cents = cents
    }

    public var isPositive: Bool { cents > 0 }

    public var dollars: Double { Double(cents) / 100 }

    public static func fromDollars(_ value: Double) -> MapMoney {
        guard value.isFinite else { return .zero }
        return MapMoney(cents: halfAwayFromZero(value * 100))
    }

    public static func fromCents(_ cents: Int64) -> MapMoney {
        MapMoney(cents: cents)
    }

    public func scaledBy(_ factor: Double) -> MapMoney {
        if factor == 0 || cents == 0 { return .zero }
        guard factor.isFinite else { return .zero }
        return MapMoney(cents: halfAwayFromZero(Double(cents) * factor))
    }
}

func sumMoney(_ amounts: [MapMoney]) -> MapMoney {
    MapMoney(cents: amounts.reduce(0) { $0 + $1.cents })
}

func halfAwayFromZero(_ value: Double) -> Int64 {
    guard value.isFinite else { return 0 }
    if value >= 0 { return Int64(floor(value + 0.5)) }
    return Int64(ceil(value - 0.5))
}
