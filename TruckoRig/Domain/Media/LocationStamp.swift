import Foundation

/// Geotag stored on a photo and drawn into the watermark.
///
/// Port of Android `LocationData`. Missing coordinates stay nil here; the database row
/// writes `0` for both axes, matching the non-null Room columns.
public struct LocationStamp: Equatable, Sendable {
    public var latitude: Double?
    public var longitude: Double?
    public var city: String
    public var state: String
    public var zipCode: String

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        city: String = "",
        state: String = "",
        zipCode: String = ""
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
        self.state = state
        self.zipCode = zipCode
    }

    public var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }

    public var cityStateLine: String {
        var line = ""
        if !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            line += city
        }
        if !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !line.isEmpty { line += ", " }
            line += state
        }
        if line.isEmpty { line += "—" }
        return line
    }

    public var coordinatesLine: String {
        guard let latitude, let longitude else { return "—" }
        return Self.formatCoordinates(latitude: latitude, longitude: longitude)
    }

    public static func formatCoordinates(latitude: Double, longitude: Double) -> String {
        let latitudeDirection = latitude >= 0 ? "N" : "S"
        let longitudeDirection = longitude >= 0 ? "E" : "W"
        return String(
            format: "%.3f° %@, %.3f° %@",
            locale: Locale(identifier: "en_US_POSIX"),
            abs(latitude),
            latitudeDirection,
            abs(longitude),
            longitudeDirection
        )
    }

    /// Values written into the photo row. Android stores `0.0` when the fix is missing.
    public var persistedLatitude: Double { latitude ?? 0 }
    public var persistedLongitude: Double { longitude ?? 0 }
}
