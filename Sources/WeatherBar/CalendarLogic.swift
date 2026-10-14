import Foundation

struct CalendarDayCell: Equatable {
    let date: Date
    let dayNumber: Int
    let isCurrentMonth: Bool
    let isToday: Bool
}

struct CalendarWeek: Equatable {
    let weekNumber: Int
    let days: [CalendarDayCell]
}

/// Pure month-grid math for the panel calendar: Sunday-first, six fixed rows,
/// ISO week numbers (the "CW" column), adjacent-month days flagged for graying.
enum CalendarGridCalculator {
    static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        return calendar
    }

    static func startOfMonth(containing date: Date, calendar: Calendar = makeCalendar()) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func monthByAddingMonths(_ months: Int, to monthStart: Date, calendar: Calendar = makeCalendar()) -> Date {
        calendar.date(byAdding: .month, value: months, to: monthStart) ?? monthStart
    }

    static func monthTitle(for monthStart: Date, calendar: Calendar = makeCalendar()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter.string(from: monthStart)
    }

    static func weeks(for monthStart: Date, today: Date, calendar: Calendar = makeCalendar()) -> [CalendarWeek] {
        let isoCalendar = Calendar(identifier: .iso8601)
        let firstDayOffset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -firstDayOffset, to: monthStart) else {
            return []
        }
        let todayStart = calendar.startOfDay(for: today)

        var weeks: [CalendarWeek] = []
        for weekIndex in 0..<6 {
            guard let weekStart = calendar.date(byAdding: .day, value: weekIndex * 7, to: gridStart) else {
                continue
            }
            var days: [CalendarDayCell] = []
            for dayIndex in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: dayIndex, to: weekStart) else { continue }
                days.append(CalendarDayCell(
                    date: day,
                    dayNumber: calendar.component(.day, from: day),
                    isCurrentMonth: calendar.isDate(day, equalTo: monthStart, toGranularity: .month),
                    isToday: calendar.startOfDay(for: day) == todayStart
                ))
            }
            // Label the row by the ISO week of its Thursday: a Sunday-start row
            // straddles two ISO weeks (Sunday closes the previous one), and the
            // Thursday is unambiguous — it matches reference calendar layouts.
            let thursday = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
            weeks.append(CalendarWeek(
                weekNumber: isoCalendar.component(.weekOfYear, from: thursday),
                days: days
            ))
        }
        return weeks
    }

    static func weekdayHeaders(calendar: Calendar = makeCalendar()) -> [String] {
        calendar.shortWeekdaySymbols
    }
}
