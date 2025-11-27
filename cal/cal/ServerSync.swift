import Foundation

struct ServerSyncPayload {
    var tasks: [TaskItem]
    var taskSegments: [TaskSegment]
    var assignments: [SchoolAssignment]
    var assignmentSegments: [TaskSegment]
    var routines: [RoutineItem]
}

actor ServerSyncClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:4000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchAll() async -> ServerSyncPayload? {
        async let tasksDTO = fetch([TaskDTO].self, path: "/api/tasks")
        async let taskSegmentsDTO = fetch([TaskSegmentDTO].self, path: "/api/task-segments")
        async let assignmentsDTO = fetch([AssignmentDTO].self, path: "/api/assignments")
        async let assignmentSegmentsDTO = fetch([AssignmentSegmentDTO].self, path: "/api/assignment-segments")
        async let routinesDTO = fetch([RoutineDTO].self, path: "/api/routines")

        guard
            let tasks = try? await tasksDTO,
            let taskSegments = try? await taskSegmentsDTO,
            let assignments = try? await assignmentsDTO,
            let assignmentSegments = try? await assignmentSegmentsDTO,
            let routines = try? await routinesDTO
        else {
            return nil
        }

        return ServerSyncPayload(
            tasks: tasks.map { $0.toTaskItem() },
            taskSegments: taskSegments.compactMap { $0.toTaskSegment() },
            assignments: assignments.compactMap { $0.toSchoolAssignment() },
            assignmentSegments: assignmentSegments.compactMap { $0.toTaskSegment() },
            routines: routines.map { $0.toRoutineItem() }
        )
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResponseEnvelope<T>.self, from: data).unwrap()
    }

    // MARK: - Outbound sync helpers
    func upsertTask(_ task: TaskItem) async {
        let payload = TaskWritePayload(task: task)
        await send(payload, to: "/api/tasks", method: "POST")
    }

    func updateTask(_ task: TaskItem) async {
        let payload = TaskWritePayload(task: task)
        await send(payload, to: "/api/tasks", method: "PUT")
    }

    func deleteTask(id: UUID) async {
        await send(nil as EmptyPayload?, to: "/api/tasks?id=\(id.uuidString)", method: "DELETE")
    }

    func taskTimer(id: UUID, action: String) async {
        await send(TimerPayload(id: id.uuidString, action: action), to: "/api/tasks/timer", method: "POST")
    }

    func upsertTaskSegment(_ segment: TaskSegment) async {
        switch segment.parentType {
        case .todo:
            await send(TaskSegmentWritePayload(segment: segment), to: "/api/task-segments", method: "POST")
        case .assignment:
            await send(AssignmentSegmentWritePayload(segment: segment), to: "/api/assignment-segments", method: "POST")
        }
    }

    func updateTaskSegment(_ segment: TaskSegment) async {
        switch segment.parentType {
        case .todo:
            await send(TaskSegmentWritePayload(segment: segment), to: "/api/task-segments", method: "PUT")
        case .assignment:
            await send(AssignmentSegmentWritePayload(segment: segment), to: "/api/assignment-segments", method: "PUT")
        }
    }

    func deleteTaskSegment(_ segment: TaskSegment) async {
        switch segment.parentType {
        case .todo:
            await send(nil as EmptyPayload?, to: "/api/task-segments?id=\(segment.id.uuidString)", method: "DELETE")
        case .assignment:
            await send(nil as EmptyPayload?, to: "/api/assignment-segments?id=\(segment.id.uuidString)", method: "DELETE")
        }
    }

    func segmentTimer(_ segment: TaskSegment, action: String) async {
        switch segment.parentType {
        case .todo:
            await send(TimerPayload(id: segment.id.uuidString, action: action), to: "/api/task-segment-timer", method: "POST")
        case .assignment:
            await send(TimerPayload(id: segment.id.uuidString, action: action), to: "/api/assignment-segment-timer", method: "POST")
        }
    }

    func upsertAssignment(_ assignment: SchoolAssignment) async {
        let payload = AssignmentWritePayload(assignment: assignment)
        await send(payload, to: "/api/assignments", method: "POST")
    }

    func updateAssignment(_ assignment: SchoolAssignment) async {
        let payload = AssignmentWritePayload(assignment: assignment)
        await send(payload, to: "/api/assignments", method: "PUT")
    }

    func deleteAssignment(id: String) async {
        await send(nil as EmptyPayload?, to: "/api/assignments?id=\(id)", method: "DELETE")
    }

    func assignmentTimer(id: String, action: String) async {
        await send(TimerPayload(id: id, action: action), to: "/api/assignment-timer", method: "POST")
    }

    func upsertRoutine(_ routine: RoutineItem) async {
        let payload = RoutineWritePayload(routine: routine)
        await send(payload, to: "/api/routines", method: "POST")
    }

    func updateRoutine(_ routine: RoutineItem) async {
        let payload = RoutineWritePayload(routine: routine)
        await send(payload, to: "/api/routines", method: "PUT")
    }

    func deleteRoutine(id: UUID) async {
        await send(nil as EmptyPayload?, to: "/api/routines?id=\(id.uuidString)", method: "DELETE")
    }

    // MARK: - HTTP send
    private func send<E: Encodable>(_ payload: E?, to path: String, method: String) async {
        guard let url = URL(string: path, relativeTo: baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let payload = payload {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try? encoder.encode(payload)
        }
        _ = try? await session.data(for: request)
    }
}

