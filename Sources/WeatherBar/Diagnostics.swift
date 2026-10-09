import CoreLocation
import Foundation

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
