import Foundation

enum Weekday: Int, CaseIterable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

struct RoutineItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var timeOfDay: DateComponents
    var isEnabled: Bool
    var weekdays: Set<Int>
}

let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
let r = RoutineItem(id: UUID(), title: "Test", timeOfDay: comps, isEnabled: true, weekdays: Set([1,2,3]))
let arr = [r]
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted]
encoder.dateEncodingStrategy = .iso8601

do {
    let data = try encoder.encode(arr)
    if let s = String(data: data, encoding: .utf8) {
        print("Encoded JSON:\n\(s)")
    }
} catch {
    print("Encode failed: \(error)")
}
