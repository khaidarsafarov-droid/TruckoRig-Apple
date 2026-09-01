import Foundation

/// Where a load's rate per mile falls relative to the driver's thresholds.
public enum RPMBand: String, Sendable {
    case unknown
    case low
    case acceptable
    case good
}

/// Driver-configurable rate-per-mile bands. Defaults match the Android app.
public struct RPMThresholds: Equatable, Codable, Sendable {
    public var minProfit: Double
    public var targetProfit: Double

    public static let `default` = RPMThresholds(minProfit: 2.00, targetProfit: 2.50)

    public init(minProfit: Double = 2.00, targetProfit: Double = 2.50) {
        self.minProfit = minProfit
        self.targetProfit = targetProfit
    }

    /// `nil` when the pair is usable; otherwise the reason it is not.
    public var validationFailure: RPMThresholdError? {
        if minProfit < 0 || targetProfit < 0 { return .negative }
        if minProfit > targetProfit { return .outOfOrder }
        return nil
    }
}

public enum RPMThresholdError: Error, Equatable, Sendable {
    case negative
    case outOfOrder
}
