import Foundation

/// The menu-bar clock: `Wed, Oct 14 11:05 AM` next to the temperature.
enum MenuBarClock {
    static func text(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d h:mm a"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

struct TimeZoneEntry: Codable, Equatable {
    var label: String
    var identifier: String
}

/// Persisted, ordered list of timezone rows for the panel. Falls back to the
/// four US zones when nothing is stored (or everything was removed) so the
/// panel is never empty.
@MainActor
final class TimeZoneStore {
    static let defaultsKey = "panelTimezoneEntries"

    static let defaultEntries: [TimeZoneEntry] = [
        TimeZoneEntry(label: "Eastern", identifier: "America/New_York"),
        TimeZoneEntry(label: "Central", identifier: "America/Chicago"),
        TimeZoneEntry(label: "Mountain", identifier: "America/Denver"),
        TimeZoneEntry(label: "Pacific", identifier: "America/Los_Angeles")
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var entries: [TimeZoneEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([TimeZoneEntry].self, from: data),
              !decoded.isEmpty else {
            return Self.defaultEntries
        }
        return decoded
    }

    func add(_ entry: TimeZoneEntry) {
        var current = entries
        guard !current.contains(where: { $0.identifier == entry.identifier }) else { return }
        current.append(entry)
        persist(current)
    }

    func remove(identifier: String) {
        persist(entries.filter { $0.identifier != identifier })
    }

    func resetToDefaults() {
        persist(Self.defaultEntries)
    }

    private func persist(_ value: [TimeZoneEntry]) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Display helpers for the panel's timezone clock rows.
enum TimeZoneDisplay {
    /// Curated starter suggestions when the search field is empty; typing
    /// searches every known IANA identifier instead.
    static let curatedSuggestions: [String] = [
        "UTC",
        "Europe/London",
        "Europe/Dublin",
        "Europe/Paris",
        "Europe/Berlin",
        "Europe/Madrid",
        "Europe/Rome",
        "Europe/Amsterdam",
        "Asia/Jerusalem",
        "Asia/Dubai",
        "Asia/Kolkata",
        "Asia/Singapore",
        "Asia/Hong_Kong",
        "Asia/Shanghai",
        "Asia/Tokyo",
        "Australia/Sydney",
        "Australia/Melbourne",
        "America/Sao_Paulo",
        "America/Toronto",
        "America/Vancouver",
        "America/Mexico_City",
        "America/Phoenix",
        "America/Anchorage",
        "Pacific/Honolulu"
    ]

    static func cityLabel(fromIdentifier identifier: String) -> String {
        guard let city = identifier.split(separator: "/").last, !city.isEmpty else { return identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    static func offsetText(for timeZone: TimeZone, date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "UTC" }
        let totalMinutes = abs(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let sign = seconds < 0 ? "-" : "+"
        let offset = minutes == 0 ? "\(hours) h" : String(format: "%d:%02d", hours, minutes)
        return "UTC \(sign)\(offset)"
    }

    /// "11:03" + "AM" split so the panel can style the meridiem smaller.
    static func timeComponents(for timeZone: TimeZone, date: Date) -> (time: String, meridiem: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = timeZone
        let text = formatter.string(from: date)
        let parts = text.split(separator: " ").map(String.init)
        guard let time = parts.first else { return (text, "") }
        return (time, parts.dropFirst().joined(separator: " "))
    }

    static func suggestions(matching query: String, existing identifiers: [String]) -> [String] {
        let pool: [String]
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            pool = curatedSuggestions
        } else {
            pool = TimeZone.knownTimeZoneIdentifiers.filter { $0.localizedCaseInsensitiveContains(query) }
        }
        return pool
            .filter { !identifiers.contains($0) }
            .sorted()
    }
}
