import Foundation

extension SchoolAssignment {
    func normalizedAllDayEnd(using calendar: Calendar) -> Date? {
        guard isAllDay, let endDate else {
            return nil
        }
        let adjusted = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        return adjusted
    }

    func displayEndDate(using calendar: Calendar) -> Date? {
        if isAllDay {
            if let normalizedEnd = normalizedAllDayEnd(using: calendar) {
                return calendar.endOfDay(for: normalizedEnd) ?? normalizedEnd
            }
            return calendar.endOfDay(for: dueDate) ?? dueDate
        }
        return endDate
    }

    var usesFallbackEnd: Bool {
        isAllDay && endDate == nil
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date? {
        if let startOfNextDay = self.date(byAdding: .day, value: 1, to: startOfDay(for: date)) {
            return self.date(byAdding: .second, value: -1, to: startOfNextDay)
        }
        return self.date(bySettingHour: 23, minute: 59, second: 59, of: date)
    }
}
