import CoreLocation
import Foundation
import Testing
@testable import WeatherBar

struct NetworkDiagnosticsTests {
    @Test func describesDNSFailureWithVPNHint() {
        let description = NetworkDiagnostics.describe(URLError(.cannotFindHost))
        #expect(description.contains("cannotFindHost"))
        #expect(description.contains("DNS"))
    }

    @Test func describesTimeoutWithHint() {
        let description = NetworkDiagnostics.describe(URLError(.timedOut))
        #expect(description.contains("timedOut"))
        #expect(description.contains("timed out"))
    }

    @Test func describesTLSFailureWithSSLInspectionHint() {
        let description = NetworkDiagnostics.describe(URLError(.secureConnectionFailed))
        #expect(description.contains("secureConnectionFailed"))
        #expect(description.contains("TLS"))
    }

    @Test func describesCoreLocationErrors() {
        let error = NSError(
            domain: kCLErrorDomain,
            code: CLError.Code.network.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Network error"]
        )
        let description = NetworkDiagnostics.describe(error)
        #expect(description.contains("CoreLocation"))
        #expect(description.contains("network"))
    }

    @Test func authorizationStatusNamesAreReadable() {
        #expect(CLAuthorizationStatus.notDetermined.diagnosticsName == "notDetermined")
        #expect(CLAuthorizationStatus.denied.diagnosticsName == "denied")
        #expect(CLAuthorizationStatus.restricted.diagnosticsName == "restricted")
        #expect(CLAuthorizationStatus.authorizedAlways.diagnosticsName == "authorizedAlways")
    }
}
