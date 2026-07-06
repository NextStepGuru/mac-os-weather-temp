import CoreLocation
import Foundation

@MainActor
enum SettingsStore {
    private enum Keys {
        static let manualLocationEnabled = "manualLocationEnabled"
        static let manualLocationQuery = "manualLocationQuery"
        static let manualLatitude = "manualLatitude"
        static let manualLongitude = "manualLongitude"
        static let manualCity = "manualCity"
        static let manualState = "manualState"
        static let manualTimeZoneIdentifier = "manualTimeZoneIdentifier"
    }

    static var defaults: UserDefaults = .standard

    static var manualOverrideEnabled: Bool {
        get { defaults.bool(forKey: Keys.manualLocationEnabled) }
        set { defaults.set(newValue, forKey: Keys.manualLocationEnabled) }
    }

    static var manualLocationQuery: String {
        get { defaults.string(forKey: Keys.manualLocationQuery) ?? "" }
        set { defaults.set(newValue, forKey: Keys.manualLocationQuery) }
    }

    static func saveManualLocation(query: String, location: CLLocation, place: PlaceInfo) {
        manualOverrideEnabled = true
        manualLocationQuery = query
        defaults.set(location.coordinate.latitude, forKey: Keys.manualLatitude)
        defaults.set(location.coordinate.longitude, forKey: Keys.manualLongitude)
        defaults.set(place.city, forKey: Keys.manualCity)
        defaults.set(place.state, forKey: Keys.manualState)
        defaults.set(place.timeZone.identifier, forKey: Keys.manualTimeZoneIdentifier)
    }

    static func clearManualLocation() {
        manualOverrideEnabled = false
        defaults.removeObject(forKey: Keys.manualLatitude)
        defaults.removeObject(forKey: Keys.manualLongitude)
        defaults.removeObject(forKey: Keys.manualCity)
        defaults.removeObject(forKey: Keys.manualState)
        defaults.removeObject(forKey: Keys.manualTimeZoneIdentifier)
    }

    static func loadManualLocation() -> (CLLocation, PlaceInfo)? {
        guard manualOverrideEnabled else { return nil }

        let latitude = defaults.double(forKey: Keys.manualLatitude)
        let longitude = defaults.double(forKey: Keys.manualLongitude)
        let city = defaults.string(forKey: Keys.manualCity)
        let state = defaults.string(forKey: Keys.manualState)
        let timeZoneID = defaults.string(forKey: Keys.manualTimeZoneIdentifier)

        guard let city, let state, let timeZoneID else { return nil }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        let timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let place = PlaceInfo(city: city, state: state, timeZone: timeZone)
        return (location, place)
    }
}
