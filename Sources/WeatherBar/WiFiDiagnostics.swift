import Foundation

/// Why CoreLocation has no fix, explained from the machine's own Wi-Fi state.
/// macOS locates almost exclusively by scanning nearby Wi-Fi networks; when that
/// yields nothing, every downstream source is a guess.
struct WiFiState: Equatable {
    var interface: String?
    var poweredOn: Bool?
    var associatedNetwork: String?

    var hasInterface: Bool { interface != nil }
}

enum WiFiDiagnostics {
    /// Runs networksetup to capture the Wi-Fi interface, power state, and the
    /// associated network (if any). Overridable runner for tests.
    static func captureState(
        runCommand: (_ executable: String, _ arguments: [String]) -> String? = { executable, arguments in
            Self.run(executable: executable, arguments: arguments)
        }
    ) -> WiFiState {
        let hardwarePorts = runCommand("/usr/sbin/networksetup", ["-listallhardwareports"]) ?? ""
        let interface = parseWiFiDevice(fromHardwarePorts: hardwarePorts)

        guard let interface else { return WiFiState(interface: nil, poweredOn: nil, associatedNetwork: nil) }

        let powerOutput = runCommand("/usr/sbin/networksetup", ["-getairportpower", interface]) ?? ""
        let poweredOn = parseAirportPower(powerOutput)

        let networkOutput = runCommand("/usr/sbin/networksetup", ["-getairportnetwork", interface]) ?? ""
        let associatedNetwork = parseAssociatedNetwork(networkOutput)

        return WiFiState(interface: interface, poweredOn: poweredOn, associatedNetwork: associatedNetwork)
    }

    static func parseWiFiDevice(fromHardwarePorts output: String) -> String? {
        var lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        while let portIndex = lines.firstIndex(where: { $0.hasPrefix("Hardware Port: Wi-Fi") }) {
            let window = lines[(portIndex + 1)...].prefix(3)
            if let deviceLine = window.first(where: { $0.hasPrefix("Device:") }) {
                return String(deviceLine.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces))
            }
            lines.removeFirst(portIndex + 1)
        }
        return nil
    }

    /// "Wi-Fi Power (en0): On" → true, "... Off" → false, anything else → nil.
    static func parseAirportPower(_ output: String) -> Bool? {
        if output.contains(": On") { return true }
        if output.contains(": Off") { return false }
        return nil
    }

    /// "Current Wi-Fi Network: HomeNet" → "HomeNet";
    /// "You are not associated with an AirPort network." → nil.
    static func parseAssociatedNetwork(_ output: String) -> String? {
        guard let range = output.range(of: "Current Wi-Fi Network:") else { return nil }
        let network = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return network.isEmpty ? nil : network
    }

    /// Human guidance for the log, ordered by how fixable each cause is.
    static func guidance(for state: WiFiState, appleLocationReachable: Bool?) -> [String] {
        var lines: [String] = []

        if let appleLocationReachable, !appleLocationReachable {
            lines.append(
                "Wi-Fi positioning: Apple's location service is UNREACHABLE — the VPN/firewall is blocking it. "
                    + "Refresh once with the VPN disconnected; WeatherBar caches the fix for 30 days."
            )
        }

        if !state.hasInterface {
            lines.append(
                "Wi-Fi positioning: no Wi-Fi hardware on this Mac — macOS cannot auto-locate without it. "
                    + "Set your location once in Settings… for exact weather."
            )
        } else if state.poweredOn == false {
            lines.append(
                "Wi-Fi positioning: Wi-Fi is OFF — enable it in System Settings → Wi-Fi. macOS locates by "
                    + "scanning nearby networks, even without joining one; Ethernet can remain the connection."
            )
        } else if state.associatedNetwork == nil {
            lines.append(
                "Wi-Fi positioning: Wi-Fi is on but not joined to any network. This Mac is likely on Ethernet, and "
                    + "in rural areas Apple's database may not know the nearby networks — joining your own router "
                    + "once (Ethernet stays primary) helps Apple learn this location over time. Meanwhile, set your "
                    + "location in Settings… for exact weather."
            )
        } else if lines.isEmpty {
            lines.append(
                "Wi-Fi positioning: connected to \"\(state.associatedNetwork ?? "")\" but Apple has no location "
                    + "data for these networks yet. Set your location in Settings… for exact weather."
            )
        }

        return lines
    }

    private static func run(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Quick reachability check for the endpoint locationd talks to, so the log can
/// distinguish "blocked by VPN/firewall" from "reachable but no Wi-Fi data".
enum LocationServiceProbe {
    static let appleLocationTestURL = URL(string: "https://gsp-ssl.ls.apple.com/pep/gcc")!

    /// Any HTTP response (even 403, its normal unauthenticated reply) means the
    /// endpoint is reachable; only transport failure means blocked.
    static func isReachable(statusCode: Int?) -> Bool {
        statusCode != nil
    }

    static func probe() async -> Bool? {
        var request = URLRequest(url: appleLocationTestURL)
        request.timeoutInterval = 5
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 6
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let outcome = await withCheckedContinuation { continuation in
            session.dataTask(with: request) { _, response, _ in
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                continuation.resume(returning: statusCode)
            }.resume()
        }
        return isReachable(statusCode: outcome)
    }
}
