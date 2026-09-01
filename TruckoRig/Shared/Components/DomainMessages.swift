import Foundation

/// Localized text for domain verdicts.
///
/// The domain layer stays free of Foundation localization so it can be tested on its own; the
/// mapping to a user-facing sentence lives here, where the keys are checked at compile time.
extension RelayParseFailure {
    var localizedMessage: String {
        switch self {
        case .notLoadLike: return String(localized: "relay.error.notLoadLike")
        case .missingTripId: return String(localized: "relay.error.missingTripId")
        case .missingRate: return String(localized: "relay.error.missingRate")
        case .missingAddress: return String(localized: "relay.error.missingAddress")
        }
    }
}

extension LoadDraft.ValidationError {
    var localizedMessage: String {
        switch self {
        case .missingTripId: return String(localized: "load.error.tripId")
        case .nonPositiveRate: return String(localized: "load.error.rate")
        case .negativeMiles: return String(localized: "load.error.miles")
        case .finishBeforeStart: return String(localized: "load.error.finishDate")
        }
    }
}

extension RPMThresholdError {
    var localizedMessage: String {
        switch self {
        case .negative: return String(localized: "settings.rpm.error.negative")
        case .outOfOrder: return String(localized: "settings.rpm.error.order")
        }
    }
}
