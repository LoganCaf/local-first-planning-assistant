import Foundation

struct SchoolAssignment: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let dueDate: Date
    let endDate: Date?
    let isAllDay: Bool
    let description: String?
    let course: String?
    let location: String?
    let url: URL?
    var isCompleted: Bool
    var estimatedDurationMinutes: Int?
    var actualStartTime: Date?
    var actualEndTime: Date?
    var actualDurationSeconds: Double?
    var activeTimerStart: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueDate
        case endDate
        case isAllDay
        case details = "description"
        case course
        case location
        case url
        case isCompleted
        case estimatedDurationMinutes
        case actualStartTime
        case actualEndTime
        case actualDurationSeconds
        case activeTimerStart
    }

    init(
        id: String,
        title: String,
        dueDate: Date,
        endDate: Date?,
        isAllDay: Bool,
        description: String?,
        course: String?,
        location: String?,
        url: URL?,
        isCompleted: Bool,
        estimatedDurationMinutes: Int? = nil,
        actualStartTime: Date? = nil,
        actualEndTime: Date? = nil,
        actualDurationSeconds: Double? = nil,
        activeTimerStart: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.description = description
        self.course = course
        self.location = location
        self.url = url
        self.isCompleted = isCompleted
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.actualStartTime = actualStartTime
        self.actualEndTime = actualEndTime
        self.actualDurationSeconds = actualDurationSeconds
        self.activeTimerStart = activeTimerStart
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        description = try container.decodeIfPresent(String.self, forKey: .details)
        course = try container.decodeIfPresent(String.self, forKey: .course)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        estimatedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedDurationMinutes)
        actualStartTime = try container.decodeIfPresent(Date.self, forKey: .actualStartTime)
        actualEndTime = try container.decodeIfPresent(Date.self, forKey: .actualEndTime)
        actualDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .actualDurationSeconds)
        activeTimerStart = try container.decodeIfPresent(Date.self, forKey: .activeTimerStart)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encodeIfPresent(description, forKey: .details)
        try container.encodeIfPresent(course, forKey: .course)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(estimatedDurationMinutes, forKey: .estimatedDurationMinutes)
        try container.encodeIfPresent(actualStartTime, forKey: .actualStartTime)
        try container.encodeIfPresent(actualEndTime, forKey: .actualEndTime)
        try container.encodeIfPresent(actualDurationSeconds, forKey: .actualDurationSeconds)
        try container.encodeIfPresent(activeTimerStart, forKey: .activeTimerStart)
    }
}

struct CanvasICSParser {
    enum ParserError: Error {
        case invalidData
        case noEvents
    }

    func parseAssignments(from data: Data) throws -> [SchoolAssignment] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParserError.invalidData
        }

        let unfoldedLines = unfoldICS(content)
        let defaultTimeZone = extractCalendarTimeZone(from: unfoldedLines) ?? TimeZone.current
        let events = extractEvents(from: unfoldedLines)

        guard !events.isEmpty else {
            throw ParserError.noEvents
        }

        return events.compactMap { event in
            guard let titleField = event["SUMMARY"],
                  let primaryDateField = event["DUE"] ?? event["DTSTART"] ?? event["DTEND"],
                  let dueDate = parseDate(from: primaryDateField, defaultTimeZone: defaultTimeZone) else {
                return nil
            }

            let summaryText = titleField.value
            let cleanedTitle = summaryText.removingBracketedSuffix().trimmingCharacters(in: .whitespacesAndNewlines)
            let title = cleanedTitle.isEmpty ? summaryText : cleanedTitle
            let description = event["DESCRIPTION"]?.value
            let location = event["LOCATION"]?.value
            let courseContext = summaryText.bracketedContext()
            let isAllDay = primaryDateField.parameters["VALUE"]?.uppercased() == "DATE" || primaryDateField.value.count == 8
            let endDate = event["DTEND"].flatMap { parseDate(from: $0, defaultTimeZone: defaultTimeZone) }
            let url = event["URL"].flatMap { URL(string: $0.value) }
            let uid = event["UID"]?.value ?? UUID().uuidString
            let identifier = "\(uid)|\(primaryDateField.value)"

            return SchoolAssignment(
                id: identifier,
                title: title,
                dueDate: dueDate,
                endDate: endDate,
                isAllDay: isAllDay,
                description: description?.emptyToNil(),
                course: courseContext?.emptyToNil(),
                location: location?.emptyToNil(),
                url: url,
                isCompleted: false,
                estimatedDurationMinutes: nil
            )
        }
        .sorted { $0.dueDate < $1.dueDate }
    }
}

