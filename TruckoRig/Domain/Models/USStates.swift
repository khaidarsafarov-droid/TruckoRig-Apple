import Foundation

/// US state reference data: name/abbreviation resolution plus approximate centroids used by the
/// state heatmap. Coordinates are geographic centres, accurate enough to place a map annotation.
public enum USStates {

    public struct StateInfo: Equatable, Sendable {
        public let code: String
        public let name: String
        public let latitude: Double
        public let longitude: Double
    }

    public static let all: [StateInfo] = [
        StateInfo(code: "AL", name: "Alabama", latitude: 32.806671, longitude: -86.791130),
        StateInfo(code: "AK", name: "Alaska", latitude: 61.370716, longitude: -152.404419),
        StateInfo(code: "AZ", name: "Arizona", latitude: 33.729759, longitude: -111.431221),
        StateInfo(code: "AR", name: "Arkansas", latitude: 34.969704, longitude: -92.373123),
        StateInfo(code: "CA", name: "California", latitude: 36.116203, longitude: -119.681564),
        StateInfo(code: "CO", name: "Colorado", latitude: 39.059811, longitude: -105.311104),
        StateInfo(code: "CT", name: "Connecticut", latitude: 41.597782, longitude: -72.755371),
        StateInfo(code: "DE", name: "Delaware", latitude: 39.318523, longitude: -75.507141),
        StateInfo(code: "DC", name: "District of Columbia", latitude: 38.897438, longitude: -77.026817),
        StateInfo(code: "FL", name: "Florida", latitude: 27.766279, longitude: -81.686783),
        StateInfo(code: "GA", name: "Georgia", latitude: 33.040619, longitude: -83.643074),
        StateInfo(code: "HI", name: "Hawaii", latitude: 21.094318, longitude: -157.498337),
        StateInfo(code: "ID", name: "Idaho", latitude: 44.240459, longitude: -114.478828),
        StateInfo(code: "IL", name: "Illinois", latitude: 40.349457, longitude: -88.986137),
        StateInfo(code: "IN", name: "Indiana", latitude: 39.849426, longitude: -86.258278),
        StateInfo(code: "IA", name: "Iowa", latitude: 42.011539, longitude: -93.210526),
        StateInfo(code: "KS", name: "Kansas", latitude: 38.526600, longitude: -96.726486),
        StateInfo(code: "KY", name: "Kentucky", latitude: 37.668140, longitude: -84.670067),
        StateInfo(code: "LA", name: "Louisiana", latitude: 31.169546, longitude: -91.867805),
        StateInfo(code: "ME", name: "Maine", latitude: 44.693947, longitude: -69.381927),
        StateInfo(code: "MD", name: "Maryland", latitude: 39.063946, longitude: -76.802101),
        StateInfo(code: "MA", name: "Massachusetts", latitude: 42.230171, longitude: -71.530106),
        StateInfo(code: "MI", name: "Michigan", latitude: 43.326618, longitude: -84.536095),
        StateInfo(code: "MN", name: "Minnesota", latitude: 45.694454, longitude: -93.900192),
        StateInfo(code: "MS", name: "Mississippi", latitude: 32.741646, longitude: -89.678696),
        StateInfo(code: "MO", name: "Missouri", latitude: 38.456085, longitude: -92.288368),
        StateInfo(code: "MT", name: "Montana", latitude: 46.921925, longitude: -110.454353),
        StateInfo(code: "NE", name: "Nebraska", latitude: 41.125370, longitude: -98.268082),
        StateInfo(code: "NV", name: "Nevada", latitude: 38.313515, longitude: -117.055374),
        StateInfo(code: "NH", name: "New Hampshire", latitude: 43.452492, longitude: -71.563896),
        StateInfo(code: "NJ", name: "New Jersey", latitude: 40.298904, longitude: -74.521011),
        StateInfo(code: "NM", name: "New Mexico", latitude: 34.840515, longitude: -106.248482),
        StateInfo(code: "NY", name: "New York", latitude: 42.165726, longitude: -74.948051),
        StateInfo(code: "NC", name: "North Carolina", latitude: 35.630066, longitude: -79.806419),
        StateInfo(code: "ND", name: "North Dakota", latitude: 47.528912, longitude: -99.784012),
        StateInfo(code: "OH", name: "Ohio", latitude: 40.388783, longitude: -82.764915),
        StateInfo(code: "OK", name: "Oklahoma", latitude: 35.565342, longitude: -96.928917),
        StateInfo(code: "OR", name: "Oregon", latitude: 44.572021, longitude: -122.070938),
        StateInfo(code: "PA", name: "Pennsylvania", latitude: 40.590752, longitude: -77.209755),
        StateInfo(code: "RI", name: "Rhode Island", latitude: 41.680893, longitude: -71.511780),
        StateInfo(code: "SC", name: "South Carolina", latitude: 33.856892, longitude: -80.945007),
        StateInfo(code: "SD", name: "South Dakota", latitude: 44.299782, longitude: -99.438828),
        StateInfo(code: "TN", name: "Tennessee", latitude: 35.747845, longitude: -86.692345),
        StateInfo(code: "TX", name: "Texas", latitude: 31.054487, longitude: -97.563461),
        StateInfo(code: "UT", name: "Utah", latitude: 40.150032, longitude: -111.862434),
        StateInfo(code: "VT", name: "Vermont", latitude: 44.045876, longitude: -72.710686),
        StateInfo(code: "VA", name: "Virginia", latitude: 37.769337, longitude: -78.169968),
        StateInfo(code: "WA", name: "Washington", latitude: 47.400902, longitude: -121.490494),
        StateInfo(code: "WV", name: "West Virginia", latitude: 38.491226, longitude: -80.954453),
        StateInfo(code: "WI", name: "Wisconsin", latitude: 44.268543, longitude: -89.616508),
        StateInfo(code: "WY", name: "Wyoming", latitude: 42.755966, longitude: -107.302490),
    ]

    private static let byCode: [String: StateInfo] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.code, $0) }
    )
    private static let byLowercasedName: [String: StateInfo] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.name.lowercased(), $0) }
    )

    public static func info(code: String) -> StateInfo? {
        byCode[code.uppercased()]
    }

    public static func name(code: String) -> String? {
        info(code: code)?.name
    }

    /// Accepts `"NC"` or `"North Carolina"` and returns the two-letter code.
    ///
    /// Unrecognised input is uppercased and returned as-is so foreign or malformed states still
    /// round-trip instead of being silently dropped.
    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count == 2 { return trimmed.uppercased() }
        return byLowercasedName[trimmed.lowercased()]?.code ?? trimmed.uppercased()
    }

    public static func isKnown(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return byCode[trimmed.uppercased()] != nil || byLowercasedName[trimmed.lowercased()] != nil
    }
}
