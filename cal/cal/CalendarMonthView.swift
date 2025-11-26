import SwiftUI

struct CalendarMonthView: View {
    @State private var monthAnchor: Date
    @State private var selectedDate: Date?
    @State private var isPresentingYearPicker = false
    @State private var yearPickerSelection: Int
    private let calendar: Calendar
    private let onDayTap: ((Date) -> Void)?
    private let eventsProvider: ((Date) -> Int?)?

    init(calendar: Calendar = Calendar(identifier: .gregorian), onDayTap: ((Date) -> Void)? = nil, eventsProvider: ((Date) -> Int?)? = nil) {
    var configuredCalendar = calendar
    // Use the device locale so month/weekday names appear in the user's language
    configuredCalendar.locale = Locale.current
        configuredCalendar.timeZone = .current
        configuredCalendar.firstWeekday = 1 // Sunday

        self.calendar = configuredCalendar
        let now = Date()
        let initialMonth = configuredCalendar.startOfMonth(for: now) ?? now
        let clamped = configuredCalendar.clampedMonth(initialMonth)
        _monthAnchor = State(initialValue: clamped)
        _selectedDate = State(initialValue: configuredCalendar.clampedDay(now))
        let initialYear = configuredCalendar.component(.year, from: clamped)
        _isPresentingYearPicker = State(initialValue: false)
        _yearPickerSelection = State(initialValue: initialYear)
        self.onDayTap = onDayTap
        self.eventsProvider = eventsProvider
    }

    var body: some View {
        VStack(spacing: 16) {
            monthHeader
            weekdayHeader
            monthGrid
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: monthAnchor)
        .sheet(isPresented: $isPresentingYearPicker) {
            NavigationStack {
                VStack(spacing: 24) {
                    yearSelector
                    monthGridForSelection
                    Spacer()
                }
                .padding(.top)
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            yearPickerSelection = calendar.component(.year, from: monthAnchor)
                            isPresentingYearPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private extension CalendarMonthView {
    var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .padding(8)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(monthFormatter.string(from: monthAnchor))
                .font(.title2.bold())
                .contentShape(Rectangle())
                .onTapGesture {
                    yearPickerSelection = calendar.component(.year, from: monthAnchor)
                    isPresentingYearPicker = true
                }

            Spacer()

            Button("Today") {
                jumpToMonth(Date())
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .padding(.horizontal, -10)
            .accessibilityLabel("Jump to current month")

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .padding(8)
            }
            .accessibilityLabel("Next month")
        }
    }

    var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .frame(maxWidth: .infinity)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(daysInMonth) { day in
                CalendarDayCell(
                    day: day,
                    isSelected: dayMatchesSelected(day.date),
                    isToday: calendar.isDateInToday(day.date),
                    eventsCount: eventsProvider?(day.date)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard day.isWithinDisplayedMonth else { return }
                    selectedDate = day.date
                    onDayTap?(day.date)
                }
            }
        }
    }

