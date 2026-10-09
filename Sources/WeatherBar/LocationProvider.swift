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

    var currentAuthorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Requests authorization when needed and applies the current authorization state.
    /// Call after `onAuthorizationChanged` is wired so startup sync is not missed.
    func start() {
        let servicesEnabled = CLLocationManager.locationServicesEnabled()
        AppLogger.shared.log(
            "Starting location provider (system Location Services enabled: \(servicesEnabled), authorization: \(manager.authorizationStatus.diagnosticsName))"
        )
        if !servicesEnabled {
            AppLogger.shared.log(
                "System Location Services are OFF — enable the master switch in System Settings → Privacy & Security → Location Services",
                level: .warning
            )
        }
        applyAuthorizationStatus(manager.authorizationStatus)

        if manager.authorizationStatus == .notDetermined {
            AppLogger.shared.log("Requesting location permission (status stays notDetermined until the prompt is answered)")
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Re-shows the permission prompt if authorization is still undetermined
    /// (macOS will not re-prompt on its own once the sheet is dismissed).
    func requestAuthorizationIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        AppLogger.shared.log("Re-requesting location permission")
        manager.requestWhenInUseAuthorization()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        AppLogger.shared.log("Location authorization changed: \(status.diagnosticsName) (raw \(status.rawValue))")
        applyAuthorizationStatus(status)
    }

    private func applyAuthorizationStatus(_ status: CLAuthorizationStatus) {
        onAuthorizationChanged?(status)

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            AppLogger.shared.log("Location authorized (\(status.diagnosticsName)) — starting location updates")
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
        let ageSeconds = Int(max(0, -location.timestamp.timeIntervalSinceNow))
        AppLogger.shared.log(
            "Location fix: \(String(format: "%.4f", location.coordinate.latitude)), "
                + "\(String(format: "%.4f", location.coordinate.longitude)) "
                + "±\(Int(location.horizontalAccuracy))m (fix age \(ageSeconds)s)",
            level: .debug
        )
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            AppLogger.shared.log(
                "Location temporarily unknown (CLError.locationUnknown) — still waiting for a fix; "
                    + "Wi-Fi positioning may be slow or blocked (VPN/proxy can interfere with Apple's location servers)",
                level: .debug
            )
            return
        }

        AppLogger.shared.log("Location manager error: \(NetworkDiagnostics.describe(error))", level: .error)
        onError?(error)
    }
}
