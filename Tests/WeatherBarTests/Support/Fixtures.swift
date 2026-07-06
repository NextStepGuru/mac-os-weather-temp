import Foundation

enum Fixtures {
    static let nwsPoints = """
    {
        "properties": {
            "forecastHourly": "https://api.weather.gov/gridpoints/MFR/55,88/forecast/hourly"
        }
    }
    """

    static func nwsHourly(temperature: Double, unit: String) -> String {
        """
        {
            "properties": {
                "periods": [
                    {
                        "temperature": \(temperature),
                        "temperatureUnit": "\(unit)"
                    }
                ]
            }
        }
        """
    }

    static let nwsHourlyEmpty = """
    {
        "properties": {
            "periods": []
        }
    }
    """

    static func openMeteo(temperatureC: Double) -> String {
        """
        {
            "current": {
                "temperature_2m": \(temperatureC)
            }
        }
        """
    }

    static let ipapiSuccess = """
    {
        "latitude": 45.5152,
        "longitude": -122.6784,
        "city": "Portland",
        "region": "Oregon",
        "region_code": "OR",
        "timezone": "America/Los_Angeles"
    }
    """

    static let ipapiError = """
    {
        "error": true,
        "reason": "Rate limited"
    }
    """

    static let ipapiMissingCoords = """
    {
        "city": "Portland",
        "region": "Oregon"
    }
    """

    static let ipapiMinimalFields = """
    {
        "latitude": 40.0,
        "longitude": -100.0
    }
    """

    static let ipapiRegionFallback = """
    {
        "latitude": 40.0,
        "longitude": -100.0,
        "region": "Nebraska"
    }
    """

    static let githubLatestRelease = """
    {
        "tag_name": "v1.2.0",
        "assets": [
            {
                "browser_download_url": "https://github.com/NextStepGuru/mac-os-weather-temp/releases/download/v1.2.0/WeatherBar-v1.2.0.zip"
            },
            {
                "browser_download_url": "https://github.com/NextStepGuru/mac-os-weather-temp/releases/download/v1.2.0/notes.txt"
            }
        ]
    }
    """
}
