import Foundation

struct WeatherService {
    private static let userAgent = "WeatherBar/1.0 (com.weatherbar.app)"

    private let session: URLSession
    private let retryDelayNanoseconds: UInt64

    init(session: URLSession = .configured, retryDelayNanoseconds: UInt64 = 1_000_000_000) {
        self.session = session
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    private struct NWSPointsResponse: Decodable {
        struct Properties: Decodable {
            let forecastHourly: URL
        }

        let properties: Properties
    }

    private struct NWSHourlyForecastResponse: Decodable {
        struct Period: Decodable {
            let temperature: Double
            let temperatureUnit: String
        }

        struct Properties: Decodable {
            let periods: [Period]
        }

        let properties: Properties
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature2m: Double

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
            }
        }

        let current: Current
    }

    func currentTemperatureC(latitude: Double, longitude: Double) async throws -> Double {
        var lastError: Error?

        for provider in [fetchFromNWS, fetchFromOpenMeteo] {
            do {
                return try await fetchWithRetry(provider, latitude: latitude, longitude: longitude)
            } catch {
                lastError = error
                AppLogger.shared.log(
                    "Weather provider failed: \(error.localizedDescription)",
                    level: .warning
                )
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private func fetchWithRetry(
        _ provider: (Double, Double) async throws -> Double,
        latitude: Double,
        longitude: Double,
        maxAttempts: Int = 2
    ) async throws -> Double {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await provider(latitude, longitude)
            } catch {
                lastError = error
                if attempt < maxAttempts, Self.shouldRetry(error) {
                    AppLogger.shared.log("Retrying weather fetch (attempt \(attempt + 1))", level: .debug)
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    static func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }

    private func fetchFromNWS(latitude: Double, longitude: Double) async throws -> Double {
        let lat = String(format: "%.4f", latitude)
        let lon = String(format: "%.4f", longitude)
        let pointsURL = URL(string: "https://api.weather.gov/points/\(lat),\(lon)")!

        AppLogger.shared.log("Requesting NWS points from \(pointsURL.absoluteString)", level: .debug)

        let pointsData = try await request(url: pointsURL)
        let points = try JSONDecoder().decode(NWSPointsResponse.self, from: pointsData)
        let hourlyURL = points.properties.forecastHourly

        AppLogger.shared.log("Requesting NWS hourly forecast from \(hourlyURL.absoluteString)", level: .debug)

        let forecastData = try await request(url: hourlyURL)
        let forecast = try JSONDecoder().decode(NWSHourlyForecastResponse.self, from: forecastData)

        guard let period = forecast.properties.periods.first else {
            throw URLError(.cannotParseResponse)
        }

        let celsius: Double
        switch period.temperatureUnit.uppercased() {
        case "F":
            celsius = (period.temperature - 32) * 5 / 9
        case "C":
            celsius = period.temperature
        default:
            throw URLError(.cannotParseResponse)
        }

        AppLogger.shared.log("NWS weather fetch success: \(period.temperature)°\(period.temperatureUnit)", level: .debug)
        return celsius
    }

    private func fetchFromOpenMeteo(latitude: Double, longitude: Double) async throws -> Double {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "temperature_unit", value: "celsius")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        AppLogger.shared.log("Requesting Open-Meteo from \(url.absoluteString)", level: .debug)

        let data = try await request(url: url)
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return decoded.current.temperature2m
    }

    private func request(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            AppLogger.shared.log("Weather API bad response: HTTP \(httpResponse.statusCode) for \(url.host ?? "")", level: .error)
            throw URLError(.badServerResponse)
        }

        return data
    }

    static func formatTemperature(celsius: Double) -> String {
        let fahrenheit = celsius * 9 / 5 + 32
        let cRounded = Int(celsius.rounded())
        let fRounded = Int(fahrenheit.rounded())
        return "\(cRounded)°C / \(fRounded)°F"
    }
}

extension URLSession {
    static var configured: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }
}
