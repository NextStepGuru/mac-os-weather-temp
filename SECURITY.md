# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Preferred**: Open a [GitHub Security Advisory](https://github.com/NextStepGuru/mac-os-weather-temp/security/advisories/new) (private).
2. **Alternative**: Open a GitHub issue with minimal details and ask for a private channel.

Please do **not** disclose security issues publicly until they have been reviewed and addressed.

We aim to acknowledge reports within a few business days.

## Scope

WeatherBar is a local macOS menu bar application. Security-relevant areas include:

- **Network requests**: coordinates are sent to weather APIs ([NWS](https://www.weather.gov/documentation/services-web-api), [Open-Meteo](https://open-meteo.com/)) and geocoding services (Apple CoreLocation, [ipapi.co](https://ipapi.co/) as a fallback). No user accounts or credentials are stored.
- **Location data**: GPS coordinates are used locally and sent only to the services above for weather and place lookup. IP-based fallback is used only when GPS is unavailable.
- **Persistence**: manual location settings are stored in `UserDefaults` on the local machine.
- **Login item**: uses macOS `SMAppService` for optional launch-at-login.

Out of scope: vulnerabilities in third-party APIs, macOS itself, or issues requiring physical access to an unlocked machine.

## Best Practices for Users

- Install from the official repository or a release you trust.
- Review Location Services permissions in **System Settings → Privacy & Security**.
- Use **View Logs** in the app menu to inspect network and location activity.
