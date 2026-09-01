import Foundation

/// Rate-per-mile arithmetic.
public enum RPMCalculator {

    /// Rate per mile; zero when miles are missing so the UI can show a dash instead of infinity.
    public static func ratePerMile(rate: Double, miles: Double) -> Double {
        guard miles > 0, rate.isFinite, miles.isFinite else { return 0 }
        return (rate / miles * 100).rounded() / 100
    }

    public static func band(for rpm: Double, thresholds: RPMThresholds = .default) -> RPMBand {
        guard rpm > 0 else { return .unknown }
        if rpm >= thresholds.targetProfit { return .good }
        if rpm >= thresholds.minProfit { return .acceptable }
        return .low
    }
}
