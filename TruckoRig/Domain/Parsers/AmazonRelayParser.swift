import Foundation

/// Why a paste could not be turned into a load.
public enum RelayParseFailure: Error, Equatable, Sendable {
    case notLoadLike
    case missingTripId
    case missingRate
    case missingAddress
}

/// A parsed trip plus the derived numbers the goal math needs.
public struct RelayParseResult: Equatable, Sendable {
    public var load: ParsedLoad
    public var durationDays: Double
    public var firstPickupAt: Date?
    public var lastDeliveryAt: Date?

    public var tripId: String { load.tripId }
    public var totalRate: Double { load.totalRate }
    public var totalMiles: Double { load.totalMiles }
    public var ratePerMile: Double {
        RPMCalculator.ratePerMile(rate: load.totalRate, miles: load.totalMiles)
    }
}

/// Entry point for "paste from Relay".
///
/// A trip is only accepted when it carries a Trip ID, a positive Total Rate and at least one
/// pickup or delivery address; anything else comes back as a typed failure so the UI can explain
/// what was missing instead of silently importing an empty row.
public enum AmazonRelayParser {

    public static func parse(
        _ text: String,
        reference: Date = Date(),
        timeZone: TimeZone = .current
    ) -> Result<RelayParseResult, RelayParseFailure> {
        let results = parseAll(text, reference: reference, timeZone: timeZone)
        if let first = results.first { return .success(first) }
        return .failure(diagnose(text))
    }

    public static func parseAll(
        _ text: String,
        reference: Date = Date(),
        timeZone: TimeZone = .current
    ) -> [RelayParseResult] {
        LoadMessageParser.parseAll(text, reference: reference, timeZone: timeZone).map(makeResult)
    }

    private static func makeResult(_ load: ParsedLoad) -> RelayParseResult {
        let summary = LoadSummary(
            tripId: load.tripId,
            totalRate: load.totalRate,
            totalMiles: load.totalMiles,
            firstPickupAt: load.firstPickupAt,
            lastDeliveryAt: load.lastDeliveryAt
        )
        return RelayParseResult(
            load: load,
            durationDays: LoadYieldCalculator.activeDurationDays(of: summary),
            firstPickupAt: load.firstPickupAt,
            lastDeliveryAt: load.lastDeliveryAt
        )
    }

    /// Works out which requirement the text failed, so the driver gets a specific message.
    static func diagnose(_ text: String) -> RelayParseFailure {
        let normalized = StyledTextNormalizer.normalize(
            text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard MessageClassifier.isLoadLike(normalized) else { return .notLoadLike }
        guard Rx.firstCapture(in: normalized, patterns: LoadMessageParser.tripIdPatterns) != nil else {
            return .missingTripId
        }
        let rate = LoadMessageParser.totalRatePattern.firstMatch(in: normalized)?.group(1)
            ?? LoadMessageParser.inlineRatePattern.firstMatch(in: normalized)?.group(1)
        guard let rate, NumberParsing.parseMoney(rate) > 0 else { return .missingRate }
        return .missingAddress
    }
}
