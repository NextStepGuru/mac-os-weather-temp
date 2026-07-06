import AppKit
import CoreLocation

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var instance: SettingsWindowController?

    var onApplyManual: ((CLLocation, PlaceInfo, String) -> Void)?
    var onDisableManual: (() -> Void)?

    private let geocodingService = GeocodingService()
    private let overrideCheckbox = NSButton(checkboxWithTitle: "Override location with a manual entry", target: nil, action: nil)
    private let locationField = NSTextField()
    private let validateButton = NSButton(title: "Validate & Save", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private var isValidating = false

    static func show(
        onApplyManual: @escaping (CLLocation, PlaceInfo, String) -> Void,
        onDisableManual: @escaping () -> Void
    ) {
        if let instance {
            instance.onApplyManual = onApplyManual
            instance.onDisableManual = onDisableManual
            instance.loadFromStore()
            instance.window?.makeKeyAndOrderFront(nil)
        } else {
            let controller = SettingsWindowController()
            controller.onApplyManual = onApplyManual
            controller.onDisableManual = onDisableManual
            instance = controller
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))

        overrideCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let locationLabel = NSTextField(labelWithString: "Place:")
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        locationField.translatesAutoresizingMaskIntoConstraints = false
        locationField.placeholderString = "e.g. Portland, OR"
        locationField.bezelStyle = .roundedBezel

        validateButton.translatesAutoresizingMaskIntoConstraints = false
        validateButton.bezelStyle = .rounded

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        contentView.addSubview(overrideCheckbox)
        contentView.addSubview(locationLabel)
        contentView.addSubview(locationField)
        contentView.addSubview(validateButton)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            overrideCheckbox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            overrideCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            overrideCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            locationLabel.topAnchor.constraint(equalTo: overrideCheckbox.bottomAnchor, constant: 16),
            locationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            locationLabel.widthAnchor.constraint(equalToConstant: 44),

            locationField.centerYAnchor.constraint(equalTo: locationLabel.centerYAnchor),
            locationField.leadingAnchor.constraint(equalTo: locationLabel.trailingAnchor, constant: 8),
            locationField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            validateButton.topAnchor.constraint(equalTo: locationField.bottomAnchor, constant: 16),
            validateButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            statusLabel.topAnchor.constraint(equalTo: validateButton.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WeatherBar Settings"
        window.contentView = contentView
        window.center()
        window.setFrameAutosaveName("WeatherBarSettings")

        super.init(window: window)
        window.delegate = self

        overrideCheckbox.target = self
        overrideCheckbox.action = #selector(overrideToggled)
        validateButton.target = self
        validateButton.action = #selector(validateAndSave)

        loadFromStore()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadFromStore() {
        overrideCheckbox.state = SettingsStore.manualOverrideEnabled ? .on : .off
        locationField.stringValue = SettingsStore.manualLocationQuery
        updateControlsEnabled()
        updateStatusFromStore()
    }

    private func updateControlsEnabled() {
        let enabled = overrideCheckbox.state == .on && !isValidating
        locationField.isEnabled = enabled
        validateButton.isEnabled = enabled
    }

    private func updateStatusFromStore() {
        guard SettingsStore.manualOverrideEnabled,
              let (_, place) = SettingsStore.loadManualLocation() else {
            setStatus("", color: .secondaryLabelColor)
            return
        }
        setStatus("Current: \(place.displayName)", color: .secondaryLabelColor)
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }

    @objc private func overrideToggled() {
        if overrideCheckbox.state == .off {
            SettingsStore.clearManualLocation()
            onDisableManual?()
            setStatus("Using GPS location", color: .secondaryLabelColor)
        } else {
            setStatus("Enter a place and click Validate & Save", color: .secondaryLabelColor)
        }
        updateControlsEnabled()
    }

    @objc private func validateAndSave() {
        let query = locationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            setStatus("Please enter a place name or address", color: .systemRed)
            return
        }

        isValidating = true
        updateControlsEnabled()
        setStatus("Validating…", color: .secondaryLabelColor)

        Task {
            do {
                let result = try await geocodingService.forwardGeocode(address: query)
                SettingsStore.saveManualLocation(query: query, location: result.location, place: result.place)
                onApplyManual?(result.location, result.place, query)
                setStatus("Saved: \(result.place.displayName)", color: .systemGreen)
                AppLogger.shared.log("Manual location saved: \(result.place.displayName) (\(query))")
            } catch {
                setStatus(error.localizedDescription, color: .systemRed)
                AppLogger.shared.log("Manual location validation failed: \(error.localizedDescription)", level: .warning)
            }

            isValidating = false
            updateControlsEnabled()
        }
    }
}
