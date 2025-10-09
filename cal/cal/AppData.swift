import Foundation
import Combine
import SwiftUI

@MainActor
final class AppData: ObservableObject {
    @Published var todos: [TaskItem] = []
    @Published var assignments: [SchoolAssignment] = []
    @Published var routines: [RoutineItem] = []
    @Published var assignmentsLastUpdated: Date?
    @Published private(set) var lastAssignmentSync: AssignmentSyncSource?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let todosURL: URL
    private let assignmentsURL: URL
    private let assignmentsICSURL: URL
    private let routinesURL: URL

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

        loadTodos()
        loadAssignments()
        loadRoutines()
    }

    // MARK: - Routines
    func add(routine: RoutineItem) {
        routines.append(routine)
        persistRoutines()
    }

    func removeRoutines(at offsets: IndexSet) {
        routines.remove(atOffsets: offsets)
        persistRoutines()
    }

    func toggleRoutineEnabled(id: UUID) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].isEnabled.toggle()
        persistRoutines()
    }

    func update(routine: RoutineItem) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
        persistRoutines()
    }

    func add(task: TaskItem) {
        todos.append(task)
        sortTasks()
        persistTodos()
    }

    func update(task: TaskItem) {
        guard let index = todos.firstIndex(where: { $0.id == task.id }) else { return }
        todos[index] = task
        sortTasks()
        persistTodos()
    }

    func removeTasks(at offsets: IndexSet) {
        todos.remove(atOffsets: offsets)
        sortTasks()
        persistTodos()
    }

    func toggleTaskCompletion(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        sortTasks()
        persistTodos()
    }

    func startTaskProgress(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        var task = todos[index]
        let now = Date()
        if task.actualStartTime == nil {
            task.actualStartTime = now
        }
        task.actualEndTime = nil
        task.actualDurationSeconds = nil
        todos[index] = task
        persistTodos()
    }

    func completeTaskProgress(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        var task = todos[index]
        let now = Date()
        if task.actualStartTime == nil {
            task.actualStartTime = now
        }
        task.actualEndTime = now
        task.actualDurationSeconds = max(0, now.timeIntervalSince(task.actualStartTime ?? now))
        task.isCompleted = true
        todos[index] = task
        sortTasks()
        persistTodos()
    }

    func setTaskDuration(id: UUID, minutes: Int?) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].estimatedDurationMinutes = minutes
        persistTodos()
    }

    func toggleAssignmentCompletion(id: String) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        assignments[index].isCompleted.toggle()
        sortAssignments()
        persistAssignments()
    }

    func startAssignmentProgress(id: String) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        var assignment = assignments[index]
        let now = Date()
        if assignment.actualStartTime == nil {
            assignment.actualStartTime = now
        }
        assignment.actualEndTime = nil
        assignment.actualDurationSeconds = nil
        assignments[index] = assignment
        persistAssignments()
    }

    func completeAssignmentProgress(id: String) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        var assignment = assignments[index]
        let now = Date()
        if assignment.actualStartTime == nil {
            assignment.actualStartTime = now
        }
        assignment.actualEndTime = now
        assignment.actualDurationSeconds = max(0, now.timeIntervalSince(assignment.actualStartTime ?? now))
        assignment.isCompleted = true
        assignments[index] = assignment
        sortAssignments()
        persistAssignments()
    }

    func setAssignmentDuration(id: String, minutes: Int?) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        assignments[index].estimatedDurationMinutes = minutes
        persistAssignments()
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
                return $0.dueDate < $1.dueDate
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
        }
    }

    private func loadAssignments() {
        guard let data = try? Data(contentsOf: assignmentsURL) else { return }
        if let decoded = try? decoder.decode(AssignmentsSnapshot.self, from: data) {
            assignments = decoded.assignments
            assignmentsLastUpdated = decoded.lastUpdated
            lastAssignmentSync = decoded.syncSource
            sortAssignments()
        }
    }

    private func loadRoutines() {
        guard let data = try? Data(contentsOf: routinesURL) else { return }
        if let decoded = try? decoder.decode([RoutineItem].self, from: data) {
            routines = decoded
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
