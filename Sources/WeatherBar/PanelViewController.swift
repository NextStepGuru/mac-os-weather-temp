import AppKit

/// The dropdown panel shown when the status item is clicked: a month calendar
/// plus an editable list of timezone clocks, with a ••• button exposing the
/// classic menu (refresh, logs, updates, settings, quit).
@MainActor
final class PanelViewController: NSViewController {
    private let calendar = CalendarGridCalculator.makeCalendar()
    private let timezoneStore: TimeZoneStore
    private let moreMenu: NSMenu
    private let statusLineProvider: () -> String?

    private var displayedMonthStart: Date
    private var isCalendarCollapsed = false
    private var refreshTimer: Timer?

    // Calendar header
    private let statusLineLabel = NSTextField(labelWithString: "")
    private let monthLabel = NSTextField(labelWithString: "")
    private let collapseButton = NSButton(title: "▾", target: nil, action: nil)
    private let previousMonthButton = NSButton(title: "‹", target: nil, action: nil)
    private let todayBadgeButton = NSButton(title: "", target: nil, action: nil)
    private let nextMonthButton = NSButton(title: "›", target: nil, action: nil)

    private let calendarGridContainer = NSView()

    // Timezones
    private let timezoneHeaderLabel = NSTextField(labelWithString: "TIMEZONES")
    private let addTimezoneButton = NSButton(title: "+ Add", target: nil, action: nil)
    private let resetTimezoneButton = NSButton(title: "Reset", target: nil, action: nil)
    private let timezoneScroll = NSScrollView()
    private let timezoneStack = NSStackView()

    // Add-timezone section
    private let addSectionContainer = NSView()
    private let searchField = NSSearchField()
    private let suggestionsScroll = NSScrollView()
    private let suggestionsStack = NSStackView()

    // Footer
    private let moreButton = NSButton(title: "•••", target: nil, action: nil)

    init(
        moreMenu: NSMenu,
        statusLineProvider: @escaping () -> String?,
        timezoneStore: TimeZoneStore = TimeZoneStore()
    ) {
        self.moreMenu = moreMenu
        self.statusLineProvider = statusLineProvider
        self.timezoneStore = timezoneStore
        self.displayedMonthStart = CalendarGridCalculator.startOfMonth(
            containing: Date(),
            calendar: CalendarGridCalculator.makeCalendar()
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 344, height: 660))
        view = root

        configureHeaderControls()
        configureTimezoneList()
        configureAddSection()
        moreButton.target = self
        moreButton.action = #selector(showMoreMenu)
        moreButton.isBordered = false
        moreButton.contentTintColor = .secondaryLabelColor

        let calendarHeader = NSStackView(views: [collapseButton, monthLabel, spacer(), previousMonthButton, todayBadgeButton, nextMonthButton])
        calendarHeader.orientation = .horizontal
        calendarHeader.spacing = 6

        let timezoneHeaderRow = NSStackView(views: [timezoneHeaderLabel, spacer(), addTimezoneButton, resetTimezoneButton])
        timezoneHeaderRow.orientation = .horizontal
        timezoneHeaderRow.spacing = 8

        let footer = NSStackView(views: [spacer(), moreButton])
        footer.orientation = .horizontal

