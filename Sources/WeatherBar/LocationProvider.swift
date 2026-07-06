import CoreLocation
import Foundation

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var onLocationUpdate: ((CLLocation) -> Void)?
    var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)?
    var onAuthorizationDenied: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 3000
    }

    /// Requests authorization when needed and applies the current authorization state.
    /// Call after `onAuthorizationChanged` is wired so startup sync is not missed.
    func start() {
        AppLogger.shared.log("Starting location provider")
        applyAuthorizationStatus(manager.authorizationStatus)

        if manager.authorizationStatus == .notDetermined {
            AppLogger.shared.log("Requesting location permission")
            manager.requestWhenInUseAuthorization()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        AppLogger.shared.log("Location authorization changed: \(status.rawValue)")
        applyAuthorizationStatus(status)
    }

    private func applyAuthorizationStatus(_ status: CLAuthorizationStatus) {
        onAuthorizationChanged?(status)

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.requestLocation()
        case .denied, .restricted:
            onAuthorizationDenied?()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            AppLogger.shared.log("Location temporarily unknown, waiting for fix", level: .debug)
            return
        }

        AppLogger.shared.log("Location manager error: \(error.localizedDescription)", level: .error)
        onError?(error)
    }
}
