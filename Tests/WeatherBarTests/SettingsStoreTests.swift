import CoreLocation
import Foundation
import Testing
@testable import WeatherBar

@MainActor
struct SettingsStoreTests {
    private let suiteName = "WeatherBarTests.\(UUID().uuidString)"

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func saveAndLoadRoundTrip() {
        let defaults = makeDefaults()
        SettingsStore.defaults = defaults

        let location = CLLocation(latitude: 45.5152, longitude: -122.6784)
        let place = PlaceInfo(city: "Portland", state: "OR", timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        SettingsStore.saveManualLocation(query: "Portland, OR", location: location, place: place)

        #expect(SettingsStore.manualOverrideEnabled)
        #expect(SettingsStore.manualLocationQuery == "Portland, OR")

        let loaded = SettingsStore.loadManualLocation()
        #expect(loaded != nil)
        #expect(abs(loaded!.0.coordinate.latitude - 45.5152) < 0.0001)
        #expect(abs(loaded!.0.coordinate.longitude - (-122.6784)) < 0.0001)
        #expect(loaded!.1.city == "Portland")
        #expect(loaded!.1.state == "OR")
        #expect(loaded!.1.timeZone.identifier == "America/Los_Angeles")
    }

    @Test func clearManualLocationResetsFlag() {
        let defaults = makeDefaults()
        SettingsStore.defaults = defaults

        let location = CLLocation(latitude: 45.0, longitude: -122.0)
        let place = PlaceInfo(city: "Portland", state: "OR", timeZone: .current)
        SettingsStore.saveManualLocation(query: "Portland, OR", location: location, place: place)

        SettingsStore.clearManualLocation()

        #expect(!SettingsStore.manualOverrideEnabled)
        #expect(SettingsStore.loadManualLocation() == nil)
    }

    @Test func loadReturnsNilWhenDisabled() {
        let defaults = makeDefaults()
        SettingsStore.defaults = defaults
        SettingsStore.manualOverrideEnabled = false

        #expect(SettingsStore.loadManualLocation() == nil)
    }

    @Test func loadReturnsNilWhenKeysMissing() {
        let defaults = makeDefaults()
        SettingsStore.defaults = defaults
        SettingsStore.manualOverrideEnabled = true

        #expect(SettingsStore.loadManualLocation() == nil)
    }

    @Test func queryGetSet() {
        let defaults = makeDefaults()
        SettingsStore.defaults = defaults

        SettingsStore.manualLocationQuery = "Seattle, WA"
        #expect(SettingsStore.manualLocationQuery == "Seattle, WA")
    }
}
