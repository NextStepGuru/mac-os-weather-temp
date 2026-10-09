import CoreLocation
import Foundation

enum IPFallbackReason: Equatable {
    case denied
    case graceTimeout
    /// The permission prompt was never answered (status stuck at notDetermined).
    case permissionPending
    /// The user explicitly asked for a refresh while no location is available.
    case manualRefresh
}

enum IPFallbackDecision: Equatable {
    case attempt
    case skipManualOverride
    case skipHasGPS
    case alreadyAttempted(showDenied: Bool)
}

enum IPFallbackPolicy {
    static func shouldAttempt(
        reason: IPFallbackReason,
        isManualOverride: Bool,
        lastGPSLocation: CLLocation?,
        ipFallbackAttempted: Bool,
        lastLocation: CLLocation?,
        isManualRefresh: Bool = false
    ) -> IPFallbackDecision {
        _ = reason
        if isManualOverride {
            return .skipManualOverride
        }
        if lastGPSLocation != nil {
            return .skipHasGPS
        }
        // A manual refresh is an explicit user request for data, so allow one retry
        // even if a previous attempt already failed (and produced no location).
        if ipFallbackAttempted, !(isManualRefresh && lastLocation == nil) {
            return .alreadyAttempted(showDenied: lastLocation == nil)
        }
        return .attempt
    }
}

struct StatusLineInput {
    var loginItemError: String?
    var isGeocoding: Bool
    var placeInfo: PlaceInfo?
    var location: CLLocation?
    var isManualOverride: Bool
    var isUsingIPFallback: Bool
    var isUsingLastKnownGPS = false
    var lastUpdated: Date?
    var isFetching: Bool
    var lastFetchFailed: Bool
    var isLocating: Bool
    var now: Date
}

enum StatusLineFormatter {
    static func format(_ input: StatusLineInput) -> String? {
        if let loginItemError = input.loginItemError {
            return loginItemError
        }

        if input.isGeocoding {
            return "Looking up location…"
        }

        if let placeInfo = input.placeInfo {
            let localTime = placeInfo.formatTime(input.now)
            let tzAbbr = placeInfo.timeZoneAbbreviation(for: input.now)
            var text = "\(placeInfo.displayName) · \(localTime) \(tzAbbr)"

            if input.isManualOverride {
                text += " · Manual"
            }

            if input.isUsingIPFallback {
                text += " · Approx (IP)"
            }

            if input.isUsingLastKnownGPS {
                text += " · Last known"
            }

            if let lastUpdated = input.lastUpdated {
                let updatedTime = placeInfo.formatTime(lastUpdated)
                text += " · Updated \(updatedTime)"
            } else if input.isFetching {
                text += " · Refreshing…"
            }

            if input.lastFetchFailed {
                text += " · Update failed"
            }

            return text
        }

        if let location = input.location {
            let lat = String(format: "%.4f", location.coordinate.latitude)
            let lon = String(format: "%.4f", location.coordinate.longitude)
            var text = "Location: \(lat), \(lon)"

            if let lastUpdated = input.lastUpdated {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                formatter.timeZone = .current
                text += " · Updated \(formatter.string(from: lastUpdated))"
            } else if input.isFetching {
                text += " · Refreshing…"
            }

            if input.lastFetchFailed {
                text += " · Update failed"
            }

            return text
        }

        if input.isLocating {
            return "Locating…"
        }

        if input.isFetching {
            return "Refreshing…"
        }

        return nil
    }
}

enum WeatherDisplayPolicy {
    /// Returns a new menu bar title on fetch failure, or nil to keep the existing title.
    static func menuBarTitleOnFetchFailure(lastTemperatureText: String?) -> String? {
        lastTemperatureText == nil ? "!°" : nil
    }
}

enum LocationChangeDetector {
    static func hasChanged(from previous: CLLocation?, to current: CLLocation, tolerance: Double) -> Bool {
        guard let previous else { return true }
        return abs(previous.coordinate.latitude - current.coordinate.latitude) > tolerance
            || abs(previous.coordinate.longitude - current.coordinate.longitude) > tolerance
    }
}
