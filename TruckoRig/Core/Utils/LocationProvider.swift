import CoreLocation
import Foundation
import Observation

/// One-shot location lookups for geotagging photos.
///
/// Deliberately not a continuous tracker: the app only needs where a photo was taken, and keeping
/// GPS running would cost battery on a driver's long day for no benefit.
@Observable
final class LocationProvider: NSObject {

    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<CLLocation?, Never>] = []

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastLocation: CLLocation?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestAuthorization() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Current location, or `nil` when permission is missing or the fix does not arrive.
    ///
    /// A photo without coordinates is still worth keeping, so this never throws or blocks capture.
    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
            manager.requestLocation()
        }
    }

    private func resume(with location: CLLocation?) {
        let pending = continuations
        continuations = []
        for continuation in pending {
            continuation.resume(returning: location)
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if !isAuthorized { resume(with: nil) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        resume(with: locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.media.notice("Location fix failed")
        resume(with: nil)
    }
}
