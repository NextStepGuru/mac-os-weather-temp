import Foundation
import Testing
@testable import WeatherBar

struct PlaceInfoTests {
    @Test func displayName() {
        let place = PlaceInfo(city: "Portland", state: "OR", timeZone: .current)
        #expect(place.displayName == "Portland, OR")
    }

    @Test func formatTime() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let place = PlaceInfo(city: "Portland", state: "OR", timeZone: timeZone)

        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 25
        components.hour = 14
        components.minute = 30
        components.timeZone = timeZone
        let date = Calendar.current.date(from: components)!

        let formatted = place.formatTime(date)
        #expect(formatted.contains("2:30") || formatted.contains("14:30"))
    }

    @Test func timeZoneAbbreviation() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let place = PlaceInfo(city: "Portland", state: "OR", timeZone: timeZone)

        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 1
        components.timeZone = timeZone
        let date = Calendar.current.date(from: components)!

        let abbreviation = place.timeZoneAbbreviation(for: date)
        #expect(abbreviation == "PDT" || abbreviation == "America/Los_Angeles")
    }
}

struct GeocodingServiceTests {
    @Test func resolvePlaceUsesLocalityFirst() {
        let place = GeocodingService.resolvePlace(
            locality: "Portland",
            subAdministrativeArea: "Multnomah",
            name: "Downtown",
            administrativeArea: "OR",
            timeZone: TimeZone(identifier: "America/Los_Angeles")
        )
        #expect(place.city == "Portland")
        #expect(place.state == "OR")
    }

    @Test func resolvePlaceFallsBackToSubAdministrativeArea() {
        let place = GeocodingService.resolvePlace(
            locality: nil,
            subAdministrativeArea: "Multnomah",
            name: "Downtown",
            administrativeArea: "OR",
            timeZone: nil
        )
        #expect(place.city == "Multnomah")
    }

    @Test func resolvePlaceFallsBackToName() {
        let place = GeocodingService.resolvePlace(
            locality: nil,
            subAdministrativeArea: nil,
            name: "Downtown",
            administrativeArea: "OR",
            timeZone: nil
        )
        #expect(place.city == "Downtown")
    }

    @Test func resolvePlaceDefaultsToUnknown() {
        let place = GeocodingService.resolvePlace(
            locality: nil,
            subAdministrativeArea: nil,
            name: nil,
            administrativeArea: nil,
            timeZone: nil
        )
        #expect(place.city == "Unknown")
        #expect(place.state == "Unknown")
    }

    @Test func forwardGeocodeEmptyStringThrows() async {
        let service = GeocodingService()

        await #expect(throws: GeocodingError.invalidAddress) {
            try await service.forwardGeocode(address: "")
        }
    }

    @Test func forwardGeocodeWhitespaceThrows() async {
        let service = GeocodingService()

        await #expect(throws: GeocodingError.invalidAddress) {
            try await service.forwardGeocode(address: "   ")
        }
    }

    @Test func geocodingErrorDescriptions() {
        #expect(GeocodingError.noResults.errorDescription == "No location results found")
        #expect(GeocodingError.invalidAddress.errorDescription == "Please enter a place name or address")
    }
}
