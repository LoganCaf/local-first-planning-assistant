import Foundation
import SwiftUI

enum Weekday: Int, CaseIterable, Codable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var localizedShortName: String {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        // Calendar weekday symbols are 1..7 starting with Sunday
        let index = rawValue - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    var localizedTinyName: String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let index = rawValue - 1
        guard symbols.indices.contains(index) else { return localizedShortName }
        return symbols[index]
    }
}

struct RoutineItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var startTime: DateComponents
    var endTime: DateComponents
    var isEnabled: Bool
    var weekdays: Set<Int> // 1 = Sunday ... 7 = Saturday
    var iconName: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        title: String,
        startTime: DateComponents = Calendar.current.dateComponents([.hour, .minute], from: Date()),
        endTime: DateComponents? = nil,
        isEnabled: Bool = true,
        weekdays: Set<Int>? = nil,
        iconName: String = "repeat",
        colorHex: String = RoutineItem.defaultColorHex
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        if let e = endTime {
            self.endTime = e
        } else {
            var comps = startTime
            let hour = (comps.hour ?? 0) + 1
            comps.hour = hour % 24
            self.endTime = comps
        }
        self.isEnabled = isEnabled
        if let w = weekdays {
            self.weekdays = w
        } else {
            self.weekdays = Set(1...7)
        }
        self.iconName = iconName
        self.colorHex = colorHex
    }

    var isEveryDay: Bool {
        weekdays.count == 7
    }

    func weekdayDisplayString() -> String {
        if isEveryDay { return NSLocalizedString("Every day", comment: "Routine repeats every day") }
        let names = Weekday.allCases.filter { weekdays.contains($0.rawValue) }.map { $0.localizedShortName }
        return names.joined(separator: ", ")
    }

    func timeRangeString() -> String {
        let cal = Calendar.current
        if let s = cal.date(from: startTime), let e = cal.date(from: endTime) {
            let fmt = DateFormatter()
            fmt.timeStyle = .short
            return "\(fmt.string(from: s)) - \(fmt.string(from: e))"
        }
        return ""
    }
}

// Backwards-compatible Codable conformance: older JSON may not include iconName
extension RoutineItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, startTime, endTime, isEnabled, weekdays, iconName, colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startTime = try container.decode(DateComponents.self, forKey: .startTime)
        endTime = try container.decode(DateComponents.self, forKey: .endTime)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        weekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? Set(1...7)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "repeat"
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? RoutineItem.defaultColorHex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encode(iconName, forKey: .iconName)
        try container.encode(colorHex, forKey: .colorHex)
    }
}

extension RoutineItem {
    static let defaultColorHex = "#4F8DFF"

    var color: Color {
        Color(hex: colorHex)
    }
}
