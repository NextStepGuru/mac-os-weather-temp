import CoreLocation
import Foundation
import Testing
@testable import WeatherBar

struct IPLocationServiceTests {
    @Test func successParse() async throws {
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(body: Fixtures.ipapiSuccess)
        }

        let service = IPLocationService(session: session)
        let result = try await service.lookup()

        #expect(abs(result.location.coordinate.latitude - 45.5152) < 0.0001)
        #expect(abs(result.location.coordinate.longitude - (-122.6784)) < 0.0001)
        #expect(result.place.city == "Portland")
        #expect(result.place.state == "OR")
        #expect(result.place.timeZone.identifier == "America/Los_Angeles")
    }

    @Test func errorTrueThrows() async {
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(body: Fixtures.ipapiError)
        }

        let service = IPLocationService(session: session)

        await #expect(throws: URLError.self) {
            try await service.lookup()
        }
    }

    @Test func missingCoordinatesThrows() async {
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(body: Fixtures.ipapiMissingCoords)
        }

        let service = IPLocationService(session: session)

        await #expect(throws: URLError.self) {
            try await service.lookup()
        }
    }

    @Test func regionCodePreferredOverRegion() async throws {
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(body: Fixtures.ipapiSuccess)
        }

        let service = IPLocationService(session: session)
        let result = try await service.lookup()
        #expect(result.place.state == "OR")
    }

    @Test func regionFallbackWhenNoRegionCode() async throws {
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(body: Fixtures.ipapiRegionFallback)
        }

        let service = IPLocationService(session: session)
        let result = try await service.lookup()
        #expect(result.place.state == "Nebraska")
    }

    @Test func defaultsCityAndStateToUnknown() async throws {
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(body: Fixtures.ipapiMinimalFields)
        }

        let service = IPLocationService(session: session)
        let result = try await service.lookup()
        #expect(result.place.city == "Unknown")
        #expect(result.place.state == "Unknown")
    }

    @Test func httpErrorThrows() async {
        let session = MockURLProtocol.makeSession { _ in
            MockURLProtocol.jsonResponse(statusCode: 503, body: "{}")
        }

        let service = IPLocationService(session: session)

        await #expect(throws: URLError.self) {
            try await service.lookup()
        }
    }
}
