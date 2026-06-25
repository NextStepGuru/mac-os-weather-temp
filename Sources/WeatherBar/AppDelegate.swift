import AppKit
import CoreLocation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let locationProvider = LocationProvider()
    private let weatherService = WeatherService()
    private let geocodingService = GeocodingService()

    private var statusMenuItem: NSMenuItem?
    private var loginItemMenuItem: NSMenuItem?
    private var refreshTimer: Timer?
    private var lastLocation: CLLocation?
    private var lastPlaceInfo: PlaceInfo?
    private var lastUpdated: Date?
    private var isFetching = false
    private var isGeocoding = false
    private var loginItemError: String?

    private let refreshInterval: TimeInterval = 10 * 60
    private let coordinateTolerance = 0.01

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupLocationProvider()
        startRefreshTimer()
        enableLoginItemIfNeeded()
        locationProvider.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        } catch {
            loginItemError = "Login item failed: \(error.localizedDescription)"
            loginItemMenuItem?.state = .off
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
        refreshWeather()
    }

    @objc private func toggleLoginItem() {
        do {
            if LoginItemManager.isEnabled {
                try LoginItemManager.disable()
                loginItemMenuItem?.state = .off
            } else {
                try LoginItemManager.enable()
                loginItemMenuItem?.state = .on
            }
            loginItemError = nil
        } catch {
            loginItemError = "Login item failed: \(error.localizedDescription)"
            loginItemMenuItem?.state = LoginItemManager.isEnabled ? .on : .off
            updateStatusMenu()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        let locationChanged = lastLocation.map {
            abs($0.coordinate.latitude - location.coordinate.latitude) > coordinateTolerance
                || abs($0.coordinate.longitude - location.coordinate.longitude) > coordinateTolerance
        } ?? true

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
        updateStatusMenu()

        Task {
            do {
                let placeInfo = try await geocodingService.reverseGeocode(location: location)
                self.isGeocoding = false
                self.lastPlaceInfo = placeInfo
                self.updateStatusMenu()
                self.refreshWeather()
            } catch {
                self.isGeocoding = false
                self.lastPlaceInfo = nil
                self.updateStatusMenu()
                self.refreshWeather()
            }
        }
    }

    private func handleLocationDenied() {
        statusItem.button?.title = "!°"
        statusMenuItem?.title = "Location denied — enable in System Settings → Privacy & Security → Location Services"
    }

    private func handleError(_ message: String) {
        statusItem.button?.title = "!°"
        statusMenuItem?.title = message
    }

    private func refreshWeather() {
        guard let location = lastLocation else { return }
        guard !isFetching else { return }

        isFetching = true
        updateStatusMenu()

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        Task {
            do {
                let celsius = try await weatherService.currentTemperatureC(
                    latitude: latitude,
                    longitude: longitude
                )

                self.isFetching = false
                self.lastUpdated = Date()
                self.statusItem.button?.title = WeatherService.formatTemperature(celsius: celsius)
                self.updateStatusMenu()
            } catch {
                self.isFetching = false
                self.statusItem.button?.title = "!°"
                self.statusMenuItem?.title = "Weather fetch failed: \(error.localizedDescription)"
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

            if let lastUpdated {
                let updatedTime = placeInfo.formatTime(lastUpdated)
                text += " · Updated \(updatedTime)"
            } else if isFetching {
                text += " · Refreshing…"
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

            statusMenuItem.title = text
        } else if isFetching {
            statusMenuItem.title = "Refreshing…"
        }
    }
}
