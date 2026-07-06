import CoreLocation
import Foundation
import Testing
@testable import WeatherBar

struct AppStateLogicTests {
    private let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    private var fixedNow: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 1
        components.hour = 14
        components.minute = 30
        components.timeZone = timeZone
        return Calendar.current.date(from: components)!
    }

    private var fixedUpdated: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 1
        components.hour = 14
        components.minute = 15
        components.timeZone = timeZone
        return Calendar.current.date(from: components)!
    }

    private func portlandPlace() -> PlaceInfo {
        PlaceInfo(city: "Portland", state: "OR", timeZone: timeZone)
    }

    @Test func statusLineLoginErrorTakesPriority() {
        let input = StatusLineInput(
            loginItemError: "Login item failed: error",
            isGeocoding: true,
            placeInfo: portlandPlace(),
            location: nil,
            isManualOverride: false,
            isUsingIPFallback: false,
            lastUpdated: nil,
            isFetching: true,
            lastFetchFailed: true,
            now: fixedNow
        )
        #expect(StatusLineFormatter.format(input) == "Login item failed: error")
    }

    @Test func statusLineGeocoding() {
        let input = StatusLineInput(
            loginItemError: nil,
            isGeocoding: true,
            placeInfo: portlandPlace(),
            location: nil,
            isManualOverride: false,
            isUsingIPFallback: false,
            lastUpdated: nil,
            isFetching: false,
            lastFetchFailed: false,
            now: fixedNow
        )
        #expect(StatusLineFormatter.format(input) == "Looking up location…")
    }

    @Test func statusLineManualTag() {
        let input = StatusLineInput(
            loginItemError: nil,
            isGeocoding: false,
            placeInfo: portlandPlace(),
            location: nil,
            isManualOverride: true,
            isUsingIPFallback: false,
            lastUpdated: fixedUpdated,
            isFetching: false,
            lastFetchFailed: false,
            now: fixedNow
        )
        let result = StatusLineFormatter.format(input)!
        #expect(result.contains("Portland, OR"))
        #expect(result.contains(" · Manual"))
        #expect(result.contains(" · Updated "))
    }

    @Test func statusLineApproxIPTag() {
        let input = StatusLineInput(
            loginItemError: nil,
            isGeocoding: false,
            placeInfo: portlandPlace(),
            location: nil,
            isManualOverride: false,
            isUsingIPFallback: true,
            lastUpdated: nil,
            isFetching: true,
            lastFetchFailed: false,
            now: fixedNow
        )
        let result = StatusLineFormatter.format(input)!
        #expect(result.contains(" · Approx (IP)"))
        #expect(result.contains(" · Refreshing…"))
    }

    @Test func statusLineUpdateFailed() {
        let input = StatusLineInput(
            loginItemError: nil,
            isGeocoding: false,
            placeInfo: portlandPlace(),
            location: nil,
            isManualOverride: false,
            isUsingIPFallback: false,
            lastUpdated: fixedUpdated,
            isFetching: false,
            lastFetchFailed: true,
            now: fixedNow
        )
        let result = StatusLineFormatter.format(input)!
        #expect(result.contains(" · Update failed"))
    }

    @Test func statusLineCoordinateFallback() {
        let location = CLLocation(latitude: 45.5152, longitude: -122.6784)
        let input = StatusLineInput(
            loginItemError: nil,
            isGeocoding: false,
            placeInfo: nil,
            location: location,
            isManualOverride: false,
            isUsingIPFallback: false,
            lastUpdated: fixedUpdated,
            isFetching: false,
            lastFetchFailed: true,
            now: fixedNow
        )
        let result = StatusLineFormatter.format(input)!
        #expect(result.hasPrefix("Location: 45.5152, -122.6784"))
        #expect(result.contains(" · Update failed"))
    }

    @Test func statusLineRefreshingOnly() {
        let input = StatusLineInput(
            loginItemError: nil,
            isGeocoding: false,
            placeInfo: nil,
            location: nil,
            isManualOverride: false,
            isUsingIPFallback: false,
            lastUpdated: nil,
            isFetching: true,
            lastFetchFailed: false,
            now: fixedNow
        )
        #expect(StatusLineFormatter.format(input) == "Refreshing…")
    }

    @Test func statusLineNoUpdateWhenIdle() {
        let input = StatusLineInput(
            loginItemError: nil,
            isGeocoding: false,
            placeInfo: nil,
            location: nil,
            isManualOverride: false,
            isUsingIPFallback: false,
            lastUpdated: nil,
            isFetching: false,
            lastFetchFailed: false,
            now: fixedNow
        )
        #expect(StatusLineFormatter.format(input) == nil)
    }

    @Test func weatherDisplayShowsErrorWhenNoPriorTemp() {
        #expect(WeatherDisplayPolicy.menuBarTitleOnFetchFailure(lastTemperatureText: nil) == "!°")
    }

    @Test func weatherDisplayRetainsLastTempOnFailure() {
        #expect(WeatherDisplayPolicy.menuBarTitleOnFetchFailure(lastTemperatureText: "20°C / 68°F") == nil)
    }

    @Test func locationChangeDetectsMovementBeyondTolerance() {
        let from = CLLocation(latitude: 45.0, longitude: -122.0)
        let to = CLLocation(latitude: 45.02, longitude: -122.0)
        #expect(LocationChangeDetector.hasChanged(from: from, to: to, tolerance: 0.01))
    }

    @Test func locationChangeIgnoresMovementWithinTolerance() {
        let from = CLLocation(latitude: 45.0, longitude: -122.0)
        let to = CLLocation(latitude: 45.005, longitude: -122.005)
        #expect(!LocationChangeDetector.hasChanged(from: from, to: to, tolerance: 0.01))
    }

    @Test func locationChangeWhenNoPrevious() {
        let to = CLLocation(latitude: 45.0, longitude: -122.0)
        #expect(LocationChangeDetector.hasChanged(from: nil, to: to, tolerance: 0.01))
    }
}
