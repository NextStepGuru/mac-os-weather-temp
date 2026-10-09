import CoreLocation
import Foundation
import Testing
@testable import WeatherBar

struct SystemDiagnosticsTests {
    @Test func vpnInterfaceDetection() {
        let vpns = SystemDiagnostics.vpnInterfaceNames(
            from: ["lo0", "en0", "en1", "utun3", "utun4", "bridge0", "ppp0", "ipsec0"]
        )
        #expect(vpns == ["utun3", "utun4", "ppp0", "ipsec0"])
    }

    @Test func noVpnInterfacesOnPlainNetwork() {
        let vpns = SystemDiagnostics.vpnInterfaceNames(from: ["lo0", "en0", "en1", "awdl0"])
        #expect(vpns.isEmpty)
    }

    @Test func mdmManagedDetectedByManagedPreferencesDirectory() {
        #expect(SystemDiagnostics.isMDMManaged { path in path == "/Library/Managed Preferences" })
        #expect(!SystemDiagnostics.isMDMManaged { _ in false })
    }

    @Test func locationSourceSummaryExplainsVPNEgressAndMDM() {
        let summary = SystemDiagnostics.locationSourceSummary(
            authorization: .notDetermined,
            locationServicesEnabled: true,
            cachedGPSFixDescription: nil,
            manualOverrideActive: false,
            vpnInterfaces: ["utun3"],
            mdmManaged: true
        )
        #expect(summary.contains("authorization=notDetermined"))
        #expect(summary.contains("systemLocationServices=on"))
        #expect(summary.contains("cachedGPSFix=none"))
        #expect(summary.contains("utun3"))
        #expect(summary.contains("exit city"))
        #expect(summary.contains("mdmManaged=true"))
    }

    @Test func locationSourceSummaryOmitsVPNAndMDMWhenAbsent() {
        let summary = SystemDiagnostics.locationSourceSummary(
            authorization: .authorizedAlways,
            locationServicesEnabled: true,
            cachedGPSFixDescription: "Portland, OR",
            manualOverrideActive: false,
            vpnInterfaces: [],
            mdmManaged: false
        )
        #expect(!summary.contains("vpnTunnels"))
        #expect(!summary.contains("mdmManaged"))
        #expect(summary.contains("cachedGPSFix=Portland, OR"))
    }
}
