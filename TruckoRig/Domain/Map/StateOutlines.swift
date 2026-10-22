import Foundation

/// One polygon ring drawn for a state. Multi-polygons (Alaska, Hawaii) are several of these.
public struct StatePolygon: Equatable, Sendable {
    public var stateCode: String
    public var outer: [MapCoordinate]
    public var holes: [[MapCoordinate]]
}

public struct MapCoordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
}

/// Fill and stroke for one ring. Colors are the Android `GeoJsonPolygonStyle` values.
public struct PaintedStatePolygon: Equatable, Sendable {
    public var stateCode: String
    public var outer: [MapCoordinate]
    public var holes: [[MapCoordinate]]
    public var fillHex: String
    public var strokeHex: String
    public var strokeWidth: Double
    public var zIndex: Int
}

public enum StateOutlineStyle {
    public static let good = "4ADE80"
    public static let bad = "F87171"
    public static let neutral = "FDE047"
    public static let noData = "E2E8F0"
    public static let border = "000000"
    public static let selected = "78838F"
    public static let strokeNormal = 2.0
    public static let strokeSelected = 5.0
}

/// GeoJSON `name` → postal code. Same table as Android `STATE_NAME_TO_ABBR`.
public enum StateGeoNames {
    public static let codeByName: [String: String] = [
        "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR",
        "California": "CA", "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE",
        "District of Columbia": "DC", "Florida": "FL", "Georgia": "GA", "Hawaii": "HI",
        "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA", "Kansas": "KS",
        "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME", "Maryland": "MD",
        "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS",
        "Missouri": "MO", "Montana": "MT", "Nebraska": "NE", "Nevada": "NV",
        "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY",
        "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK",
        "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC",
        "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX", "Utah": "UT",
        "Vermont": "VT", "Virginia": "VA", "Washington": "WA", "West Virginia": "WV",
        "Wisconsin": "WI", "Wyoming": "WY", "Puerto Rico": "PR",
    ]

    public static func code(forGeoJSONName name: String) -> String {
        codeByName[name] ?? name
    }
}

/// Parses the US state GeoJSON into rings the map can draw. A bad file yields nothing,
/// and the map still opens, matching Android's logged failure.
public enum StateOutlineParser {
    public static func rings(from geoJSON: Data) -> [StatePolygon] {
        guard let root = try? JSONSerialization.jsonObject(with: geoJSON) as? [String: Any],
              let features = root["features"] as? [Any]
        else { return [] }
        var polygons: [StatePolygon] = []
        for feature in features {
            guard let object = feature as? [String: Any] else { continue }
            let properties = object["properties"] as? [String: Any]
            let name = properties?["name"] as? String ?? ""
            let code = StateGeoNames.code(forGeoJSONName: name)
            guard let geometry = object["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String
            else { continue }
            switch type {
            case "Polygon":
                append(code: code, rings: geometry["coordinates"], to: &polygons)
            case "MultiPolygon":
                guard let parts = geometry["coordinates"] as? [Any] else { continue }
                for part in parts {
                    append(code: code, rings: part, to: &polygons)
                }
            default:
                continue
            }
        }
        return polygons
    }

    private static func append(code: String, rings: Any?, to polygons: inout [StatePolygon]) {
        guard let rings = rings as? [Any], !rings.isEmpty else { return }
        let paths = rings.map(coordinates(from:))
        let outer = paths.first ?? []
        guard outer.count >= 3 else { return }
        let holes = paths.dropFirst().filter { $0.count >= 3 }
        polygons.append(StatePolygon(stateCode: code, outer: outer, holes: holes))
    }

    /// GeoJSON positions are `[longitude, latitude]`.
    private static func coordinates(from value: Any) -> [MapCoordinate] {
        guard let points = value as? [Any] else { return [] }
        return points.compactMap { point in
            guard let pair = point as? [Any], pair.count >= 2 else { return nil }
            guard let longitude = number(pair[0]), let latitude = number(pair[1]) else { return nil }
            return MapCoordinate(latitude: latitude, longitude: longitude)
        }
    }

    private static func number(_ value: Any) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        return nil
    }
}

public enum StateHeatmapPainter {
    public static func paint(
        rings: [StatePolygon],
        metrics: [USStateMetric],
        selectedCode: String
    ) -> [PaintedStatePolygon] {
        let byCode = Dictionary(uniqueKeysWithValues: metrics.map { ($0.code, $0) })
        return rings.map { ring in
            let rating = byCode[ring.stateCode]?.rating ?? .noData
            let selected = !selectedCode.isEmpty && ring.stateCode == selectedCode
            return PaintedStatePolygon(
                stateCode: ring.stateCode,
                outer: ring.outer,
                holes: ring.holes,
                fillHex: fill(rating),
                strokeHex: selected ? StateOutlineStyle.selected : StateOutlineStyle.border,
                strokeWidth: selected ? StateOutlineStyle.strokeSelected : StateOutlineStyle.strokeNormal,
                zIndex: selected ? 10 : 0
            )
        }
    }

    public static func fill(_ rating: StateRating) -> String {
        switch rating {
        case .good: return StateOutlineStyle.good
        case .bad: return StateOutlineStyle.bad
        case .neutral: return StateOutlineStyle.neutral
        case .noData: return StateOutlineStyle.noData
        }
    }
}