private func priorityValue(_ priority: TaskPriority) -> Int {
    switch priority {
    case .high: return 5
    case .medium: return 3
    case .low: return 1
    @unknown default:
        return 3
    }
}

private struct ResponseEnvelope<T: Decodable>: Decodable {
    let tasks: T?
    let routines: T?
    let assignments: T?
    let assignmentSegments: T?
    let segments: T?

    func unwrap() -> T {
        return tasks ?? routines ?? assignments ?? assignmentSegments ?? segments ?? (tasks as? T)!
    }
}

// MARK: - DTOs & Mapping

private struct TaskDTO: Decodable {
    let id: String
    let title: String
    let description: String?
    let estimatedDuration: Int?
    let priority: Int?
    let due: Date?
    let start: Date?
    let hasDeadline: Bool?
    let isCompleted: Bool?
    let history: [TimerEntryDTO]?
    let updatedAt: Date?

    func toTaskItem() -> TaskItem {
        let (actualStart, actualEnd, durationSeconds, activeStart) = history?.toTiming() ?? (nil, nil, nil, nil)
        return TaskItem(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            dueDate: due ?? Date(),
            startDate: start,
            priority: TaskPriority(rawValue: priorityString(priority)) ?? .medium,
            isCompleted: isCompleted ?? false,
            estimatedDurationMinutes: estimatedDuration,
            location: nil,
            travelEstimates: nil,
            actualStartTime: actualStart,
            actualEndTime: actualEnd,
            actualDurationSeconds: durationSeconds,
            activeTimerStart: activeStart,
            hasDeadline: hasDeadline ?? true
        )
    }

    private func priorityString(_ value: Int?) -> String {
        switch value {
        case let v? where v >= 5: return "high"
        case let v? where v <= 1: return "low"
        default: return "medium"
        }
    }
}

private struct TaskWritePayload: Encodable {
    let id: String
    let title: String
    let description: String?
    let estimatedDuration: Int?
    let priority: Int?
    let due: Date?
    let start: Date?
    let hasDeadline: Bool
    let isCompleted: Bool

    init(task: TaskItem) {
        id = task.id.uuidString
        title = task.title
        description = nil
        estimatedDuration = task.estimatedDurationMinutes
        priority = priorityValue(task.priority)
        due = task.hasDeadline ? task.dueDate : nil
        start = task.startDate
        hasDeadline = task.hasDeadline
        isCompleted = task.isCompleted
    }
}

private struct TaskSegmentDTO: Decodable {
    let id: String
    let taskId: String
    let title: String
    let start: Date?
    let due: Date?
    let hasDeadline: Bool?
    let estimatedDuration: Int?
    let isCompleted: Bool?
    let history: [TimerEntryDTO]?

