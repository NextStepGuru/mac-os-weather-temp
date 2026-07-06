import AppKit
import CoreLocation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let locationProvider = LocationProvider()
    private let weatherService = WeatherService()
    private let geocodingService = GeocodingService()
    private let ipLocationService = IPLocationService()

    private var statusMenuItem: NSMenuItem?
    private var loginItemMenuItem: NSMenuItem?
    private var refreshTimer: Timer?
    private var lastLocation: CLLocation?
    private var lastPlaceInfo: PlaceInfo?
    private var lastUpdated: Date?
    private var lastTemperatureText: String?
    private var lastFetchFailed = false
    private var isFetching = false
    private var isGeocoding = false
    private var loginItemError: String?
    private var isManualOverride = false
    private var lastGPSLocation: CLLocation?
    private var isUsingIPFallback = false
    private var ipFallbackAttempted = false

    private let refreshInterval: TimeInterval = 10 * 60
    private let coordinateTolerance = 0.01

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.log("WeatherBar launched")
        setupStatusItem()
        setupLocationProvider()
        startRefreshTimer()
        enableLoginItemIfNeeded()
        restoreManualLocationIfNeeded()
        locationProvider.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.shared.log("WeatherBar terminating")
        refreshTimer?.invalidate()
        locationProvider.stop()
    }

    private func setupStatusItem() {
        statusItem.button?.title = "--°"

        let menu = NSMenu()

        let statusLine = NSMenuItem(title: "Refreshing…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        self.statusMenuItem = statusLine
        menu.addItem(statusLine)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let viewLogsItem = NSMenuItem(title: "View Logs", action: #selector(viewLogs), keyEquivalent: "")
        viewLogsItem.target = self
        menu.addItem(viewLogsItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        self.loginItemMenuItem = loginItem
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    private func setupLocationProvider() {
        locationProvider.onLocationUpdate = { [weak self] location in
            Task { @MainActor in
                self?.handleLocationUpdate(location)
            }
        }

        locationProvider.onAuthorizationDenied = { [weak self] in
            Task { @MainActor in
                self?.handleLocationDenied()
            }
        }

        locationProvider.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleError(error.localizedDescription)
            }
        }
    }

    private func enableLoginItemIfNeeded() {
        guard !LoginItemManager.isEnabled else {
            loginItemMenuItem?.state = .on
            return
        }

        do {
            try LoginItemManager.enable()
            loginItemMenuItem?.state = .on
            loginItemError = nil
            AppLogger.shared.log("Login item enabled on launch")
        } catch {
            loginItemError = "Login item failed: \(error.localizedDescription)"
            loginItemMenuItem?.state = .off
            AppLogger.shared.log("Login item enable failed: \(error.localizedDescription)", level: .error)
            updateStatusMenu()
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWeather()
            }
        }
    }

    @objc private func refreshNow() {
        AppLogger.shared.log("Manual refresh requested")
        refreshWeather()
    }

    @objc private func viewLogs() {
        LogViewerWindowController.show()
    }

    @objc private func openSettings() {
        SettingsWindowController.show(
            onApplyManual: { [weak self] location, place, query in
                self?.applyManualOverride(location: location, place: place, query: query)
            },
            onDisableManual: { [weak self] in
                self?.disableManualOverride()
            }
        )
    }

    @objc private func toggleLoginItem() {
        do {
            if LoginItemManager.isEnabled {
                try LoginItemManager.disable()
                loginItemMenuItem?.state = .off
                AppLogger.shared.log("Login item disabled")
            } else {
                try LoginItemManager.enable()
                loginItemMenuItem?.state = .on
                AppLogger.shared.log("Login item enabled")
            }
            loginItemError = nil
        } catch {
            loginItemError = "Login item failed: \(error.localizedDescription)"
            loginItemMenuItem?.state = LoginItemManager.isEnabled ? .on : .off
            AppLogger.shared.log("Login item toggle failed: \(error.localizedDescription)", level: .error)
            updateStatusMenu()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func restoreManualLocationIfNeeded() {
        guard let (location, place) = SettingsStore.loadManualLocation() else { return }

        isManualOverride = true
        isUsingIPFallback = false
        lastLocation = location
        lastPlaceInfo = place
        AppLogger.shared.log("Restored manual location: \(place.displayName)")
        updateStatusMenu()
        refreshWeather()
    }

    private func applyManualOverride(location: CLLocation, place: PlaceInfo, query: String) {
        isManualOverride = true
        isUsingIPFallback = false
        lastLocation = location
        lastPlaceInfo = place
        SettingsStore.saveManualLocation(query: query, location: location, place: place)
        AppLogger.shared.log("Manual override enabled: \(place.displayName)")
        updateStatusMenu()
        refreshWeather()
    }

    private func disableManualOverride() {
        isManualOverride = false
        SettingsStore.clearManualLocation()
        AppLogger.shared.log("Manual override disabled, resuming GPS")

        if let gpsLocation = lastGPSLocation {
            lastLocation = gpsLocation
            reverseGeocode(gpsLocation)
        } else {
            lastLocation = nil
            lastPlaceInfo = nil
            updateStatusMenu()
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        lastGPSLocation = location
        isUsingIPFallback = false

        if isManualOverride {
            AppLogger.shared.log("GPS update ignored (manual override active)", level: .debug)
            return
        }

        let locationChanged = lastLocation.map {
            abs($0.coordinate.latitude - location.coordinate.latitude) > coordinateTolerance
                || abs($0.coordinate.longitude - location.coordinate.longitude) > coordinateTolerance
        } ?? true

        AppLogger.shared.log(
            "Location update: \(location.coordinate.latitude), \(location.coordinate.longitude) (changed: \(locationChanged))"
        )

        lastLocation = location

        if locationChanged || lastPlaceInfo == nil {
            reverseGeocode(location)
        } else {
            updateStatusMenu()
            refreshWeather()
        }
    }

    private func reverseGeocode(_ location: CLLocation) {
        isGeocoding = true
        AppLogger.shared.log("Starting reverse geocode")
        updateStatusMenu()

        Task {
            do {
                let placeInfo = try await geocodingService.reverseGeocode(location: location)
                self.isGeocoding = false
                self.lastPlaceInfo = placeInfo
                AppLogger.shared.log("Geocode success: \(placeInfo.displayName)")
                self.updateStatusMenu()
                self.refreshWeather()
            } catch {
                self.isGeocoding = false
                self.lastPlaceInfo = nil
                AppLogger.shared.log("Geocode failed: \(error.localizedDescription)", level: .warning)
                self.updateStatusMenu()
                self.refreshWeather()
            }
        }
    }

    private func handleLocationDenied() {
        AppLogger.shared.log("Location permission denied", level: .error)
        attemptIPFallback(
            deniedMessage: "Location denied — enable in System Settings → Privacy & Security → Location Services"
        )
    }

    private func handleError(_ message: String) {
        AppLogger.shared.log("Location error: \(message)", level: .error)
        guard lastLocation == nil else { return }
        attemptIPFallback(deniedMessage: message)
    }

    private func attemptIPFallback(deniedMessage: String) {
        guard !isManualOverride else { return }
        guard lastGPSLocation == nil else { return }
        guard !ipFallbackAttempted else {
            if lastLocation == nil {
                statusItem.button?.title = "!°"
                statusMenuItem?.title = deniedMessage
            }
            return
        }

        ipFallbackAttempted = true
        AppLogger.shared.log("Attempting IP-based location fallback")

        Task {
            do {
                let (location, place) = try await ipLocationService.lookup()
                self.isUsingIPFallback = true
                self.lastLocation = location
                self.lastPlaceInfo = place
                AppLogger.shared.log("IP fallback success: \(place.displayName)")
                self.updateStatusMenu()
                self.refreshWeather()
            } catch {
                AppLogger.shared.log("IP fallback failed: \(error.localizedDescription)", level: .error)
                if self.lastLocation == nil {
                    self.statusItem.button?.title = "!°"
                    self.statusMenuItem?.title = deniedMessage
                }
            }
        }
    }

    private func refreshWeather() {
        guard let location = lastLocation else {
            AppLogger.shared.log("Weather refresh skipped: no location yet", level: .debug)
            return
        }
        guard !isFetching else {
            AppLogger.shared.log("Weather refresh skipped: fetch already in progress", level: .debug)
            return
        }

        isFetching = true
        updateStatusMenu()

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        AppLogger.shared.log("Fetching weather for \(latitude), \(longitude)")

        Task {
            do {
                let celsius = try await weatherService.currentTemperatureC(
                    latitude: latitude,
                    longitude: longitude
                )

                self.isFetching = false
                self.lastUpdated = Date()
                self.lastFetchFailed = false
                let formatted = WeatherService.formatTemperature(celsius: celsius)
                self.lastTemperatureText = formatted
                AppLogger.shared.log("Weather fetch success: \(formatted)")
                self.statusItem.button?.title = formatted
                self.updateStatusMenu()
            } catch {
                self.isFetching = false
                self.lastFetchFailed = true
                AppLogger.shared.log("Weather fetch failed: \(error.localizedDescription)", level: .error)
                if self.lastTemperatureText == nil {
                    self.statusItem.button?.title = "!°"
                }
                self.updateStatusMenu()
            }
        }
    }

    private func updateStatusMenu() {
        guard let statusMenuItem else { return }

        if let loginItemError {
            statusMenuItem.title = loginItemError
            return
        }

        if isGeocoding {
            statusMenuItem.title = "Looking up location…"
            return
        }

        if let placeInfo = lastPlaceInfo {
            let now = Date()
            let localTime = placeInfo.formatTime(now)
            let tzAbbr = placeInfo.timeZoneAbbreviation(for: now)
            var text = "\(placeInfo.displayName) · \(localTime) \(tzAbbr)"

            if isManualOverride {
                text += " · Manual"
            }

            if isUsingIPFallback {
                text += " · Approx (IP)"
            }

            if let lastUpdated {
                let updatedTime = placeInfo.formatTime(lastUpdated)
                text += " · Updated \(updatedTime)"
            } else if isFetching {
                text += " · Refreshing…"
            }

            if lastFetchFailed {
                text += " · Update failed"
            }

            statusMenuItem.title = text
        } else if let location = lastLocation {
            let lat = String(format: "%.4f", location.coordinate.latitude)
            let lon = String(format: "%.4f", location.coordinate.longitude)
            var text = "Location: \(lat), \(lon)"

            if let lastUpdated {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                formatter.timeZone = .current
                text += " · Updated \(formatter.string(from: lastUpdated))"
            } else if isFetching {
                text += " · Refreshing…"
            }

            if lastFetchFailed {
                text += " · Update failed"
            }

            statusMenuItem.title = text
        } else if isFetching {
            statusMenuItem.title = "Refreshing…"
        }
    }
}
