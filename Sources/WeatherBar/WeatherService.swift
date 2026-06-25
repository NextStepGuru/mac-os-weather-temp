import Foundation

struct WeatherService {
    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature2m: Double

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
            }
        }

        let current: Current
    }

    func currentTemperatureC(latitude: Double, longitude: Double) async throws -> Double {
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

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return decoded.current.temperature2m
    }

    static func formatTemperature(celsius: Double) -> String {
        let fahrenheit = celsius * 9 / 5 + 32
        let cRounded = Int(celsius.rounded())
        let fRounded = Int(fahrenheit.rounded())
        return "\(cRounded)°C / \(fRounded)°F"
    }
}
