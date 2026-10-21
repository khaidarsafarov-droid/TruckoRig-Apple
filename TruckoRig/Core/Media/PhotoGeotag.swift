import CoreLocation

/// Reverse-geocodes a one-shot fix into the city, state and ZIP Android stores on the photo.
enum PhotoGeotag {

    static func stamp(for location: CLLocation?) async -> LocationStamp {
        guard let location else { return LocationStamp() }
        let placemark = await placemark(for: location)
        let city = placemark?.locality?.nonEmpty ?? placemark?.subAdministrativeArea ?? ""
        return LocationStamp(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            city: city,
            state: placemark?.administrativeArea ?? "",
            zipCode: placemark?.postalCode ?? ""
        )
    }

    private static func placemark(for location: CLLocation) async -> CLPlacemark? {
        let geocoder = CLGeocoder()
        return await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { marks, _ in
                continuation.resume(returning: marks?.first)
            }
        }
    }
}
