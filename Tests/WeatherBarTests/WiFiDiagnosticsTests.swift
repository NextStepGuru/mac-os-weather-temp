import Foundation
import Testing
@testable import WeatherBar

struct WiFiDiagnosticsTests {
    private let hardwarePortsFixture = """
    Hardware Port: Ethernet Adapter (en4)
    Device: en4
    Ethernet Address: 26:37:d9:93:6d:ee

    Hardware Port: Wi-Fi
    Device: en0
    Ethernet Address: 60:3e:5f:51:98:39

    Hardware Port: Thunderbolt Bridge
    Device: bridge0
    Ethernet Address: 36:91:10:cc:3b:00
    """

    @Test func parsesWiFiDeviceFromHardwarePorts() {
        #expect(WiFiDiagnostics.parseWiFiDevice(fromHardwarePorts: hardwarePortsFixture) == "en0")
        #expect(WiFiDiagnostics.parseWiFiDevice(fromHardwarePorts: "Hardware Port: Ethernet Adapter (en4)\nDevice: en4") == nil)
        #expect(WiFiDiagnostics.parseWiFiDevice(fromHardwarePorts: "") == nil)
    }

    @Test func parsesAirportPower() {
        #expect(WiFiDiagnostics.parseAirportPower("Wi-Fi Power (en0): On") == true)
        #expect(WiFiDiagnostics.parseAirportPower("Wi-Fi Power (en0): Off") == false)
        #expect(WiFiDiagnostics.parseAirportPower("en1 is not a Wi-Fi interface.") == nil)
    }

    @Test func parsesAssociatedNetwork() {
        #expect(WiFiDiagnostics.parseAssociatedNetwork("Current Wi-Fi Network: HomeNet\n") == "HomeNet")
        #expect(WiFiDiagnostics.parseAssociatedNetwork("You are not associated with an AirPort network.") == nil)
    }

    @Test func captureStateUsesRunnerOutputs() {
        var commands: [(String, [String])] = []
        let state = WiFiDiagnostics.captureState { executable, arguments in
            commands.append((executable, arguments))
            switch arguments.first {
            case "-listallhardwareports":
                return hardwarePortsFixture
            case "-getairportpower":
                return "Wi-Fi Power (en0): On"
            case "-getairportnetwork":
                return "You are not associated with an AirPort network."
            default:
                return nil
            }
        }

        #expect(state == WiFiState(interface: "en0", poweredOn: true, associatedNetwork: nil))
        #expect(commands.count == 3)
    }

    @Test func guidanceForUnjoinedEthernetMacMentionsRuralDatabase() {
        let state = WiFiState(interface: "en0", poweredOn: true, associatedNetwork: nil)
        let lines = WiFiDiagnostics.guidance(for: state, appleLocationReachable: true)
        #expect(lines.count == 1)
        #expect(lines[0].contains("not joined"))
        #expect(lines[0].contains("Settings"))
    }

    @Test func guidanceForBlockedAppleServiceMentionsVPNAndCache() {
        let state = WiFiState(interface: "en0", poweredOn: true, associatedNetwork: "HomeNet")
        let lines = WiFiDiagnostics.guidance(for: state, appleLocationReachable: false)
        #expect(lines.count == 1)
        #expect(lines[0].contains("UNREACHABLE"))
        #expect(lines[0].contains("30 days"))
    }

    @Test func guidanceForHealthyWiFiButNoFixSuggestsManualLocation() {
        let state = WiFiState(interface: "en0", poweredOn: true, associatedNetwork: "HomeNet")
        let lines = WiFiDiagnostics.guidance(for: state, appleLocationReachable: true)
        #expect(lines.count == 1)
        #expect(lines[0].contains("no location data"))
    }

    @Test func guidanceForNoWiFiHardwareSuggestsManualLocation() {
        let state = WiFiState(interface: nil, poweredOn: nil, associatedNetwork: nil)
        let lines = WiFiDiagnostics.guidance(for: state, appleLocationReachable: true)
        #expect(lines.count == 1)
        #expect(lines[0].contains("no Wi-Fi hardware"))
    }

    @Test func guidanceForOffWiFiSuggestsEnabling() {
        let state = WiFiState(interface: "en0", poweredOn: false, associatedNetwork: nil)
        let lines = WiFiDiagnostics.guidance(for: state, appleLocationReachable: true)
        #expect(lines.count == 1)
        #expect(lines[0].contains("OFF"))
    }

    @Test func reachabilityRequiresAnyHTTPResponse() {
        #expect(LocationServiceProbe.isReachable(statusCode: 403) == true)
        #expect(LocationServiceProbe.isReachable(statusCode: 200) == true)
        #expect(LocationServiceProbe.isReachable(statusCode: nil) == false)
    }
}