    var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
    // Use a year + full month format (localized via calendar.locale)
    formatter.dateFormat = "yyyy MMMM"
        return formatter
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstWeekdayIndex = max(calendar.firstWeekday - 1, 0)
        let leading = Array(symbols[firstWeekdayIndex...])
        let trailing = Array(symbols[..<firstWeekdayIndex])
        return leading + trailing
    }

    var daysInMonth: [CalendarDay] {
        guard let metadata = calendar.monthMetadata(for: monthAnchor) else {
            return []
        }

        let firstDay = metadata.firstDay
        let leadingDays = metadata.leadingDays
        let trailingDays = metadata.trailingDays
        let numberOfDays = metadata.numberOfDays

        let previousMonthDays = (0..<leadingDays).compactMap { offset -> CalendarDay? in
            guard let day = calendar.date(byAdding: .day, value: offset - leadingDays, to: firstDay) else {
                return nil
            }
            let number = calendar.component(.day, from: day)
            return CalendarDay(date: day, number: number, isWithinDisplayedMonth: false)
        }

        let currentMonthDays = (0..<numberOfDays).compactMap { offset -> CalendarDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            return CalendarDay(date: day, number: offset + 1, isWithinDisplayedMonth: true)
        }

        let lastDayOfMonth = calendar.date(byAdding: .day, value: numberOfDays - 1, to: firstDay) ?? firstDay

        let nextMonthDays: [CalendarDay]
        if trailingDays > 0 {
            nextMonthDays = (1...trailingDays).compactMap { offset -> CalendarDay? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: lastDayOfMonth) else {
                    return nil
                }
                let number = calendar.component(.day, from: day)
                return CalendarDay(date: day, number: number, isWithinDisplayedMonth: false)
            }
        } else {
            nextMonthDays = []
        }

        return previousMonthDays + currentMonthDays + nextMonthDays
    }

    func shiftMonth(by value: Int) {
        guard let updatedMonth = calendar.date(byAdding: .month, value: value, to: monthAnchor) else {
            return
        }
        monthAnchor = calendar.clampedMonth(updatedMonth)
        selectedDate = calendar.clampedDay(monthAnchor)
        yearPickerSelection = calendar.component(.year, from: monthAnchor)

        // Update selection so the day stays within the new month when possible
        if let selected = selectedDate,
           !calendar.isDate(selected, equalTo: monthAnchor, toGranularity: .month) {
            selectedDate = calendar.clampedDay(monthAnchor)
        }
    }

    func dayMatchesSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func jumpToMonth(_ date: Date) {
        let clamped = calendar.clampedMonth(date)
        monthAnchor = clamped
        selectedDate = calendar.clampedDay(clamped)
        yearPickerSelection = calendar.component(.year, from: clamped)
    }

    var yearSelector: some View {
        let currentYear = calendar.component(.year, from: Date())
        let range = (currentYear - 100)...(currentYear + 50)
        let rowHeight: CGFloat = 32
        let visibleRows: CGFloat = 7.5

        return Picker("Year", selection: $yearPickerSelection) {
            ForEach(range, id: \.self) { year in
                Text(yearDescription(year))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .tag(year)
            }
        }
        .pickerStyle(.wheel)
        .clipped()
        .padding(.horizontal, 8)
    }

    var monthGridForSelection: some View {
        let months = calendar.monthSymbols.indices.map { $0 + 1 }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(months, id: \.self) { month in
                Button {
                    jumpToYear(yearPickerSelection, month: month)
                    isPresentingYearPicker = false
                } label: {
                    Text(shortMonthName(for: month))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(monthButtonBackground(month: month))

                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    func shortMonthName(for month: Int) -> String {
        let symbols = calendar.shortMonthSymbols
        guard month - 1 < symbols.count else { return "\(month)" }
        return symbols[month - 1]
    }

    func monthButtonBackground(month: Int) -> Color {
        let currentMonth = calendar.component(.month, from: monthAnchor)
        let currentYear = calendar.component(.year, from: monthAnchor)
        if currentYear == yearPickerSelection && currentMonth == month {
            return Color.accentColor.opacity(0.2)
        }
        return Color(.secondarySystemBackground)
    }

    func jumpToYear(_ year: Int, month: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        if let date = calendar.date(from: components) {
            jumpToMonth(date)
        }
    }

    func yearDescription(_ year: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: year)) ?? "\(year)"
    }
}

struct CalendarDay: Identifiable {
    let id: String
    let date: Date
    let number: Int
    let isWithinDisplayedMonth: Bool

    init(date: Date, number: Int, isWithinDisplayedMonth: Bool) {
        self.date = date
        self.number = number
        self.isWithinDisplayedMonth = isWithinDisplayedMonth
        self.id = "\(Int(date.timeIntervalSinceReferenceDate))-\(number)-\(isWithinDisplayedMonth)"
    }
}

struct MonthMetadata {
    let numberOfDays: Int
    let firstDay: Date
    let leadingDays: Int
    let trailingDays: Int
}

private extension Calendar {
    var minimumAllowedDate: Date {
        var components = DateComponents()
        components.year = 1900
        components.month = 1
        components.day = 1
        return self.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    var maximumAllowedDate: Date {
        var components = DateComponents()
        components.year = 2099
        components.month = 12
        components.day = 31
        return self.date(from: components) ?? Date.distantFuture
    }

    func clampedMonth(_ date: Date) -> Date {
        guard let monthStart = startOfMonth(for: date) else { return date }
        if monthStart < minimumAllowedDate {
            return startOfMonth(for: minimumAllowedDate) ?? minimumAllowedDate
        }
        if monthStart > maximumAllowedDate {
            return startOfMonth(for: maximumAllowedDate) ?? maximumAllowedDate
        }
        return monthStart
    }

    func clampedDay(_ date: Date) -> Date {
        if date < minimumAllowedDate {
            return minimumAllowedDate
        }
        if date > maximumAllowedDate {
            return maximumAllowedDate
        }
        return date
    }

    func startOfMonth(for date: Date) -> Date? {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components)
    }

    func monthMetadata(for date: Date) -> MonthMetadata? {
        guard let start = startOfMonth(for: date),
              let range = range(of: .day, in: .month, for: start) else {
            return nil
        }

        let numberOfDays = range.count
        let firstWeekday = component(.weekday, from: start)
        let offset = (firstWeekday - self.firstWeekday + 7) % 7
        let leadingDays = offset
        let totalDays = leadingDays + numberOfDays
        let trailingDays = (7 - (totalDays % 7)) % 7

        return MonthMetadata(
            numberOfDays: numberOfDays,
            firstDay: start,
            leadingDays: leadingDays,
            trailingDays: trailingDays
        )
    }
}
