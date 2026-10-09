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

    @Test func cgnatAddressDetection() {
        #expect(SystemDiagnostics.isCGNATAddress("100.96.0.2"))
        #expect(SystemDiagnostics.isCGNATAddress("100.127.255.254"))
        #expect(!SystemDiagnostics.isCGNATAddress("100.128.0.1"))
        #expect(!SystemDiagnostics.isCGNATAddress("192.168.1.1"))
        #expect(!SystemDiagnostics.isCGNATAddress("not-an-ip"))
    }

    @Test func warpActiveDetectsUTunWithCGNATAddress() {
        let interfaces = [
            SystemDiagnostics.InterfaceAddresses(name: "en0", ipv4Addresses: ["192.168.1.50"]),
            SystemDiagnostics.InterfaceAddresses(name: "utun0", ipv4Addresses: ["100.96.0.2"])
        ]
        #expect(SystemDiagnostics.isCloudflareWARPActive(interfaces: interfaces))
    }

    @Test func warpInactiveWithoutCGNATTunnel() {
        let interfaces = [
            SystemDiagnostics.InterfaceAddresses(name: "en0", ipv4Addresses: ["192.168.1.50"]),
            SystemDiagnostics.InterfaceAddresses(name: "utun3", ipv4Addresses: ["10.0.0.1"])
        ]
        #expect(!SystemDiagnostics.isCloudflareWARPActive(interfaces: interfaces))
    }

    @Test func warpInstalledDetectsCloudflareApps() {
        #expect(SystemDiagnostics.isCloudflareWARPInstalled { path in
            path == "/Applications/Cloudflare WARP.app"
        })
        #expect(SystemDiagnostics.isCloudflareWARPInstalled { path in
            path == "/Applications/Cloudflare One.app"
        })
        #expect(!SystemDiagnostics.isCloudflareWARPInstalled { _ in false })
    }

    @Test func warpGuidanceMentionsQuitAndSplitTunnel() {
        let lines = SystemDiagnostics.cloudflareWARPGuidance()
        #expect(lines.count == 3)
        #expect(lines.contains { $0.contains("Quit") && $0.contains("30 days") })
        #expect(lines.contains { $0.contains("Split Tunnels") && $0.contains("*.ls.apple.com") })
    }

    @Test func locationSourceSummaryFlagsActiveWARP() {
        let summary = SystemDiagnostics.locationSourceSummary(
            authorization: .authorizedAlways,
            locationServicesEnabled: true,
            cachedGPSFixDescription: nil,
            manualOverrideActive: false,
            vpnInterfaces: ["utun0"],
            mdmManaged: true,
            cloudflareWARPActive: true
        )
        #expect(summary.contains("cloudflareWARP=active"))
        #expect(summary.contains("WARP egress"))
    }
}
