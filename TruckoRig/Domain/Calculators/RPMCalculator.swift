import Foundation

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

/// Where a load's rate per mile falls relative to the driver's thresholds.
public enum RPMBand: String, Sendable {
    case unknown
    case low
    case acceptable
    case good
}

public enum RPMCalculator {

    /// Rate per mile; zero when miles are missing so the UI can show a dash instead of infinity.
    public static func ratePerMile(rate: Double, miles: Double) -> Double {
        guard miles > 0, rate.isFinite, miles.isFinite else { return 0 }
        return (rate / miles * 100).rounded() / 100
    }

    public static func ratePerMile(_ load: LoadSummary) -> Double {
        ratePerMile(rate: load.totalRate, miles: load.totalMiles)
    }

    public static func band(for rpm: Double, thresholds: RPMThresholds = .default) -> RPMBand {
        guard rpm > 0 else { return .unknown }
        if rpm >= thresholds.targetProfit { return .good }
        if rpm >= thresholds.minProfit { return .acceptable }
        return .low
    }

    public static func band(for load: LoadSummary, thresholds: RPMThresholds = .default) -> RPMBand {
        band(for: ratePerMile(load), thresholds: thresholds)
    }

    /// Fleet-level RPM: total gross over total miles, not an average of per-load RPMs.
    public static func aggregateRatePerMile(_ loads: [LoadSummary]) -> Double {
        let totals = LoadTotals.of(loads)
        return ratePerMile(rate: totals.totalRate, miles: totals.totalMiles)
    }
}
