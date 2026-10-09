import CoreLocation
import Foundation

#if canImport(Darwin)
import Darwin
#endif

extension CLAuthorizationStatus {
    /// Human-readable name for logs, alongside the raw value CoreLocation reports.
    var diagnosticsName: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        case .authorizedAlways: return "authorizedAlways"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

/// System-level facts that explain location behavior: VPN tunnels, MDM
/// management, and a consolidated startup inventory of every location source.
enum SystemDiagnostics {
    struct InterfaceAddresses: Equatable {
        let name: String
        let ipv4Addresses: [String]
    }
    /// Interface names present on the system (e.g. lo0, en0, utun3).
    static func networkInterfaceNames() -> [String] {
        networkInterfaces().map(\.name)
    }

    /// Interfaces with their IPv4 addresses, from getifaddrs.
    static func networkInterfaces() -> [InterfaceAddresses] {
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let first = interfaceList else { return [] }
        defer { freeifaddrs(interfaceList) }

        var byName: [String: [String]] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let name = String(cString: current.pointee.ifa_name)
            if let sockaddr = current.pointee.ifa_addr, sockaddr.pointee.sa_family == UInt8(AF_INET) {
                let address = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sockaddrIn in
                    var addr = sockaddrIn.pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    return inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil
                        ? String(cString: buffer)
                        : nil
                }
                if let address {
                    byName[name, default: []].append(address)
                }
            }
            cursor = current.pointee.ifa_next
        }
        return byName
            .map { InterfaceAddresses(name: $0.key, ipv4Addresses: $0.value.sorted()) }
            .sorted { $0.name < $1.name }
    }

    /// Tunnel interfaces that usually carry VPN traffic. Note: some system
    /// services (iCloud Private Relay) also create utun interfaces, which is why
    /// presence is reported as "likely", not certain.
    static func vpnInterfaceNames(from interfaces: [String]) -> [String] {
        interfaces.filter { interface in
            interface.hasPrefix("utun") || interface.hasPrefix("ppp") || interface.hasPrefix("ipsec")
        }
    }

    static func vpnInterfacesPresent() -> [String] {
        vpnInterfaceNames(from: networkInterfaceNames())
    }

    /// Corporate MDM enrollment usually installs managed preferences here; a
    /// managed Mac may have policy suppressing location permission prompts.
    static func isMDMManaged(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        fileExists("/Library/Managed Preferences")
    }

    /// True when an IPv4 string sits inside the CGNAT range 100.64.0.0/10 that
    /// Cloudflare WARP assigns to its tunnel interface.
    static func isCGNATAddress(_ ipv4: String) -> Bool {
        let parts = ipv4.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return false }
        let value = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
        return (value & 0xFFC0_0000) == 0x6440_0000
    }

    static func isCloudflareWARPInstalled(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        fileExists("/Applications/Cloudflare WARP.app") || fileExists("/Applications/Cloudflare One.app")
    }

    /// WARP's tunnel interface is a utun carrying a CGNAT address. Installed-but-
    /// disconnected WARP is harmless for location, so only the active tunnel counts.
    static func isCloudflareWARPActive(interfaces: [InterfaceAddresses]) -> Bool {
        interfaces.contains { interface in
            interface.name.hasPrefix("utun") && interface.ipv4Addresses.contains(where: isCGNATAddress)
        }
    }

    static func isCloudflareWARPActive() -> Bool {
        isCloudflareWARPActive(interfaces: networkInterfaces())
    }

    /// Remediation guidance when WARP is breaking Wi-Fi positioning and skewing
    /// IP geolocation toward the WARP egress city.
    static func cloudflareWARPGuidance() -> [String] {
        [
            "Cloudflare WARP (Zero Trust) tunnel is ACTIVE: WARP routes traffic through Cloudflare, so IP "
                + "geolocation resolves to the WARP egress city — never your actual town — and WARP's tunnel "
                + "is a known cause of macOS Wi-Fi positioning failures (location requests can fail through "
                + "the tunnel even though small requests succeed).",
            "Fix (takes a minute): quit WARP (menu-bar WARP icon → gear → Quit), then WeatherBar → Refresh now. "
                + "The GPS fix is cached for 30 days and WeatherBar keeps working correctly after WARP is "
                + "re-enabled.",
            "Fix (permanent, needs your Zero Trust admin): exclude Apple's location endpoints from the tunnel "
                + "in Settings → WARP Client → Split Tunnels → Exclude: *.ls.apple.com (and gsp-ssl.ls.apple.com)."
        ]
    }

    /// One-line inventory of every location source, logged at startup and
    /// whenever the location path changes so the log always answers
    /// "where did this location come from, and why that one?".
    static func locationSourceSummary(
        authorization: CLAuthorizationStatus,
        locationServicesEnabled: Bool,
        cachedGPSFixDescription: String?,
        manualOverrideActive: Bool,
        vpnInterfaces: [String],
        mdmManaged: Bool,
        cloudflareWARPActive: Bool = false
    ) -> String {
        var parts: [String] = [
            "authorization=\(authorization.diagnosticsName)",
            "systemLocationServices=\(locationServicesEnabled ? "on" : "off")",
            "cachedGPSFix=\(cachedGPSFixDescription ?? "none")",
            "manualOverride=\(manualOverrideActive ? "on" : "off")"
        ]
        if !vpnInterfaces.isEmpty {
            parts.append("vpnTunnels=[\(vpnInterfaces.joined(separator: ", "))] (IP geolocation will resolve to the tunnel's exit city)")
        }
        if cloudflareWARPActive {
            parts.append("cloudflareWARP=active (IP geolocation resolves to the WARP egress; Wi-Fi positioning may fail through the tunnel)")
        }
        if mdmManaged {
            parts.append("mdmManaged=true (corporate policy may suppress the location permission prompt)")
        }
        return "Location sources: " + parts.joined(separator: ", ")
    }
}

