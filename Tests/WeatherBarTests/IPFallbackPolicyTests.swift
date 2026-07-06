import CoreLocation
import Testing
@testable import WeatherBar

struct IPFallbackPolicyTests {
    @Test func manualOverrideBlocksIPFallback() {
        let decision = IPFallbackPolicy.shouldAttempt(
            isManualOverride: true,
            lastGPSLocation: nil,
            ipFallbackAttempted: false,
            lastLocation: nil
        )
        #expect(decision == .skipManualOverride)
    }

    @Test func cachedGPSBlocksIPFallback() {
        let gps = CLLocation(latitude: 45.0, longitude: -122.0)
        let decision = IPFallbackPolicy.shouldAttempt(
            isManualOverride: false,
            lastGPSLocation: gps,
            ipFallbackAttempted: false,
            lastLocation: nil
        )
        #expect(decision == .skipHasGPS)
    }

    @Test func firstAttemptWhenEligible() {
        let decision = IPFallbackPolicy.shouldAttempt(
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: false,
            lastLocation: nil
        )
        #expect(decision == .attempt)
    }

    @Test func alreadyAttemptedShowsDeniedWhenNoLocation() {
        let decision = IPFallbackPolicy.shouldAttempt(
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: true,
            lastLocation: nil
        )
        #expect(decision == .alreadyAttempted(showDenied: true))
    }

    @Test func alreadyAttemptedSkipsWhenLocationExists() {
        let location = CLLocation(latitude: 45.0, longitude: -122.0)
        let decision = IPFallbackPolicy.shouldAttempt(
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: true,
            lastLocation: location
        )
        #expect(decision == .alreadyAttempted(showDenied: false))
    }
}