    func toTaskSegment() -> TaskSegment? {
        let (actualStart, actualEnd, durationSeconds, activeStart) = history?.toTiming() ?? (nil, nil, nil, nil)
        guard let uuid = UUID(uuidString: taskId) else { return nil }
        return TaskSegment(
            id: UUID(uuidString: id) ?? UUID(),
            parentType: .todo,
            parentIdentifier: uuid.uuidString,
            title: title,
            dueDate: due ?? Date(),
            startDate: start,
            hasDeadline: hasDeadline ?? true,
            priority: .medium,
            isCompleted: isCompleted ?? false,
            estimatedDurationMinutes: estimatedDuration,
            actualStartTime: actualStart,
            actualEndTime: actualEnd,
            actualDurationSeconds: durationSeconds,
            activeTimerStart: activeStart
        )
    }
}

private struct TaskSegmentWritePayload: Encodable {
    let id: String
    let taskId: String
    let title: String
    let start: Date?
    let due: Date?
    let hasDeadline: Bool
    let estimatedDuration: Int?
    let isCompleted: Bool

    init(segment: TaskSegment) {
        id = segment.id.uuidString
        taskId = segment.parentIdentifier
        title = segment.title
        start = segment.startDate
        due = segment.dueDate
        hasDeadline = segment.hasDeadline
        estimatedDuration = segment.estimatedDurationMinutes
        isCompleted = segment.isCompleted
    }
}

private struct AssignmentDTO: Decodable {
    let id: String
    let title: String
    let description: String?
    let course: String?
    let location: String?
    let url: String?
    let start: Date?
    let due: Date?
    let end: Date?
    let allDay: Bool?
    let hasDeadline: Bool?
    let estimatedDuration: Int?
    let isCompleted: Bool?
    let history: [TimerEntryDTO]?

    func toSchoolAssignment() -> SchoolAssignment? {
        let (actualStart, actualEnd, durationSeconds, activeStart) = history?.toTiming() ?? (nil, nil, nil, nil)
        return SchoolAssignment(
            id: id,
            title: title,
            dueDate: due ?? Date(),
            endDate: end,
            isAllDay: allDay ?? false,
            description: description,
            course: course,
            location: location,
            url: URL(string: url ?? ""),
            isCompleted: isCompleted ?? false,
            estimatedDurationMinutes: estimatedDuration,
            actualStartTime: actualStart,
            actualEndTime: actualEnd,
            actualDurationSeconds: durationSeconds,
            activeTimerStart: activeStart
        )
    }
}

private struct AssignmentWritePayload: Encodable {
    let id: String
    let title: String
    let description: String?
    let course: String?
    let location: String?
    let url: String?
    let start: Date?
    let due: Date?
    let end: Date?
    let allDay: Bool
    let hasDeadline: Bool
    let estimatedDuration: Int?
    let isCompleted: Bool

    init(assignment: SchoolAssignment) {
        id = assignment.id
        title = assignment.title
        description = assignment.description
        course = assignment.course
        location = assignment.location
        url = assignment.url?.absoluteString
        start = assignment.dueDate
        due = assignment.dueDate
        end = assignment.endDate
        allDay = assignment.isAllDay
        hasDeadline = true
        estimatedDuration = assignment.estimatedDurationMinutes
        isCompleted = assignment.isCompleted
    }
}

private struct AssignmentSegmentDTO: Decodable {
    let id: String
    let assignmentId: String
    let title: String
    let start: Date?
    let due: Date?
    let estimatedDuration: Int?
    let isCompleted: Bool?
    let history: [TimerEntryDTO]?

    func toTaskSegment() -> TaskSegment? {
        let (actualStart, actualEnd, durationSeconds, activeStart) = history?.toTiming() ?? (nil, nil, nil, nil)
        return TaskSegment(
            id: UUID(uuidString: id) ?? UUID(),
            parentType: .assignment,
            parentIdentifier: assignmentId,
            title: title,
            dueDate: due ?? Date(),
            startDate: start,
            hasDeadline: true,
            priority: .medium,
            isCompleted: isCompleted ?? false,
            estimatedDurationMinutes: estimatedDuration,
            actualStartTime: actualStart,
            actualEndTime: actualEnd,
            actualDurationSeconds: durationSeconds,
            activeTimerStart: activeStart
        )
    }
}

