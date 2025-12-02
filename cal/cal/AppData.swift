import Foundation
import Combine
import SwiftUI

@MainActor
final class AppData: ObservableObject {
    @Published var todos: [TaskItem] = []
    @Published var assignments: [SchoolAssignment] = []
    @Published var routines: [RoutineItem] = []
    @Published var taskSegments: [TaskSegment] = []
    @Published var assignmentsLastUpdated: Date?
    @Published private(set) var lastAssignmentSync: AssignmentSyncSource?
    private let defaults = UserDefaults.standard
    private let reminderKey = "assignmentReminderMinutes"

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let todosURL: URL
    private let assignmentsURL: URL
    private let assignmentsICSURL: URL
    private let routinesURL: URL
    private let taskSegmentsURL: URL
    private let serverClient = ServerSyncClient()

    init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        let appDirectory = baseDirectory.appendingPathComponent("SimpleCalendar", isDirectory: true)
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        todosURL = appDirectory.appendingPathComponent("todos.json")
        assignmentsURL = appDirectory.appendingPathComponent("assignments.json")
        assignmentsICSURL = appDirectory.appendingPathComponent("assignments.ics")
        routinesURL = appDirectory.appendingPathComponent("routines.json")
        taskSegmentsURL = appDirectory.appendingPathComponent("taskSegments.json")

        loadTodos()
        loadAssignments()
        loadRoutines()
        loadTaskSegments()

        Task {
            await syncFromServer()
        }

