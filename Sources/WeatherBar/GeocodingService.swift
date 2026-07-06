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
    static func resolvePlace(
        locality: String?,
        subAdministrativeArea: String?,
        name: String?,
        administrativeArea: String?,
        timeZone: TimeZone?
    ) -> PlaceInfo {
        let city = locality
            ?? subAdministrativeArea
            ?? name
            ?? "Unknown"
        let state = administrativeArea ?? "Unknown"
        return PlaceInfo(city: city, state: state, timeZone: timeZone ?? .current)
    }

    static func placeInfo(from placemark: CLPlacemark) -> PlaceInfo {
        resolvePlace(
            locality: placemark.locality,
            subAdministrativeArea: placemark.subAdministrativeArea,
            name: placemark.name,
            administrativeArea: placemark.administrativeArea,
            timeZone: placemark.timeZone
        )
    }

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

                continuation.resume(returning: Self.placeInfo(from: placemark))
            }
        }
    }

    func forwardGeocode(address: String) async throws -> (location: CLLocation, place: PlaceInfo) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GeocodingError.invalidAddress
        }

        let geocoder = CLGeocoder()
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.geocodeAddressString(trimmed) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let placemark = placemarks?.first, let location = placemark.location else {
                    continuation.resume(throwing: GeocodingError.noResults)
                    return
                }

                continuation.resume(returning: (location, Self.placeInfo(from: placemark)))
            }
        }
    }
}

enum GeocodingError: LocalizedError {
    case noResults
    case invalidAddress

    var errorDescription: String? {
        switch self {
        case .noResults:
            return "No location results found"
        case .invalidAddress:
            return "Please enter a place name or address"
        }
    }
}
