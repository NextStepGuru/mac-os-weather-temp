import CoreLocation
import Testing
@testable import WeatherBar

struct IPFallbackPolicyTests {
    @Test func manualOverrideBlocksIPFallback() {
        let decision = IPFallbackPolicy.shouldAttempt(
            reason: .denied,
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
            reason: .graceTimeout,
            isManualOverride: false,
            lastGPSLocation: gps,
            ipFallbackAttempted: false,
            lastLocation: nil
        )
        #expect(decision == .skipHasGPS)
    }

    @Test func deniedReasonAttemptsWhenEligible() {
        let decision = IPFallbackPolicy.shouldAttempt(
            reason: .denied,
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: false,
            lastLocation: nil
        )
        #expect(decision == .attempt)
    }

    @Test func graceTimeoutReasonAttemptsWhenEligible() {
        let decision = IPFallbackPolicy.shouldAttempt(
            reason: .graceTimeout,
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: false,
            lastLocation: nil
        )
        #expect(decision == .attempt)
    }

    @Test func alreadyAttemptedShowsDeniedWhenNoLocation() {
        let decision = IPFallbackPolicy.shouldAttempt(
            reason: .denied,
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
            reason: .graceTimeout,
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: true,
            lastLocation: location
        )
        #expect(decision == .alreadyAttempted(showDenied: false))
    }

    @Test func permissionPendingAttemptsWhenEligible() {
        let decision = IPFallbackPolicy.shouldAttempt(
            reason: .permissionPending,
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: false,
            lastLocation: nil
        )
        #expect(decision == .attempt)
    }

    @Test func manualRefreshRetriesAfterFailedAttempt() {
        let decision = IPFallbackPolicy.shouldAttempt(
            reason: .manualRefresh,
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: true,
            lastLocation: nil,
            isManualRefresh: true
        )
        #expect(decision == .attempt)
    }

    @Test func manualRefreshDoesNotRetryWhenLocationExists() {
        let location = CLLocation(latitude: 45.0, longitude: -122.0)
        let decision = IPFallbackPolicy.shouldAttempt(
            reason: .manualRefresh,
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: true,
            lastLocation: location,
            isManualRefresh: true
        )
        #expect(decision == .alreadyAttempted(showDenied: false))
    }

    @Test func nonManualRefreshDoesNotRetryAfterAttempt() {
        let decision = IPFallbackPolicy.shouldAttempt(
            reason: .graceTimeout,
            isManualOverride: false,
            lastGPSLocation: nil,
            ipFallbackAttempted: true,
            lastLocation: nil,
            isManualRefresh: false
        )
        #expect(decision == .alreadyAttempted(showDenied: true))
    }
}
