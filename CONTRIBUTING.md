# Contributing to WeatherBar

Thank you for your interest in contributing! WeatherBar is a small macOS menu bar app written in Swift.

## Getting started

### Prerequisites

- macOS 13 or later
- Swift 6+ (Xcode or Command Line Tools)
- Internet access (weather and geocoding APIs)

### Build and run

```bash
# Quick compile check
swift build

# Build a signed .app bundle
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open ./WeatherBar.app
```

For reliable login autostart, copy the app to `/Applications/` before running.

### CI

Pull requests must pass the GitHub Actions workflow (`.github/workflows/ci.yml`), which runs `swift build -c release` on macOS.

There are no automated tests yet — manual testing on macOS is required. Adding unit tests is a welcome future contribution.

## How to contribute

1. Fork the repository and create a branch from `main`.
2. Make your changes with clear, focused commits.
3. Test locally: build the app, verify menu bar behavior, and check **View Logs** for errors.
4. Open a pull request against `main` using the PR template.

## Code style

- Match existing Swift conventions in the project (4-space indentation, `@MainActor` where appropriate).
- Keep changes focused — one logical change per PR when possible.
- Use `AppLogger.shared.log(...)` for diagnostic output instead of `print`.
- Prefer small, single-purpose types (e.g. `WeatherService`, `IPLocationService`).

## Commit messages

Use clear, imperative subject lines:

- `Add IP fallback when location is denied`
- `Fix menu bar not updating after manual override`

## Reporting issues

- **Bugs**: use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md). Include macOS version and logs from **View Logs**.
- **Features**: use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md).
- **Security**: see [SECURITY.md](SECURITY.md).

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Please be respectful and constructive.
