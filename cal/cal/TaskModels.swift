import Foundation
import SwiftUI
import CoreLocation

struct TaskItem: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var dueDate: Date
    var startDate: Date?
    var priority: TaskPriority
    var isCompleted: Bool
    var estimatedDurationMinutes: Int?
    var location: TaskLocation?
    var travelEstimates: TravelEstimates?
    var actualStartTime: Date?
    var actualEndTime: Date?
    var actualDurationSeconds: Double?
    var activeTimerStart: Date?
    var hasDeadline: Bool

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        startDate: Date? = nil,
        priority: TaskPriority,
        isCompleted: Bool = false,
        estimatedDurationMinutes: Int? = nil,
        location: TaskLocation? = nil,
        travelEstimates: TravelEstimates? = nil,
        actualStartTime: Date? = nil,
        actualEndTime: Date? = nil,
        actualDurationSeconds: Double? = nil,
        activeTimerStart: Date? = nil,
        hasDeadline: Bool = true
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.startDate = startDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.location = location
        self.travelEstimates = travelEstimates
        self.actualStartTime = actualStartTime
        self.actualEndTime = actualEndTime
        self.actualDurationSeconds = actualDurationSeconds
        self.activeTimerStart = activeTimerStart
        self.hasDeadline = hasDeadline
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueDate
        case startDate
        case priority
        case isCompleted
        case estimatedDurationMinutes
        case location
        case travelEstimates
        case actualStartTime
        case actualEndTime
        case actualDurationSeconds
        case activeTimerStart
        case hasDeadline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        estimatedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedDurationMinutes)
        location = try container.decodeIfPresent(TaskLocation.self, forKey: .location)
        travelEstimates = try container.decodeIfPresent(TravelEstimates.self, forKey: .travelEstimates)
        actualStartTime = try container.decodeIfPresent(Date.self, forKey: .actualStartTime)
        actualEndTime = try container.decodeIfPresent(Date.self, forKey: .actualEndTime)
        actualDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .actualDurationSeconds)
        activeTimerStart = try container.decodeIfPresent(Date.self, forKey: .activeTimerStart)
        hasDeadline = try container.decodeIfPresent(Bool.self, forKey: .hasDeadline) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(estimatedDurationMinutes, forKey: .estimatedDurationMinutes)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(travelEstimates, forKey: .travelEstimates)
        try container.encodeIfPresent(actualStartTime, forKey: .actualStartTime)
        try container.encodeIfPresent(actualEndTime, forKey: .actualEndTime)
        try container.encodeIfPresent(actualDurationSeconds, forKey: .actualDurationSeconds)
        try container.encodeIfPresent(activeTimerStart, forKey: .activeTimerStart)
        try container.encode(hasDeadline, forKey: .hasDeadline)
    }
}

enum TaskSegmentParent: String, Codable {
    case todo
    case assignment
}

struct TaskSegment: Identifiable, Equatable, Codable {
    let id: UUID
    var parentType: TaskSegmentParent
    var parentIdentifier: String
    var title: String
    var dueDate: Date
    var startDate: Date?
    var hasDeadline: Bool
    var priority: TaskPriority
    var isCompleted: Bool
    var estimatedDurationMinutes: Int?
    var actualStartTime: Date?
    var actualEndTime: Date?
    var actualDurationSeconds: Double?
    var activeTimerStart: Date?

    init(
        id: UUID = UUID(),
        parentType: TaskSegmentParent,
        parentIdentifier: String,
        title: String,
        dueDate: Date,
        startDate: Date? = nil,
        hasDeadline: Bool = true,
        priority: TaskPriority = .medium,
        isCompleted: Bool = false,
        estimatedDurationMinutes: Int? = nil,
        actualStartTime: Date? = nil,
        actualEndTime: Date? = nil,
        actualDurationSeconds: Double? = nil,
        activeTimerStart: Date? = nil
    ) {
        self.id = id
        self.parentType = parentType
        self.parentIdentifier = parentIdentifier
        self.title = title
        self.dueDate = dueDate
        self.startDate = startDate
        self.hasDeadline = hasDeadline
        self.priority = priority
        self.isCompleted = isCompleted
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.actualStartTime = actualStartTime
        self.actualEndTime = actualEndTime
        self.actualDurationSeconds = actualDurationSeconds
        self.activeTimerStart = activeTimerStart
    }
}

struct TaskLocation: Codable, Equatable {
    var name: String
    var subtitle: String?
    var latitude: Double
    var longitude: Double
    var mapItemIdentifier: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, subtitle: String? = nil, latitude: Double, longitude: Double, mapItemIdentifier: String? = nil) {
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemIdentifier = mapItemIdentifier
    }
}

struct TravelEstimates: Codable, Equatable {
    var drivingMinutes: Int?
    var walkingMinutes: Int?
    var lastUpdated: Date?

    var hasData: Bool {
        drivingMinutes != nil || walkingMinutes != nil
    }
}

enum TaskPriority: String, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }

    var systemImageName: String {
        switch self {
        case .low:
            return "arrow.down.circle"
        case .medium:
            return "minus.circle"
        case .high:
            return "arrow.up.circle"
        }
    }

    var tintColor: Color {
        switch self {
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }
}
