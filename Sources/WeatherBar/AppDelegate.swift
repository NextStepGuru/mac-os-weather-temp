import AppKit
import CoreLocation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let locationProvider = LocationProvider()
    private let weatherService = WeatherService()
    private let geocodingService = GeocodingService()
    private let ipLocationService = IPLocationService()
    private let updateService = UpdateService()

    private var statusMenuItem: NSMenuItem?
    private var loginItemMenuItem: NSMenuItem?
    private var updateAvailableMenuItem: NSMenuItem?
    private var checkUpdatesMenuItem: NSMenuItem?
    private var automaticUpdatesMenuItem: NSMenuItem?
    private var refreshTimer: Timer?
    private var updateTimer: Timer?
    private var availableUpdate: ReleaseInfo?
    private var isCheckingForUpdate = false
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
    private var isLocating = true
    private var gpsGraceTimer: Timer?

    private let refreshInterval: TimeInterval = 10 * 60
    private let updateCheckInterval: TimeInterval = UpdateSettings.defaultCheckInterval
    private let coordinateTolerance = 0.01
    private let gpsGracePeriod: TimeInterval = 12

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.log("WeatherBar launched")
        setupStatusItem()
        setupLocationProvider()
        startRefreshTimer()
        enableLoginItemIfNeeded()
        restoreManualLocationIfNeeded()
        if !isManualOverride {
            requestLocationPermissionOnLaunch()
        }
        startUpdateTimer()
        scheduleInitialUpdateCheck()
    }

    private func requestLocationPermissionOnLaunch() {
        // Agent apps (LSUIElement) often suppress the permission sheet unless active.
        NSApp.activate(ignoringOtherApps: true)
        locationProvider.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.shared.log("WeatherBar terminating")
        gpsGraceTimer?.invalidate()
        refreshTimer?.invalidate()
        updateTimer?.invalidate()
        locationProvider.stop()
    }

    private func setupStatusItem() {
        statusItem.button?.title = "--°"

        let menu = NSMenu()

        let statusLine = NSMenuItem(title: "Locating…", action: nil, keyEquivalent: "")
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

        let checkUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = self
        self.checkUpdatesMenuItem = checkUpdatesItem
        menu.addItem(checkUpdatesItem)

        let updateAvailableItem = NSMenuItem(
            title: "Update available",
            action: #selector(installAvailableUpdate),
            keyEquivalent: ""
        )
        updateAvailableItem.target = self
        updateAvailableItem.isHidden = true
        self.updateAvailableMenuItem = updateAvailableItem
        menu.addItem(updateAvailableItem)

        let automaticUpdatesItem = NSMenuItem(
            title: "Automatic Updates",
            action: #selector(toggleAutomaticUpdates),
            keyEquivalent: ""
        )
        automaticUpdatesItem.target = self
        automaticUpdatesItem.state = updateService.isAutomaticUpdatesEnabled ? .on : .off
        self.automaticUpdatesMenuItem = automaticUpdatesItem
        menu.addItem(automaticUpdatesItem)

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

        locationProvider.onAuthorizationChanged = { [weak self] status in
            Task { @MainActor in
                self?.handleAuthorizationChange(status)
            }
        }

        locationProvider.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleError(error.localizedDescription)
            }
        }
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard !isManualOverride else { return }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            updateStatusMenu()
            startGPSGracePeriod()
        case .denied, .restricted:
            cancelGPSGracePeriod()
            isLocating = false
            AppLogger.shared.log("Location permission denied", level: .error)
            attemptIPFallback(
                reason: .denied,
                deniedMessage: "Location denied — enable in System Settings → Privacy & Security → Location Services"
            )
        case .notDetermined:
            isLocating = true
            updateStatusMenu()
        @unknown default:
            break
        }
    }

    private func startGPSGracePeriod() {
        cancelGPSGracePeriod()
        gpsGraceTimer = Timer.scheduledTimer(withTimeInterval: gpsGracePeriod, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleGPSGraceTimeout()
            }
        }
    }

    private func cancelGPSGracePeriod() {
        gpsGraceTimer?.invalidate()
        gpsGraceTimer = nil
    }

    private func handleGPSGraceTimeout() {
        guard !isManualOverride else { return }
        guard lastGPSLocation == nil else { return }

        AppLogger.shared.log("GPS grace period expired without a fix", level: .warning)
        isLocating = false
        attemptIPFallback(
            reason: .graceTimeout,
            deniedMessage: "Unable to determine location — enable Location Services or check GPS signal"
        )
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

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performUpdateCheck(force: false, showUserFeedback: false)
            }
        }
    }

    private func scheduleInitialUpdateCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            Task { @MainActor in
                await self?.performUpdateCheck(force: false, showUserFeedback: false)
            }
        }
    }

    private func performUpdateCheck(force: Bool, showUserFeedback: Bool) async {
        if isCheckingForUpdate {
            if showUserFeedback {
                showUpdateCheckInProgressAlert()
            }
            return
        }

        if !force, !updateService.shouldCheckForUpdate() {
            AppLogger.shared.log("Update check skipped (checked recently)", level: .debug)
            return
        }

        isCheckingForUpdate = true
        if showUserFeedback {
            setCheckUpdatesMenuItem(inProgress: true)
        }
        defer {
            isCheckingForUpdate = false
            if showUserFeedback {
                setCheckUpdatesMenuItem(inProgress: false)
            }
        }

        AppLogger.shared.log(force ? "Manual update check requested" : "Checking for updates")

        do {
            let release = try await updateService.checkForUpdate()
            updateService.recordUpdateCheck()

            guard let release else {
                clearAvailableUpdate()
                AppLogger.shared.log("WeatherBar is up to date")
                if showUserFeedback {
                    showUpToDateAlert()
                }
                return
            }

            AppLogger.shared.log("Update available: \(release.tag)")

            if showUserFeedback {
                let shouldInstall = showUpdateAvailableAlert(for: release)
                if shouldInstall {
                    await installUpdate(release, initiatedByUser: true)
                } else {
                    setAvailableUpdate(release)
                }
                return
            }

            if updateService.isAutomaticUpdatesEnabled, updateService.canSelfInstall() {
                await installUpdate(release, initiatedByUser: false)
            } else {
                setAvailableUpdate(release)
            }
        } catch {
            AppLogger.shared.log("Update check failed: \(error.localizedDescription)", level: .error)
            if showUserFeedback {
                showUpdateCheckFailedAlert(error: error)
            }
        }
    }

    private func installUpdate(_ release: ReleaseInfo, initiatedByUser: Bool) async {
        guard updateService.canSelfInstall() else {
            setAvailableUpdate(release)
            if initiatedByUser {
                showCannotSelfInstallAlert(for: release)
            } else {
                AppLogger.shared.log(
                    "Automatic update deferred: app is not running from a writable .app bundle",
                    level: .warning
                )
            }
            return
        }

        do {
            try await updateService.downloadAndInstall(release)
            AppLogger.shared.log("Terminating for update install")
            NSApplication.shared.terminate(nil)
        } catch {
            AppLogger.shared.log("Update install failed: \(error.localizedDescription)", level: .error)
            setAvailableUpdate(release)
            if initiatedByUser {
                showUpdateInstallFailedAlert(error: error)
            }
        }
    }

    private func setAvailableUpdate(_ release: ReleaseInfo) {
        availableUpdate = release
        updateAvailableMenuItem?.title = "Update available (\(release.tag)) — Install"
        updateAvailableMenuItem?.isHidden = false
    }

    private func clearAvailableUpdate() {
        availableUpdate = nil
        updateAvailableMenuItem?.isHidden = true
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        if let version = updateService.currentVersion() {
            alert.informativeText = "WeatherBar \(version) is the latest release."
        } else {
            alert.informativeText = "WeatherBar is the latest release."
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateAvailableAlert(for release: ReleaseInfo) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Update available"
        alert.informativeText = "WeatherBar \(release.tag) is available. Install now?"
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Later")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showCannotSelfInstallAlert(for release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "Manual update required"
        alert.informativeText = """
        WeatherBar \(release.tag) is available, but this copy cannot replace itself automatically. \
        Download the latest release from GitHub and move WeatherBar.app to /Applications.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateCheckFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update check failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateInstallFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateCheckInProgressAlert() {
        let alert = NSAlert()
        alert.messageText = "Checking for updates"
        alert.informativeText = "An update check is already in progress."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setCheckUpdatesMenuItem(inProgress: Bool) {
        checkUpdatesMenuItem?.title = inProgress ? "Checking for Updates…" : "Check for Updates…"
        checkUpdatesMenuItem?.isEnabled = !inProgress
    }

    @objc private func refreshNow() {
        AppLogger.shared.log("Manual refresh requested")
        refreshWeather()
    }

    @objc private func viewLogs() {
        LogViewerWindowController.show()
    }

    @objc private func checkForUpdates() {
        Task { @MainActor in
            await performUpdateCheck(force: true, showUserFeedback: true)
        }
    }

    @objc private func installAvailableUpdate() {
        guard let release = availableUpdate else { return }

        Task { @MainActor in
            await installUpdate(release, initiatedByUser: true)
        }
    }

    @objc private func toggleAutomaticUpdates() {
        updateService.setAutomaticUpdatesEnabled(!updateService.isAutomaticUpdatesEnabled)
        automaticUpdatesMenuItem?.state = updateService.isAutomaticUpdatesEnabled ? .on : .off
        AppLogger.shared.log(
            "Automatic updates \(updateService.isAutomaticUpdatesEnabled ? "enabled" : "disabled")"
        )
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
        isLocating = false
        cancelGPSGracePeriod()
        lastLocation = location
        lastPlaceInfo = place
        AppLogger.shared.log("Restored manual location: \(place.displayName)")
        updateStatusMenu()
        refreshWeather()
    }

    private func applyManualOverride(location: CLLocation, place: PlaceInfo, query: String) {
        isManualOverride = true
        isUsingIPFallback = false
        isLocating = false
        cancelGPSGracePeriod()
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
            isLocating = true
            updateStatusMenu()
            if isLocationAuthorized {
                startGPSGracePeriod()
            } else {
                requestLocationPermissionOnLaunch()
            }
        }
    }

    private var isLocationAuthorized: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        lastGPSLocation = location
        isUsingIPFallback = false
        isLocating = false
        cancelGPSGracePeriod()

        if isManualOverride {
            AppLogger.shared.log("GPS update ignored (manual override active)", level: .debug)
            return
        }

        let locationChanged = LocationChangeDetector.hasChanged(
            from: lastLocation,
            to: location,
            tolerance: coordinateTolerance
        )

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

    private func handleError(_ message: String) {
        AppLogger.shared.log("Location error: \(message)", level: .error)
    }

    private func attemptIPFallback(reason: IPFallbackReason, deniedMessage: String) {
        switch IPFallbackPolicy.shouldAttempt(
            reason: reason,
            isManualOverride: isManualOverride,
            lastGPSLocation: lastGPSLocation,
            ipFallbackAttempted: ipFallbackAttempted,
            lastLocation: lastLocation
        ) {
        case .skipManualOverride, .skipHasGPS:
            return
        case .alreadyAttempted(let showDenied):
            if showDenied {
                statusItem.button?.title = "!°"
                statusMenuItem?.title = deniedMessage
            }
            return
        case .attempt:
            break
        }

        ipFallbackAttempted = true
        AppLogger.shared.log("Attempting IP-based location fallback (\(reason))")

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
                if let title = WeatherDisplayPolicy.menuBarTitleOnFetchFailure(lastTemperatureText: self.lastTemperatureText) {
                    self.statusItem.button?.title = title
                }
                self.updateStatusMenu()
            }
        }
    }

    private func updateStatusMenu() {
        guard let statusMenuItem else { return }

        let input = StatusLineInput(
            loginItemError: loginItemError,
            isGeocoding: isGeocoding,
            placeInfo: lastPlaceInfo,
            location: lastPlaceInfo == nil ? lastLocation : nil,
            isManualOverride: isManualOverride,
            isUsingIPFallback: isUsingIPFallback,
            lastUpdated: lastUpdated,
            isFetching: isFetching,
            lastFetchFailed: lastFetchFailed,
            isLocating: isLocating,
            now: Date()
        )

        if let title = StatusLineFormatter.format(input) {
            statusMenuItem.title = title
        }
    }
}
