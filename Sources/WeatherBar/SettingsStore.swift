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
        static let lastGPSLatitude = "lastGPSLatitude"
        static let lastGPSLongitude = "lastGPSLongitude"
        static let lastGPSCity = "lastGPSCity"
        static let lastGPSState = "lastGPSState"
        static let lastGPSTimeZoneIdentifier = "lastGPSTimeZoneIdentifier"
        static let lastGPSCachedAt = "lastGPSCachedAt"
    }

    /// How long a cached GPS fix stays trustworthy as a fallback. Beyond this the
    /// device may have traveled, so a stale fix would report the wrong city — but
    /// even a stale fix beats the VPN egress city IP geolocation would produce.
    static let lastGPSFixMaxAge: TimeInterval = 30 * 24 * 60 * 60

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

    /// Caches the most recent GPS fix so a later launch without GPS (e.g. VPN
    /// blocking Wi-Fi positioning) can still show a plausible local location
    /// instead of falling back to VPN-egress IP geolocation.
    static func saveLastGPSFix(location: CLLocation, place: PlaceInfo, at date: Date = Date()) {
        defaults.set(location.coordinate.latitude, forKey: Keys.lastGPSLatitude)
        defaults.set(location.coordinate.longitude, forKey: Keys.lastGPSLongitude)
        defaults.set(place.city, forKey: Keys.lastGPSCity)
        defaults.set(place.state, forKey: Keys.lastGPSState)
        defaults.set(place.timeZone.identifier, forKey: Keys.lastGPSTimeZoneIdentifier)
        defaults.set(date, forKey: Keys.lastGPSCachedAt)
    }

    /// Returns the cached GPS fix, or nil when missing or older than `maxAge`.
    /// Stale entries are cleared so they can never resurface.
    static func loadLastGPSFix(now: Date = Date(), maxAge: TimeInterval = lastGPSFixMaxAge) -> (CLLocation, PlaceInfo)? {
        let latitude = defaults.double(forKey: Keys.lastGPSLatitude)
        let longitude = defaults.double(forKey: Keys.lastGPSLongitude)
        let city = defaults.string(forKey: Keys.lastGPSCity)
        let state = defaults.string(forKey: Keys.lastGPSState)
        let timeZoneID = defaults.string(forKey: Keys.lastGPSTimeZoneIdentifier)
        let cachedAt = defaults.object(forKey: Keys.lastGPSCachedAt) as? Date

        guard let city, let state, let timeZoneID, let cachedAt else { return nil }

        guard now.timeIntervalSince(cachedAt) <= maxAge else {
            clearLastGPSFix()
            return nil
        }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        let timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let place = PlaceInfo(city: city, state: state, timeZone: timeZone)
        return (location, place)
    }

    static func clearLastGPSFix() {
        defaults.removeObject(forKey: Keys.lastGPSLatitude)
        defaults.removeObject(forKey: Keys.lastGPSLongitude)
        defaults.removeObject(forKey: Keys.lastGPSCity)
        defaults.removeObject(forKey: Keys.lastGPSState)
        defaults.removeObject(forKey: Keys.lastGPSTimeZoneIdentifier)
        defaults.removeObject(forKey: Keys.lastGPSCachedAt)
    }
}
