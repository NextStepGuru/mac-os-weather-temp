import Foundation
import Testing
@testable import WeatherBar

struct CalendarAndClockTests {
    private let calendar = CalendarGridCalculator.makeCalendar()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, minute: Int = 0, timeZoneIdentifier: String = "America/New_York") -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: timeZoneIdentifier)
        return CalendarGridCalculator.makeCalendar().date(from: components)!
    }

    @Test func menuBarClockFormatsWeekdayMonthDayTime() {
        let date = date(2026, 10, 14, 11, minute: 5, timeZoneIdentifier: "America/New_York")
        // 2026-10-14 is a Wednesday.
        #expect(MenuBarClock.text(for: date, timeZone: TimeZone(identifier: "America/New_York")!) == "Wed, Oct 14 11:05 AM")
    }

    @Test func menuBarClockHandlesSingleDigitDayAndPM() {
        let date = date(2026, 10, 5, 15, timeZoneIdentifier: "America/New_York")
        let text = MenuBarClock.text(for: date, timeZone: TimeZone(identifier: "America/New_York")!)
        #expect(text == "Mon, Oct 5 3:00 PM")
    }

    @Test func october2026GridMatchesReferenceLayout() {
        let monthStart = CalendarGridCalculator.startOfMonth(containing: date(2026, 10, 14), calendar: calendar)
        let weeks = CalendarGridCalculator.weeks(for: monthStart, today: date(2026, 10, 14), calendar: calendar)

        // Six fixed rows, ISO week numbers 40–45 like the reference screenshot.
        #expect(weeks.count == 6)
        #expect(weeks.map(\.weekNumber) == [40, 41, 42, 43, 44, 45])

        // First row starts on Sunday Sep 27; Oct 1 lands under Thursday.
        #expect(weeks[0].days[0].dayNumber == 27)
        #expect(!weeks[0].days[0].isCurrentMonth)
        #expect(weeks[0].days[4].dayNumber == 1)
        #expect(weeks[0].days[4].isCurrentMonth)

        // Today is Oct 14 (Wednesday of week 42).
        #expect(weeks[2].days[0].dayNumber == 11)
        #expect(weeks[2].days[3].isToday)
        #expect(weeks.flatMap(\.days).filter(\.isToday).count == 1)

        // Trailing days bleed into November.
        #expect(weeks[5].days[6].dayNumber == 7)
        #expect(!weeks[5].days[6].isCurrentMonth)
    }

    @Test func monthTitleAndNavigation() {
        let october = CalendarGridCalculator.startOfMonth(containing: date(2026, 10, 14), calendar: calendar)
        #expect(CalendarGridCalculator.monthTitle(for: october, calendar: calendar) == "October 2026")
        let november = CalendarGridCalculator.monthByAddingMonths(1, to: october, calendar: calendar)
        #expect(CalendarGridCalculator.monthTitle(for: november, calendar: calendar) == "November 2026")
    }

    @Test func weekdayHeadersAreSundayFirst() {
        #expect(CalendarGridCalculator.weekdayHeaders(calendar: calendar).first == "Sun")
        #expect(CalendarGridCalculator.weekdayHeaders(calendar: calendar).count == 7)
    }

    @Test func timezoneOffsetText() {
        let date = date(2026, 10, 14, 16, timeZoneIdentifier: "UTC")
        #expect(TimeZoneDisplay.offsetText(for: TimeZone(identifier: "America/New_York")!, date: date) == "UTC -4 h")
        #expect(TimeZoneDisplay.offsetText(for: TimeZone(identifier: "America/Los_Angeles")!, date: date) == "UTC -7 h")
        #expect(TimeZoneDisplay.offsetText(for: TimeZone(identifier: "Europe/London")!, date: date) == "UTC +1 h")
        #expect(TimeZoneDisplay.offsetText(for: TimeZone(identifier: "UTC")!, date: date) == "UTC")
        #expect(TimeZoneDisplay.offsetText(for: TimeZone(identifier: "Asia/Kolkata")!, date: date) == "UTC +5:30")
    }

    @Test func timezoneTimeComponentsSplitMeridiem() {
        let date = date(2026, 10, 14, 16, timeZoneIdentifier: "UTC")
        let (time, meridiem) = TimeZoneDisplay.timeComponents(for: TimeZone(identifier: "America/New_York")!, date: date)
        #expect(time == "12:00")
        #expect(meridiem == "PM")
    }

    @Test func cityLabelFromIdentifier() {
        #expect(TimeZoneDisplay.cityLabel(fromIdentifier: "Europe/London") == "London")
        #expect(TimeZoneDisplay.cityLabel(fromIdentifier: "America/New_York") == "New York")
        #expect(TimeZoneDisplay.cityLabel(fromIdentifier: "Asia/Tel_Aviv") == "Tel Aviv")
        #expect(TimeZoneDisplay.cityLabel(fromIdentifier: "UTC") == "UTC")
    }

    @Test func suggestionsExcludeExistingAndFilterByQuery() {
        let empty = TimeZoneDisplay.suggestions(matching: "", existing: ["America/New_York"])
        #expect(empty.contains("Europe/London"))
        #expect(!empty.contains("America/New_York"))

        let filtered = TimeZoneDisplay.suggestions(matching: "lond", existing: [])
        #expect(filtered == ["Europe/London"])

        let existing = TimeZoneDisplay.suggestions(matching: "lond", existing: ["Europe/London"])
        #expect(existing.isEmpty)
    }
}

@MainActor
struct TimeZoneStoreTests {
    private let suiteName = "WeatherBarTimeZoneTests.\(UUID().uuidString)"

    private func makeStore() -> TimeZoneStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TimeZoneStore(defaults: defaults)
    }

    @Test func defaultsAreTheFourUSZones() {
        let store = makeStore()
        #expect(store.entries == TimeZoneStore.defaultEntries)
        #expect(store.entries.map(\.label) == ["Eastern", "Central", "Mountain", "Pacific"])
        #expect(store.entries.map(\.identifier) == [
            "America/New_York",
            "America/Chicago",
            "America/Denver",
            "America/Los_Angeles"
        ])
    }

    @Test func addPersistsAndDeduplicates() {
        let store = makeStore()
        store.add(TimeZoneEntry(label: "London", identifier: "Europe/London"))
        store.add(TimeZoneEntry(label: "London", identifier: "Europe/London"))

        #expect(store.entries.count == 5)
        #expect(store.entries.last == TimeZoneEntry(label: "London", identifier: "Europe/London"))

        // A second store over the same defaults sees the persisted entry.
        #expect(TimeZoneStore(defaults: UserDefaults(suiteName: suiteName)!).entries.count == 5)
    }

    @Test func removePersists() {
        let store = makeStore()
        store.remove(identifier: "America/Chicago")
        #expect(!store.entries.contains { $0.identifier == "America/Chicago" })
        #expect(store.entries.count == 3)
    }

    @Test func resetRestoresUSDefaults() {
        let store = makeStore()
        store.add(TimeZoneEntry(label: "Tokyo", identifier: "Asia/Tokyo"))
        store.remove(identifier: "America/Denver")
        store.resetToDefaults()
        #expect(store.entries == TimeZoneStore.defaultEntries)
    }
}