        NotificationManager.shared.requestAuthorizationIfNeeded()
    }

    // MARK: - Routines
    func add(routine: RoutineItem) {
        routines.append(routine)
        persistRoutines()
        Task { await serverClient.upsertRoutine(routine) }
        scheduleAllReminders()
    }

    func removeRoutines(at offsets: IndexSet) {
        routines.remove(atOffsets: offsets)
        persistRoutines()
        Task {
            for index in offsets {
                if routines.indices.contains(index) {
                    await serverClient.deleteRoutine(id: routines[index].id)
                }
            }
        }
    }

    func removeRoutine(id: UUID) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines.remove(at: index)
        persistRoutines()
        Task { await serverClient.deleteRoutine(id: id) }
        scheduleAllReminders()
    }

    func toggleRoutineEnabled(id: UUID) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].isEnabled.toggle()
        persistRoutines()
        Task { await serverClient.updateRoutine(routines[index]) }
        scheduleAllReminders()
    }

    func update(routine: RoutineItem) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
        persistRoutines()
        Task { await serverClient.updateRoutine(routine) }
        scheduleAllReminders()
    }

    // MARK: - Task Segments
    func segments(for parentType: TaskSegmentParent, parentIdentifier: String) -> [TaskSegment] {
        taskSegments
            .filter { $0.parentType == parentType && $0.parentIdentifier == parentIdentifier }
            .sorted { lhs, rhs in
                if lhs.dueDate == rhs.dueDate {
                    return lhs.title < rhs.title
                }
                return lhs.dueDate < rhs.dueDate
            }
    }

    func add(segment: TaskSegment) {
        taskSegments.append(segment)
        persistTaskSegments()
        Task { await serverClient.upsertTaskSegment(segment) }
    }

    func update(segment: TaskSegment) {
        guard let index = taskSegments.firstIndex(where: { $0.id == segment.id }) else { return }
        taskSegments[index] = segment
        persistTaskSegments()
        Task { await serverClient.updateTaskSegment(segment) }
    }

    func removeSegment(id: UUID) {
        guard let segment = taskSegments.first(where: { $0.id == id }) else { return }
        taskSegments.removeAll { $0.id == id }
        persistTaskSegments()
        Task { await serverClient.deleteTaskSegment(segment) }
    }

    func removeSegments(for parentType: TaskSegmentParent, parentIdentifier: String) {
        let removed = taskSegments.filter { $0.parentType == parentType && $0.parentIdentifier == parentIdentifier }
        taskSegments.removeAll { $0.parentType == parentType && $0.parentIdentifier == parentIdentifier }
        persistTaskSegments()
        Task {
            for segment in removed {
                await serverClient.deleteTaskSegment(segment)
            }
        }
    }

    func toggleSegmentCompletion(id: UUID) {
        guard let index = taskSegments.firstIndex(where: { $0.id == id }) else { return }
        taskSegments[index].isCompleted.toggle()
        if taskSegments[index].isCompleted {
            taskSegments[index].activeTimerStart = nil
            if taskSegments[index].actualStartTime == nil {
                taskSegments[index].actualStartTime = Date()
            }
            taskSegments[index].actualEndTime = Date()
        }
        persistTaskSegments()
        Task { await serverClient.segmentTimer(taskSegments[index], action: "complete") }
    }

    func startSegmentProgress(id: UUID) {
        guard let index = taskSegments.firstIndex(where: { $0.id == id }) else { return }
        var segment = taskSegments[index]
        let now = Date()
        if segment.actualStartTime == nil {
            segment.actualStartTime = now
        }
        if segment.actualDurationSeconds == nil {
            segment.actualDurationSeconds = 0
        }
        segment.actualEndTime = nil
        segment.activeTimerStart = now
        segment.isCompleted = false
        taskSegments[index] = segment
        persistTaskSegments()
        Task { await serverClient.segmentTimer(segment, action: "start") }
    }

    func pauseSegmentProgress(id: UUID) {
        guard let index = taskSegments.firstIndex(where: { $0.id == id }) else { return }
        var segment = taskSegments[index]
        guard let segmentStart = segment.activeTimerStart else { return }
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(segmentStart))
        let accumulated = segment.actualDurationSeconds ?? 0
        segment.actualDurationSeconds = accumulated + elapsed
        segment.activeTimerStart = nil
        segment.actualEndTime = nil
        taskSegments[index] = segment
        persistTaskSegments()
        Task { await serverClient.segmentTimer(segment, action: "pause") }
    }

    func completeSegmentProgress(id: UUID) {
        guard let index = taskSegments.firstIndex(where: { $0.id == id }) else { return }
        var segment = taskSegments[index]
        let now = Date()
        if segment.actualStartTime == nil {
            segment.actualStartTime = now
        }
        var total = segment.actualDurationSeconds ?? 0
        if let start = segment.activeTimerStart {
            total += max(0, now.timeIntervalSince(start))
        }
        segment.activeTimerStart = nil
        segment.actualEndTime = now
        segment.actualDurationSeconds = total
        segment.isCompleted = true
        taskSegments[index] = segment
        persistTaskSegments()
        Task { await serverClient.segmentTimer(segment, action: "complete") }
    }

    func add(task: TaskItem) {
        todos.append(task)
        sortTasks()
        persistTodos()
        Task { await serverClient.upsertTask(task) }
        scheduleAllReminders()
    }

    func update(task: TaskItem) {
        guard let index = todos.firstIndex(where: { $0.id == task.id }) else { return }
        todos[index] = task
        sortTasks()
        persistTodos()
        Task { await serverClient.updateTask(task) }
        scheduleAllReminders()
    }

    func removeTasks(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { index in
            todos.indices.contains(index) ? todos[index].id : nil
        }
        todos.remove(atOffsets: offsets)
        sortTasks()
        persistTodos()
        for id in removedIDs {
            removeSegments(for: .todo, parentIdentifier: id.uuidString)
            Task { await serverClient.deleteTask(id: id) }
        }
        scheduleAllReminders()
    }

    func toggleTaskCompletion(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        sortTasks()
        persistTodos()
        Task { await serverClient.updateTask(todos[index]) }
        scheduleAllReminders()
    }

    func startTaskProgress(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        var task = todos[index]
        let now = Date()
        if task.actualStartTime == nil {
            task.actualStartTime = now
        }
        if task.actualDurationSeconds == nil {
            task.actualDurationSeconds = 0
        }
        task.actualEndTime = nil
        task.activeTimerStart = now
        task.isCompleted = false
        todos[index] = task
        persistTodos()
        Task { await serverClient.taskTimer(id: task.id, action: "start") }
        scheduleAllReminders()
    }

    func pauseTaskProgress(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        var task = todos[index]
        guard let segmentStart = task.activeTimerStart else { return }
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(segmentStart))
        let accumulated = task.actualDurationSeconds ?? 0
        task.actualDurationSeconds = accumulated + elapsed
        task.activeTimerStart = nil
        task.actualEndTime = nil
        todos[index] = task
        persistTodos()
        Task { await serverClient.taskTimer(id: task.id, action: "pause") }
        scheduleAllReminders()
    }

    func completeTaskProgress(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        var task = todos[index]
        let now = Date()
        if task.actualStartTime == nil {
            task.actualStartTime = now
        }
        var total = task.actualDurationSeconds ?? 0
        if let segmentStart = task.activeTimerStart {
            total += max(0, now.timeIntervalSince(segmentStart))
        }
        task.actualDurationSeconds = total
        task.activeTimerStart = nil
        task.actualEndTime = now
        task.isCompleted = true
        todos[index] = task
        sortTasks()
        persistTodos()
        Task { await serverClient.taskTimer(id: task.id, action: "complete") }
        scheduleAllReminders()
    }

    func setTaskDuration(id: UUID, minutes: Int?) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].estimatedDurationMinutes = minutes
        persistTodos()
        scheduleAllReminders()
    }

    func toggleAssignmentCompletion(id: String) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        assignments[index].isCompleted.toggle()
        sortAssignments()
        persistAssignments()
        Task { await serverClient.updateAssignment(assignments[index]) }
        scheduleAllReminders()
    }

    func startAssignmentProgress(id: String) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        var assignment = assignments[index]
        let now = Date()
        if assignment.actualStartTime == nil {
            assignment.actualStartTime = now
        }
        if assignment.actualDurationSeconds == nil {
            assignment.actualDurationSeconds = 0
        }
        assignment.actualEndTime = nil
        assignment.activeTimerStart = now
        assignment.isCompleted = false
        assignments[index] = assignment
        persistAssignments()
        Task { await serverClient.assignmentTimer(id: assignment.id, action: "start") }
        scheduleAllReminders()
    }

    func pauseAssignmentProgress(id: String) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        var assignment = assignments[index]
        guard let segmentStart = assignment.activeTimerStart else { return }
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(segmentStart))
        let accumulated = assignment.actualDurationSeconds ?? 0
        assignment.actualDurationSeconds = accumulated + elapsed
        assignment.activeTimerStart = nil
        assignment.actualEndTime = nil
        assignments[index] = assignment
        persistAssignments()
        Task { await serverClient.assignmentTimer(id: assignment.id, action: "pause") }
        scheduleAllReminders()
    }

    func completeAssignmentProgress(id: String) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        var assignment = assignments[index]
        let now = Date()
        if assignment.actualStartTime == nil {
            assignment.actualStartTime = now
        }
        var total = assignment.actualDurationSeconds ?? 0
        if let segmentStart = assignment.activeTimerStart {
            total += max(0, now.timeIntervalSince(segmentStart))
        }
        assignment.activeTimerStart = nil
        assignment.actualEndTime = now
        assignment.actualDurationSeconds = total
        assignment.isCompleted = true
        assignments[index] = assignment
        sortAssignments()
        persistAssignments()
        Task { await serverClient.assignmentTimer(id: assignment.id, action: "complete") }
        scheduleAllReminders()
    }

    func setAssignmentDuration(id: String, minutes: Int?) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        assignments[index].estimatedDurationMinutes = minutes
        persistAssignments()
        Task { await serverClient.updateAssignment(assignments[index]) }
        scheduleAllReminders()
    }

    func replaceAssignments(with newAssignments: [SchoolAssignment], syncSource: AssignmentSyncSource?, rawICSData: Data?) {
        if let rawICSData {
            storeAssignmentsICSData(rawICSData)
        }

        let now = Date()
        let calendar = Calendar.current
        var merged: [SchoolAssignment] = []

        for var assignment in newAssignments {
            if let existing = assignments.first(where: { $0.id == assignment.id }) {
                assignment.isCompleted = existing.isCompleted
                assignment.estimatedDurationMinutes = existing.estimatedDurationMinutes
            } else if assignment.displayEndDate(using: calendar) ?? assignment.dueDate < now {
                assignment.isCompleted = true
            }
            merged.append(assignment)
        }

        assignments = merged
        sortAssignments()
        assignmentsLastUpdated = Date()
        if let syncSource {
            lastAssignmentSync = syncSource
        }
        persistAssignments()
        Task {
            for assignment in assignments {
                await serverClient.upsertAssignment(assignment)
            }
        }
        scheduleAllReminders()

        let validAssignmentIDs = Set(assignments.map(\.id))
        let originalSegmentCount = taskSegments.count
        taskSegments.removeAll { segment in
            segment.parentType == .assignment && !validAssignmentIDs.contains(segment.parentIdentifier)
        }
        if taskSegments.count != originalSegmentCount {
            persistTaskSegments()
        }
        scheduleAllReminders()
    }

    func loadStoredAssignmentsICSData() -> Data? {
        try? Data(contentsOf: assignmentsICSURL)
    }

    private func storeAssignmentsICSData(_ data: Data) {
        try? data.write(to: assignmentsICSURL, options: [.atomic])
    }

    private func sortTasks() {
        todos.sort {
            if $0.isCompleted == $1.isCompleted {
                switch ($0.hasDeadline, $1.hasDeadline) {
                case (true, true):
                    return $0.dueDate < $1.dueDate
                case (true, false):
                    return true
                case (false, true):
                    return false
                case (false, false):
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }
            return !$0.isCompleted && $1.isCompleted
        }
    }

    private func sortAssignments() {
        assignments.sort {
            if $0.isCompleted == $1.isCompleted {
                return $0.dueDate < $1.dueDate
            }
            return !$0.isCompleted && $1.isCompleted
        }
    }

    private func loadTodos() {
        guard let data = try? Data(contentsOf: todosURL) else { return }
        if let decoded = try? decoder.decode([TaskItem].self, from: data) {
            todos = decoded
            sortTasks()
            scheduleAllReminders()
        }
    }

    private func loadAssignments() {
        guard let data = try? Data(contentsOf: assignmentsURL) else { return }
        if let decoded = try? decoder.decode(AssignmentsSnapshot.self, from: data) {
            assignments = decoded.assignments
            assignmentsLastUpdated = decoded.lastUpdated
            lastAssignmentSync = decoded.syncSource
            sortAssignments()
            scheduleAllReminders()
        }
    }

    private func loadRoutines() {
        guard let data = try? Data(contentsOf: routinesURL) else { return }
        if let decoded = try? decoder.decode([RoutineItem].self, from: data) {
            routines = decoded
            scheduleAllReminders()
        }
    }

    private func loadTaskSegments() {
        guard let data = try? Data(contentsOf: taskSegmentsURL) else { return }
        if let decoded = try? decoder.decode([TaskSegment].self, from: data) {
            taskSegments = decoded
        }
    }

    private func persistTodos() {
        guard let data = try? encoder.encode(todos) else { return }
        try? data.write(to: todosURL, options: [.atomic])
    }

    private func persistAssignments() {
        let snapshot = AssignmentsSnapshot(assignments: assignments, lastUpdated: assignmentsLastUpdated, syncSource: lastAssignmentSync)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: assignmentsURL, options: [.atomic])
    }

    private func persistRoutines() {
        // Use a local encoder to avoid potential shared-state concurrency issues
        let localEncoder = JSONEncoder()
        localEncoder.outputFormatting = encoder.outputFormatting
        localEncoder.dateEncodingStrategy = encoder.dateEncodingStrategy

        do {
            let data = try localEncoder.encode(routines)
            try data.write(to: routinesURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to persist routines: \(error)")
            #endif
        }
    }

    private func persistTaskSegments() {
        let localEncoder = JSONEncoder()
        localEncoder.outputFormatting = encoder.outputFormatting
        localEncoder.dateEncodingStrategy = encoder.dateEncodingStrategy

        do {
            let data = try localEncoder.encode(taskSegments)
            try data.write(to: taskSegmentsURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to persist task segments: \(error)")
            #endif
        }
    }

    // MARK: - Server Sync
    func syncFromServer() async {
        guard let payload = await serverClient.fetchAll() else { return }
        await MainActor.run {
            self.todos = payload.tasks
            self.taskSegments = payload.taskSegments
            self.assignments = payload.assignments
            self.routines = payload.routines
            self.persistTodos()
            self.persistTaskSegments()
            self.persistAssignments()
            self.persistRoutines()
            self.scheduleAllReminders()
        }
    }

    func refreshAssignmentReminders() {
        scheduleAllReminders()
    }

    private func scheduleAllReminders() {
        let lead = defaults.integer(forKey: reminderKey)
        let effectiveLead = lead > 0 ? lead : 60
        NotificationManager.shared.scheduleTaskReminders(tasks: todos, leadMinutes: effectiveLead)
        NotificationManager.shared.scheduleAssignmentReminders(assignments: assignments, leadMinutes: effectiveLead)
        NotificationManager.shared.scheduleRoutineReminders(routines: routines)
    }
}

private struct AssignmentsSnapshot: Codable {
    var assignments: [SchoolAssignment]
    var lastUpdated: Date?
    var syncSource: AssignmentSyncSource?
}

struct AssignmentSyncSource: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case file
        case url
    }

    var kind: Kind
    var remoteURLString: String?
    var displayName: String?
}
