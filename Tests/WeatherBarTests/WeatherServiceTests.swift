import Foundation
import Testing
@testable import WeatherBar

struct WeatherServiceTests {
    @Test func formatTemperaturePositive() {
        #expect(WeatherService.formatTemperature(celsius: 25.0) == "25°C / 77°F")
    }

    @Test func formatTemperatureZero() {
        #expect(WeatherService.formatTemperature(celsius: 0.0) == "0°C / 32°F")
    }

    @Test func formatTemperatureNegative() {
        #expect(WeatherService.formatTemperature(celsius: -10.4) == "-10°C / 13°F")
    }

    @Test func shouldRetryOnTimeout() {
        #expect(WeatherService.shouldRetry(URLError(.timedOut)))
    }

    @Test func shouldRetryOnConnectionLost() {
        #expect(WeatherService.shouldRetry(URLError(.networkConnectionLost)))
    }

    @Test func shouldRetryOnNotConnected() {
        #expect(WeatherService.shouldRetry(URLError(.notConnectedToInternet)))
    }

    @Test func shouldRetryOnCannotConnect() {
        #expect(WeatherService.shouldRetry(URLError(.cannotConnectToHost)))
    }

    @Test func shouldNotRetryOnBadServerResponse() {
        #expect(!WeatherService.shouldRetry(URLError(.badServerResponse)))
    }

    @Test func shouldNotRetryOnNonURLError() {
        #expect(!WeatherService.shouldRetry(NSError(domain: "test", code: 1)))
    }

    @Test func nwsSuccessFahrenheit() async throws {
        let session = MockURLProtocol.makeSession { request in
            if request.url?.host == "api.weather.gov", request.url?.path.contains("/points/") == true {
                return MockURLProtocol.jsonResponse(body: Fixtures.nwsPoints)
            }
            return MockURLProtocol.jsonResponse(body: Fixtures.nwsHourly(temperature: 61, unit: "F"))
        }

        let service = WeatherService(session: session, retryDelayNanoseconds: 1)
        let celsius = try await service.currentTemperatureC(latitude: 42.4295, longitude: -124.4017)
        #expect(abs(celsius - 16.111) < 0.1)
    }

    @Test func nwsSuccessCelsius() async throws {
        let session = MockURLProtocol.makeSession { request in
            if request.url?.host == "api.weather.gov", request.url?.path.contains("/points/") == true {
                return MockURLProtocol.jsonResponse(body: Fixtures.nwsPoints)
            }
            return MockURLProtocol.jsonResponse(body: Fixtures.nwsHourly(temperature: 20, unit: "C"))
        }

        let service = WeatherService(session: session, retryDelayNanoseconds: 1)
        let celsius = try await service.currentTemperatureC(latitude: 42.4295, longitude: -124.4017)
        #expect(celsius == 20)
    }

    @Test func nwsEmptyPeriodsThrows() async {
        let session = MockURLProtocol.makeSession { request in
            if request.url?.host == "api.weather.gov", request.url?.path.contains("/points/") == true {
                return MockURLProtocol.jsonResponse(body: Fixtures.nwsPoints)
            }
            if request.url?.host == "api.weather.gov" {
                return MockURLProtocol.jsonResponse(body: Fixtures.nwsHourlyEmpty)
            }
            throw URLError(.cannotConnectToHost)
        }

        let service = WeatherService(session: session, retryDelayNanoseconds: 1)

        await #expect(throws: URLError.self) {
            try await service.currentTemperatureC(latitude: 42.4295, longitude: -124.4017)
        }
    }

    @Test func nwsHTTPErrorThrows() async {
        let session = MockURLProtocol.makeSession { request in
            if request.url?.host == "api.weather.gov" {
                return MockURLProtocol.jsonResponse(statusCode: 500, body: "{}")
            }
            throw URLError(.cannotConnectToHost)
        }

        let service = WeatherService(session: session, retryDelayNanoseconds: 1)

        await #expect(throws: URLError.self) {
            try await service.currentTemperatureC(latitude: 42.4295, longitude: -124.4017)
        }
    }

    @Test func fallsBackToOpenMeteoWhenNWSFails() async throws {
        let session = MockURLProtocol.makeSession { request in
            if request.url?.host == "api.weather.gov" {
                throw URLError(.cannotConnectToHost)
            }
            return MockURLProtocol.jsonResponse(body: Fixtures.openMeteo(temperatureC: 18.5))
        }

        let service = WeatherService(session: session, retryDelayNanoseconds: 1)
        let celsius = try await service.currentTemperatureC(latitude: 42.4295, longitude: -124.4017)
        #expect(celsius == 18.5)
    }

    @Test func bothProvidersFailThrows() async {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.timedOut)
        }

        let service = WeatherService(session: session, retryDelayNanoseconds: 1)

        await #expect(throws: URLError.self) {
            try await service.currentTemperatureC(latitude: 42.4295, longitude: -124.4017)
        }
    }

    @Test func openMeteoParseSuccess() async throws {
        let session = MockURLProtocol.makeSession { request in
            if request.url?.host == "api.weather.gov" {
                throw URLError(.badServerResponse)
            }
            return MockURLProtocol.jsonResponse(body: Fixtures.openMeteo(temperatureC: 22.3))
        }

        let service = WeatherService(session: session, retryDelayNanoseconds: 1)
        let celsius = try await service.currentTemperatureC(latitude: 51.5, longitude: -0.1)
        #expect(celsius == 22.3)
    }
}