private extension CanvasICSParser {
    struct EventField {
        let value: String
        let parameters: [String: String]
    }

    typealias EventDictionary = [String: EventField]

    func unfoldICS(_ content: String) -> [String] {
        let lines = content.split(whereSeparator: \.isNewline)
        var unfolded: [String] = []

        for line in lines {
            if let last = unfolded.last, line.first == " " || line.first == "\t" {
                unfolded[unfolded.count - 1] = last + line.dropFirst()
            } else {
                unfolded.append(String(line))
            }
        }
        return unfolded
    }

    func extractEvents(from lines: [String]) -> [EventDictionary] {
        var events: [EventDictionary] = []
        var currentEvent: EventDictionary = [:]
        var isInEvent = false

        for line in lines {
            if line == "BEGIN:VEVENT" {
                currentEvent = [:]
                isInEvent = true
                continue
            }
            if line == "END:VEVENT" {
                if isInEvent {
                    events.append(currentEvent)
                }
                isInEvent = false
                continue
            }
            guard isInEvent else { continue }

            let components = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else { continue }

            let fieldKey = String(components[0])
            let value = String(components[1]).replacingOccurrences(of: "\\n", with: "\n")

            let keyAndParameters = fieldKey.split(separator: ";")
            guard let keyComponent = keyAndParameters.first else { continue }

            var parameters: [String: String] = [:]
            if keyAndParameters.count > 1 {
                for param in keyAndParameters.dropFirst() {
                    let pair = param.split(separator: "=", maxSplits: 1)
                    if pair.count == 2 {
                        parameters[String(pair[0]).uppercased()] = String(pair[1])
                    } else {
                        parameters[String(param).uppercased()] = ""
                    }
                }
            }

            let key = String(keyComponent)
            currentEvent[key] = EventField(value: value, parameters: parameters)
        }

        return events
    }

    func extractCalendarTimeZone(from lines: [String]) -> TimeZone? {
        if let tzLine = lines.first(where: { $0.hasPrefix("X-WR-TIMEZONE:") }) {
            let identifier = tzLine.replacingOccurrences(of: "X-WR-TIMEZONE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return TimeZone(identifier: identifier)
        }

        if let tzLine = lines.first(where: { $0.hasPrefix("TZID:") }) {
            let identifier = tzLine.replacingOccurrences(of: "TZID:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return TimeZone(identifier: identifier)
        }

        return nil
    }

    func parseDate(from field: EventField, defaultTimeZone: TimeZone) -> Date? {
        let rawValue = field.value
        let timezone = timeZone(for: field, default: defaultTimeZone)

        if field.parameters["VALUE"]?.uppercased() == "DATE" || rawValue.count == 8 {
            return parseFloatingDate(rawValue, timezone: timezone)
        }

        if rawValue.hasSuffix("Z"), let date = isoZuluFormatter.date(from: rawValue) {
            return date
        }

        if let formatter = dateTimeFormatter(for: timezone),
           let date = formatter.date(from: rawValue) {
            return date
        }

        let isoFormatter = isoGeneralFormatter
        isoFormatter.timeZone = timezone
        if let date = isoFormatter.date(from: rawValue) {
            return date
        }

        return nil
    }

    func timeZone(for field: EventField, default: TimeZone) -> TimeZone {
        if let tzIdentifier = field.parameters["TZID"],
           let timezone = TimeZone(identifier: tzIdentifier) {
            return timezone
        }
        return `default`
    }

    var isoZuluFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }

    func dateTimeFormatter(for timezone: TimeZone) -> DateFormatter? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }

    var isoGeneralFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    func parseFloatingDate(_ rawValue: String, timezone: TimeZone) -> Date? {
        guard rawValue.count == 8,
              let year = Int(rawValue.prefix(4)),
              let month = Int(rawValue.dropFirst(4).prefix(2)),
              let day = Int(rawValue.suffix(2)) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        return calendar.date(from: components)
    }
}

private extension String {
    func emptyToNil() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func bracketedContext() -> String? {
        guard let start = lastIndex(of: "["), let end = lastIndex(of: "]"), start < end else {
            return nil
        }
        let content = self[index(after: start)..<end]
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func removingBracketedSuffix() -> String {
        guard let start = lastIndex(of: "["), let end = lastIndex(of: "]"), start < end else {
            return self
        }
        let prefix = self[..<start]
        return String(prefix)
    }
}
