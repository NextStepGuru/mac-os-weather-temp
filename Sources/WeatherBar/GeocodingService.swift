import CoreLocation
import Foundation

struct PlaceInfo: Equatable {
    let city: String
    let state: String
    let timeZone: TimeZone

    var displayName: String {
        "\(city), \(state)"
    }

    func formatTime(_ date: Date, style: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = style
        formatter.dateStyle = .none
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    func timeZoneAbbreviation(for date: Date = Date()) -> String {
        timeZone.abbreviation(for: date) ?? timeZone.identifier
    }
}

struct GeocodingService: Sendable {
    func reverseGeocode(location: CLLocation) async throws -> PlaceInfo {
        let geocoder = CLGeocoder()
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let placemark = placemarks?.first else {
                    continuation.resume(throwing: GeocodingError.noResults)
                    return
                }

                let city = placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.name
                    ?? "Unknown"
                let state = placemark.administrativeArea ?? "Unknown"
                let timeZone = placemark.timeZone ?? .current

                continuation.resume(returning: PlaceInfo(city: city, state: state, timeZone: timeZone))
            }
        }
    }
}

enum GeocodingError: LocalizedError {
    case noResults

    var errorDescription: String? {
        switch self {
        case .noResults:
            return "No location results found"
        }
    }
}