/// Builds detailed, action-oriented log descriptions for network and location errors,
/// flagging the failure patterns commonly caused by corporate VPNs, proxies, and firewalls.
enum NetworkDiagnostics {
    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return describe(urlError)
        }
        if let clError = error as? CLError {
            return "CoreLocation error code \(clError.code.rawValue) (\(cleCodeName(clError.code))): \(clError.localizedDescription)"
        }
        if let decodingError = error as? DecodingError {
            return "Response decoding failed (\(decodingSummary(decodingError))) — server response may be an unexpected format or a proxy block page"
        }
        let nsError = error as NSError
        return "\(nsError.domain) code \(nsError.code): \(error.localizedDescription)"
    }

    private static func describe(_ error: URLError) -> String {
        var parts: [String] = ["URLError.\(urlErrorCodeName(error.code)) (code \(error.code.rawValue))"]

        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            parts.append("url=\(url.absoluteString)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain) code \(underlying.code)")
        }

        let hint = vpnHint(for: error.code)
        if !hint.isEmpty {
            parts.append("hint: \(hint)")
        }

        parts.append("\"\(error.localizedDescription)\"")
        return parts.joined(separator: " ")
    }

    /// Failure patterns where a VPN, proxy, or firewall is a plausible root cause.
    private static func vpnHint(for code: URLError.Code) -> String {
        switch code {
        case .cannotFindHost:
            return "DNS lookup failed — VPN/proxy DNS or a filtered resolver may be blocking this host"
        case .cannotConnectToHost:
            return "connection could not be established — a firewall or VPN may be blocking this host/port"
        case .timedOut:
            return "request timed out — the host may be blocked or the tunnel is slow"
        case .networkConnectionLost, .notConnectedToInternet:
            return "no usable network connectivity — VPN may have dropped or split-tunnel rules apply"
        case .secureConnectionFailed:
            return "TLS handshake failed — corporate SSL inspection (VPN/proxy MITM) is a common cause"
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid:
            return "server certificate rejected — corporate SSL inspection (VPN/proxy MITM) is a common cause"
        case .badServerResponse:
            return "server response was malformed — a proxy may have intercepted the request"
        case .cannotParseResponse:
            return "response could not be parsed — a proxy block page may have been returned instead"
        default:
            return ""
        }
    }

    private static func urlErrorCodeName(_ code: URLError.Code) -> String {
        switch code {
        case .badURL: return "badURL"
        case .timedOut: return "timedOut"
        case .unsupportedURL: return "unsupportedURL"
        case .cannotFindHost: return "cannotFindHost"
        case .cannotConnectToHost: return "cannotConnectToHost"
        case .notConnectedToInternet: return "notConnectedToInternet"
        case .networkConnectionLost: return "networkConnectionLost"
        case .badServerResponse: return "badServerResponse"
        case .cannotParseResponse: return "cannotParseResponse"
        case .userCancelledAuthentication: return "userCancelledAuthentication"
        case .userAuthenticationRequired: return "userAuthenticationRequired"
        case .secureConnectionFailed: return "secureConnectionFailed"
        case .serverCertificateHasBadDate: return "serverCertificateHasBadDate"
        case .serverCertificateUntrusted: return "serverCertificateUntrusted"
        case .serverCertificateHasUnknownRoot: return "serverCertificateHasUnknownRoot"
        case .serverCertificateNotYetValid: return "serverCertificateNotYetValid"
        case .cancelled: return "cancelled"
        case .internationalRoamingOff: return "internationalRoamingOff"
        case .callIsActive: return "callIsActive"
        case .dataNotAllowed: return "dataNotAllowed"
        case .requestBodyStreamExhausted: return "requestBodyStreamExhausted"
        default: return "code-\(code.rawValue)"
        }
    }

    private static func cleCodeName(_ code: CLError.Code) -> String {
        switch code {
        case .locationUnknown: return "locationUnknown"
        case .denied: return "denied"
        case .network: return "network"
        case .headingFailure: return "headingFailure"
        case .geocodeFoundNoResult: return "geocodeFoundNoResult"
        case .geocodeFoundPartialResult: return "geocodeFoundPartialResult"
        case .geocodeCanceled: return "geocodeCanceled"
        case .rangingUnavailable: return "rangingUnavailable"
        case .rangingFailure: return "rangingFailure"
        case .promptDeclined: return "promptDeclined"
        default: return "code-\(code.rawValue)"
        }
    }

    private static func decodingSummary(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            return "dataCorrupted at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .keyNotFound(let key, _):
            return "missing key \(key.stringValue)"
        case .typeMismatch(let type, let context):
            return "type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "missing value of \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default:
            return String(describing: error)
        }
    }
}
