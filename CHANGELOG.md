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

### Fixed

- Self-update quit the app without installing or relaunching: the detached
  install script was killed immediately (its `Process` object was deallocated)
  and its staged bundle was deleted by a cleanup path before it could copy it.
  The installer now spawns fully detached in its own session, stages the new
  bundle in a stable directory, swaps with a backup and rollback, and
  relaunches the app automatically (relaunching the old app if anything fails).
- Wrong city (e.g. San Francisco) behind a corporate VPN: IP geolocation
  resolves to the network's exit point, not the user's location. The app now
  caches the last real GPS fix and prefers it over IP fallback for up to 7
  days, labels it `Last known` in the menu, and offers a one-click
  **Location Looks Wrong? Set It Manually…** menu item whenever the location
  is approximate.

### Added

- Log viewer gained **Copy All**, **Save As…**, and **Refresh** buttons so
  logs can be captured and shared for diagnosis.
- **Allow Location Access…** menu item that opens System Settings directly to
  Privacy & Security → Location Services — the reliable grant path when the
  permission prompt never appears (common on MDM-managed corporate Macs).
- Location-source diagnostics: startup inventory of every location source
  (authorization, Location Services, cached GPS fix, manual override), active
  VPN tunnel detection, and MDM-management detection, plus an explicit log of
  why IP geolocation was chosen and what its VPN-egress limitations are.

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
