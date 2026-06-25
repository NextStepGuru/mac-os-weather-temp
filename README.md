# WeatherBar

A lightweight macOS menu bar app that shows the current temperature in Celsius and Fahrenheit (e.g. `25°C / 77°F`) based on your GPS location.

## Requirements

- macOS 13+
- Swift 6+ (Command Line Tools or Xcode)
- Internet access for weather data

## Build

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

This compiles a release binary, assembles `WeatherBar.app`, and ad-hoc signs it.

## Install (recommended)

For reliable login autostart, copy the app to `/Applications`:

```bash
cp -R WeatherBar.app /Applications/
open /Applications/WeatherBar.app
```

## Run

```bash
open ./WeatherBar.app
```

On first launch, macOS will prompt for **Location Services** permission. Allow access so the app can determine your coordinates.

If Gatekeeper blocks the app (ad-hoc signed), right-click the app → **Open**, or allow it in **System Settings → Privacy & Security**.

## Behavior

- **Menu bar**: displays current temperature as `25°C / 77°F`
- **Dropdown**: shows city/state, local time with timezone (e.g. `Gold Beach, OR · 8:53 AM PST · Updated 8:53 AM`)
- **Location tracking**: uses CoreLocation with ~3 km distance filter; re-fetches when you move
- **Auto-refresh**: updates every 10 minutes
- **Login autostart**: enabled by default on first launch; toggle via **Open at Login** in the menu

## Weather data

Temperatures are fetched from [Open-Meteo](https://open-meteo.com/) (free, no API key required).

City, state, and timezone come from Apple's reverse geocoding (CoreLocation).

## Project structure

```
Package.swift
Sources/WeatherBar/
  main.swift
  AppDelegate.swift
  LocationProvider.swift
  WeatherService.swift
  GeocodingService.swift
  LoginItemManager.swift
Resources/Info.plist
scripts/build_app.sh
```
