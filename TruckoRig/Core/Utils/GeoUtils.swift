import CoreLocation
import Foundation
import MapKit

/// Geography helpers for the route map and the state heatmap.
enum GeoUtils {

    static func coordinate(forState code: String) -> CLLocationCoordinate2D? {
        guard let info = USStates.info(code: code) else { return nil }
        return CLLocationCoordinate2D(latitude: info.latitude, longitude: info.longitude)
    }

    /// Region that fits every coordinate with a little breathing room.
    ///
    /// Returns `nil` for an empty set so callers can show an empty state instead of a map centred
    /// on the Atlantic.
    static func region(fitting coordinates: [CLLocationCoordinate2D], paddingFactor: Double = 1.4) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max()
        else { return nil }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.5, (maxLat - minLat) * paddingFactor),
            longitudeDelta: max(0.5, (maxLon - minLon) * paddingFactor)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Great-circle distance in miles.
    static func miles(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let start = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let end = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return start.distance(from: end) / 1609.344
    }

    /// Geocodes a `"City, ST"` string. Used only when a stop has no coordinates of its own.
    static func geocode(cityState: String) async -> CLLocationCoordinate2D? {
        guard !cityState.trimmed.isEmpty else { return nil }
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.geocodeAddressString(cityState + ", USA")
        return placemarks?.first?.location?.coordinate
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
