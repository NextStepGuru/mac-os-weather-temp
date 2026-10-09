# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Open source documentation, MIT license, CI workflow, and GitHub templates.
- Universal binary (`arm64` + `x86_64`) for native Intel Mac support.
- Detailed diagnostics logging: readable location-authorization statuses, system
  Location Services state, per-fix GPS accuracy/age, per-request HTTP status,
  latency and byte counts, and VPN/firewall-aware descriptions for weather,
  IP-geolocation, and geocoding failures (DNS blocks, TLS interception, timeouts).

### Fixed

- No-weather hang when the location permission prompt is never answered: a
  30-second watchdog now re-prompts, logs actionable diagnostics, and falls back
  to IP-based location instead of sitting at "Locating…" forever.
- **Refresh now** retries IP-based location when no location is available
  instead of silently skipping the weather fetch.

### Changed

- CI and `scripts/test.sh` run tests on arm64 only; releases still ship a
  universal (`arm64` + `x86_64`) binary.

## [0.1.0] - 2026-03-23

### Added

- Menu bar temperature display in Celsius and Fahrenheit (e.g. `25°C / 77°F`).
- Dropdown with city/state, local time, timezone, and last-updated timestamp.
- GPS location tracking via CoreLocation (~3 km distance filter).
- Manual location override via **Settings…** (saved across launches).
- IP-based location fallback when GPS is denied or unavailable, labeled `Approx (IP)`.
- Persistent last valid temperature when weather fetch fails (no `!°` wipe).
- Dual weather providers: NWS (primary) and Open-Meteo (fallback).
- Auto-refresh every 10 minutes and **Refresh now** menu action.
- Login autostart via **Open at Login** (enabled by default on first launch).
- In-app log viewer (**View Logs**).

[Unreleased]: https://github.com/NextStepGuru/mac-os-weather-temp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/NextStepGuru/mac-os-weather-temp/releases/tag/v0.1.0
