import CoreLocation
import Foundation

struct IPLocationService {
    private static let userAgent = "WeatherBar/1.0 (com.weatherbar.app)"
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private struct IPGeoResponse: Decodable {
        let latitude: Double?
        let longitude: Double?
        let city: String?
        let region: String?
        let regionCode: String?
        let timezone: String?
        let error: Bool?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case latitude, longitude, city, region, timezone, error, reason
            case regionCode = "region_code"
        }
    }

    func lookup() async throws -> (location: CLLocation, place: PlaceInfo) {
        let url = URL(string: "https://ipapi.co/json/")!
        AppLogger.shared.log("Requesting IP geolocation from \(url.absoluteString)", level: .debug)

        let data = try await request(url: url)
        let response = try JSONDecoder().decode(IPGeoResponse.self, from: data)

        if response.error == true {
            let reason = response.reason ?? "unknown error"
            AppLogger.shared.log("IP geolocation API error: \(reason)", level: .error)
            throw URLError(.cannotParseResponse)
        }

        guard let latitude = response.latitude, let longitude = response.longitude else {
            AppLogger.shared.log("IP geolocation missing coordinates", level: .error)
            throw URLError(.cannotParseResponse)
        }

        let city = response.city ?? "Unknown"
        let state = response.regionCode ?? response.region ?? "Unknown"
        let timeZone = response.timezone.flatMap { TimeZone(identifier: $0) } ?? .current
        let place = PlaceInfo(city: city, state: state, timeZone: timeZone)
        let location = CLLocation(latitude: latitude, longitude: longitude)

        AppLogger.shared.log(
            "IP geolocation success: \(place.displayName) (\(latitude), \(longitude))",
            level: .debug
        )
        return (location, place)
    }

    private func request(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await Self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            AppLogger.shared.log(
                "IP geolocation bad response: HTTP \(httpResponse.statusCode) for \(url.host ?? "")",
                level: .error
            )
            throw URLError(.badServerResponse)
        }

        return data
    }
}