        let rootStack = NSStackView(views: [
            statusLineLabel,
            calendarHeader,
            calendarGridContainer,
            timezoneHeaderRow,
            timezoneScroll,
            addSectionContainer,
            footer
        ])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 10
        rootStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 10, right: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: root.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            rootStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            calendarHeader.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            timezoneHeaderRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            statusLineLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            calendarGridContainer.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            addSectionContainer.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            timezoneScroll.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -28),
            timezoneScroll.heightAnchor.constraint(equalToConstant: 300)
        ])

        preferredContentSize = NSSize(width: 344, height: 660)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.view.window != nil else { return }
                self.refresh()
            }
        }
        refresh()
    }

    private func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return spacer
    }

    private func configureHeaderControls() {
        statusLineLabel.font = .systemFont(ofSize: 12)
        statusLineLabel.textColor = .secondaryLabelColor
        statusLineLabel.lineBreakMode = .byTruncatingTail

        monthLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        collapseButton.target = self
        collapseButton.action = #selector(toggleCollapse)
        collapseButton.isBordered = false
        collapseButton.contentTintColor = .secondaryLabelColor

        for button in [previousMonthButton, nextMonthButton] {
            button.target = self
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.font = .systemFont(ofSize: 15, weight: .medium)
        }
        previousMonthButton.action = #selector(previousMonth)
        nextMonthButton.action = #selector(nextMonth)

        todayBadgeButton.target = self
        todayBadgeButton.action = #selector(jumpToToday)
        todayBadgeButton.isBordered = false
        todayBadgeButton.font = .systemFont(ofSize: 12, weight: .semibold)
        todayBadgeButton.wantsLayer = true
        todayBadgeButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        todayBadgeButton.layer?.cornerRadius = 5
        todayBadgeButton.contentTintColor = .white
        todayBadgeButton.toolTip = "Back to today"
    }

    private func configureTimezoneList() {
        timezoneHeaderLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        timezoneHeaderLabel.textColor = .tertiaryLabelColor

        for button in [addTimezoneButton, resetTimezoneButton] {
            button.target = self
            button.isBordered = false
            button.font = .systemFont(ofSize: 11)
            button.contentTintColor = .secondaryLabelColor
        }
        addTimezoneButton.action = #selector(toggleAddSection)
        resetTimezoneButton.action = #selector(resetTimezones)

        timezoneStack.orientation = .vertical
        timezoneStack.alignment = .leading
        timezoneStack.spacing = 2
        timezoneStack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        timezoneStack.translatesAutoresizingMaskIntoConstraints = false

        timezoneScroll.hasVerticalScroller = true
        timezoneScroll.drawsBackground = false
        timezoneScroll.documentView = timezoneStack
        timezoneScroll.autohidesScrollers = true
    }

    private func configureAddSection() {
        addSectionContainer.isHidden = true

        searchField.placeholderString = "Search timezones (e.g. Tokyo)"
        searchField.font = .systemFont(ofSize: 12)
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        suggestionsStack.orientation = .vertical
        suggestionsStack.alignment = .leading
        suggestionsStack.spacing = 0
        suggestionsStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        suggestionsStack.translatesAutoresizingMaskIntoConstraints = false

        suggestionsScroll.hasVerticalScroller = true
        suggestionsScroll.drawsBackground = false
        suggestionsScroll.documentView = suggestionsStack
        suggestionsScroll.translatesAutoresizingMaskIntoConstraints = false

        addSectionContainer.translatesAutoresizingMaskIntoConstraints = false
        addSectionContainer.addSubview(searchField)
        addSectionContainer.addSubview(suggestionsScroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: addSectionContainer.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: addSectionContainer.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: addSectionContainer.trailingAnchor),

            suggestionsScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            suggestionsScroll.leadingAnchor.constraint(equalTo: addSectionContainer.leadingAnchor),
            suggestionsScroll.trailingAnchor.constraint(equalTo: addSectionContainer.trailingAnchor),
            suggestionsScroll.bottomAnchor.constraint(equalTo: addSectionContainer.bottomAnchor),
            suggestionsScroll.heightAnchor.constraint(equalToConstant: 170),

            addSectionContainer.heightAnchor.constraint(equalToConstant: 210)
        ])
    }

    // MARK: - Refresh

    func refresh() {
        refreshStatusLine()
        refreshCalendar()
        refreshTimezones()
        refreshSuggestions()
    }

    private func refreshStatusLine() {
        statusLineLabel.stringValue = statusLineProvider() ?? ""
        statusLineLabel.isHidden = statusLineLabel.stringValue.isEmpty
    }

    private func refreshCalendar() {
        let now = Date()
        monthLabel.stringValue = CalendarGridCalculator.monthTitle(for: displayedMonthStart, calendar: calendar)
        todayBadgeButton.title = "\(calendar.component(.day, from: now))"

        calendarGridContainer.subviews.forEach { $0.removeFromSuperview() }

        var rows: [[NSView]] = [
            (["CW"] + CalendarGridCalculator.weekdayHeaders(calendar: calendar)).map { headerLabel($0) }
        ]
        for week in CalendarGridCalculator.weeks(for: displayedMonthStart, today: now, calendar: calendar) {
            var row: [NSView] = [weekLabel("\(week.weekNumber)")]
            row.append(contentsOf: week.days.map { dayCellView($0) })
            rows.append(row)
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 1
        grid.columnSpacing = 0
        grid.translatesAutoresizingMaskIntoConstraints = false
        calendarGridContainer.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: calendarGridContainer.centerXAnchor),
            grid.topAnchor.constraint(equalTo: calendarGridContainer.topAnchor, constant: 4),
            grid.bottomAnchor.constraint(equalTo: calendarGridContainer.bottomAnchor)
        ])
    }

    private func headerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.widthAnchor.constraint(equalToConstant: text == "CW" ? 26 : 38).isActive = true
        return label
    }

    private func weekLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        label.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return label
    }

    private func dayCellView(_ cell: CalendarDayCell) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 38).isActive = true
        container.heightAnchor.constraint(equalToConstant: 40).isActive = true

        if cell.isToday {
            let badge = NSView()
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            badge.layer?.cornerRadius = 6
            badge.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                badge.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -2),
                badge.widthAnchor.constraint(equalToConstant: 30),
                badge.heightAnchor.constraint(equalToConstant: 22)
            ])
        }

        let label = NSTextField(labelWithString: "\(cell.dayNumber)")
        label.font = .systemFont(ofSize: 13, weight: cell.isToday ? .semibold : .regular)
        label.textColor = cell.isToday ? .white : (cell.isCurrentMonth ? .labelColor : .tertiaryLabelColor)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let dot = DotView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dot)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            dot.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            dot.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
            dot.widthAnchor.constraint(equalToConstant: 3),
            dot.heightAnchor.constraint(equalToConstant: 3)
        ])
        return container
    }

    // MARK: - Timezones

    private func refreshTimezones() {
        let now = Date()
        timezoneStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in timezoneStore.entries {
            timezoneStack.addArrangedSubview(timezoneRowView(entry, now: now))
        }
        timezoneStack.widthAnchor.constraint(equalTo: timezoneScroll.contentView.widthAnchor).isActive = true
    }

    private func timezoneRowView(_ entry: TimeZoneEntry, now: Date) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let timeZone = TimeZone(identifier: entry.identifier) ?? .current
        let nameLabel = NSTextField(labelWithString: entry.label)
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let todayLabel = NSTextField(labelWithString: "Today")
        todayLabel.font = .systemFont(ofSize: 11)
        todayLabel.textColor = .secondaryLabelColor
        todayLabel.translatesAutoresizingMaskIntoConstraints = false

        let (time, meridiem) = TimeZoneDisplay.timeComponents(for: timeZone, date: now)
        let timeText = NSMutableAttributedString(
            string: time,
            attributes: [
                .font: NSFont.systemFont(ofSize: 26, weight: .light),
                .foregroundColor: NSColor.labelColor
            ]
        )
        if !meridiem.isEmpty {
            timeText.append(NSAttributedString(
                string: " \(meridiem)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ))
        }
        let timeLabel = NSTextField(labelWithAttributedString: timeText)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        let offsetLabel = NSTextField(labelWithString: TimeZoneDisplay.offsetText(for: timeZone, date: now))
        offsetLabel.font = .systemFont(ofSize: 10)
        offsetLabel.textColor = .tertiaryLabelColor
        offsetLabel.alignment = .right
        offsetLabel.translatesAutoresizingMaskIntoConstraints = false

        let removeButton = NSButton(title: "–", target: self, action: #selector(removeTimezone(_:)))
        removeButton.isBordered = false
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.identifier = NSUserInterfaceItemIdentifier(entry.identifier)
        removeButton.toolTip = "Remove \(entry.label)"
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(nameLabel)
        row.addSubview(todayLabel)
        row.addSubview(timeLabel)
        row.addSubview(offsetLabel)
        row.addSubview(removeButton)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),

            nameLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -4),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: -8),

            todayLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            todayLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: 10),

            removeButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            removeButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 18),

            timeLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -4),
            timeLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: -8),

            offsetLabel.trailingAnchor.constraint(equalTo: timeLabel.trailingAnchor),
            offsetLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: -4)
        ])
        return row
    }

    // MARK: - Add-timezone suggestions

    private func refreshSuggestions() {
        suggestionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let existing = timezoneStore.entries.map(\.identifier)
        for identifier in TimeZoneDisplay.suggestions(matching: searchField.stringValue, existing: existing) {
            let button = NSButton(title: TimeZoneDisplay.cityLabel(fromIdentifier: identifier), target: self, action: #selector(addSuggested(_:)))
            button.isBordered = false
            button.font = .systemFont(ofSize: 12)
            button.contentTintColor = .labelColor
            button.identifier = NSUserInterfaceItemIdentifier(identifier)
            button.toolTip = identifier
            suggestionsStack.addArrangedSubview(button)
        }
        suggestionsStack.widthAnchor.constraint(equalTo: suggestionsScroll.contentView.widthAnchor).isActive = true
    }

    // MARK: - Actions

    @objc private func previousMonth() {
        displayedMonthStart = CalendarGridCalculator.monthByAddingMonths(-1, to: displayedMonthStart, calendar: calendar)
        refreshCalendar()
    }

    @objc private func nextMonth() {
        displayedMonthStart = CalendarGridCalculator.monthByAddingMonths(1, to: displayedMonthStart, calendar: calendar)
        refreshCalendar()
    }

    @objc private func jumpToToday() {
        displayedMonthStart = CalendarGridCalculator.startOfMonth(containing: Date(), calendar: calendar)
        refreshCalendar()
    }

    @objc private func toggleCollapse() {
        isCalendarCollapsed.toggle()
        collapseButton.title = isCalendarCollapsed ? "▸" : "▾"
        calendarGridContainer.isHidden = isCalendarCollapsed
    }

    @objc private func toggleAddSection() {
        addSectionContainer.isHidden.toggle()
        if !addSectionContainer.isHidden {
            view.window?.makeFirstResponder(searchField)
        }
    }

    @objc private func resetTimezones() {
        timezoneStore.resetToDefaults()
        refreshTimezones()
        refreshSuggestions()
    }

    @objc private func searchChanged() {
        refreshSuggestions()
    }

    @objc private func addSuggested(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        timezoneStore.add(TimeZoneEntry(label: TimeZoneDisplay.cityLabel(fromIdentifier: identifier), identifier: identifier))
        refreshTimezones()
        refreshSuggestions()
    }

    @objc private func removeTimezone(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        timezoneStore.remove(identifier: identifier)
        refreshTimezones()
        refreshSuggestions()
    }

    @objc private func showMoreMenu() {
        moreMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.maxY + 4), in: moreButton)
    }
}

/// The small decorative dot under each calendar day (matches the reference look).
final class DotView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