private struct AssignmentSegmentWritePayload: Encodable {
    let id: String
    let assignmentId: String
    let title: String
    let start: Date?
    let due: Date?
    let estimatedDuration: Int?
    let isCompleted: Bool

    init(segment: TaskSegment) {
        id = segment.id.uuidString
        assignmentId = segment.parentIdentifier
        title = segment.title
        start = segment.startDate
        due = segment.dueDate
        estimatedDuration = segment.estimatedDurationMinutes
        isCompleted = segment.isCompleted
    }
}

private struct RoutineDTO: Decodable {
    let id: String
    let name: String
    let blocks: [RoutineBlockDTO]
    let active: Bool?
    let color: String?
    let icon: String?

    func toRoutineItem() -> RoutineItem {
        let startDate = blocks.first?.start ?? Date()
        let endDate = blocks.first?.end ?? startDate.addingTimeInterval(3600)
        let startComponents = Calendar.current.dateComponents([.hour, .minute], from: startDate)
        let endComponents = Calendar.current.dateComponents([.hour, .minute], from: endDate)
        return RoutineItem(
            id: UUID(uuidString: id) ?? UUID(),
            title: name,
            startTime: startComponents,
            endTime: endComponents,
            isEnabled: active ?? true,
            weekdays: Set(blocks.map { Calendar.current.component(.weekday, from: $0.start) }),
            iconName: icon ?? "repeat",
            colorHex: color ?? RoutineItem.defaultColorHex
        )
    }
}

private struct RoutineBlockDTO: Decodable {
    let start: Date
    let end: Date
    let context: String?

    var startTime: Date { start }
    var endTime: Date { end }
}

private struct RoutineWritePayload: Encodable {
    struct BlockPayload: Encodable {
        let start: Date
        let end: Date
        let context: String
    }

    let id: String
    let name: String
    let blocks: [BlockPayload]
    let active: Bool
    let color: String
    let icon: String

    init(routine: RoutineItem) {
        id = routine.id.uuidString
        name = routine.title
        active = routine.isEnabled
        color = routine.colorHex
        icon = routine.iconName

        var tempBlocks: [BlockPayload] = []
        let calendar = Calendar.current
        for weekday in routine.weekdays {
            if let startDate = calendar.nextDate(after: Date(), matching: routine.startTime, matchingPolicy: .strict, direction: .forward),
               let endDate = calendar.nextDate(after: Date(), matching: routine.endTime, matchingPolicy: .strict, direction: .forward) {
                var startComp = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: startDate)
                var endComp = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: endDate)
                startComp.weekday = weekday
                endComp.weekday = weekday
                if let s = calendar.date(from: startComp), let e = calendar.date(from: endComp) {
                    tempBlocks.append(BlockPayload(start: s, end: e, context: name))
                }
            }
        }
        blocks = tempBlocks
    }
}

private struct TimerEntryDTO: Decodable {
    let startedAt: Date?
    let stoppedAt: Date?
}

private struct TimerPayload: Encodable {
    let id: String
    let action: String
}

private struct EmptyPayload: Encodable {}

private extension Array where Element == TimerEntryDTO {
    func toTiming() -> (Date?, Date?, Double?, Date?) {
        var total: TimeInterval = 0
        var activeStart: Date? = nil
        var firstStart: Date? = nil
        var lastStop: Date? = nil
        for entry in self {
            if let s = entry.startedAt {
                if firstStart == nil { firstStart = s }
                if let stop = entry.stoppedAt {
                    total += Swift.max(0, stop.timeIntervalSince(s))
                    lastStop = stop
                } else {
                    activeStart = s
                }
            }
        }
        return (firstStart, lastStop, total > 0 ? total : nil, activeStart)
    }
}
