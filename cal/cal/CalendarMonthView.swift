import SwiftUI

struct CalendarMonthView: View {
    @State private var monthAnchor: Date
    @State private var selectedDate: Date?
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
        _monthAnchor = State(initialValue: configuredCalendar.clampedMonth(initialMonth))
        _selectedDate = State(initialValue: configuredCalendar.clampedDay(now))
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

            Spacer()

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
    }

    func dayMatchesSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
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
        components.year = 2000
        components.month = 1
        components.day = 1
        return self.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    var maximumAllowedDate: Date {
        var components = DateComponents()
        components.year = 2030
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
