import SwiftUI

struct DayDetailView: View {
    @EnvironmentObject private var data: AppData
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    let date: Date
    @State private var isPresentingAddTodo = false
    @State private var draftTodo = DraftTask()
    @State private var isPresentingSegmentSheet = false
    @State private var segmentDraft = TaskSegmentDraft()
    @State private var editingSegment: TaskSegment?
    @State private var segmentParentTitle: String = ""

    private var todosForDay: [TaskItem] {
        data.todos.filter { $0.hasDeadline && calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var assignmentsForDay: [SchoolAssignment] {
        data.assignments.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var segmentsForDay: [TaskSegment] {
        data.taskSegments.filter { segment in
            calendar.isDate(segment.dueDate, inSameDayAs: date)
        }
        .sorted { lhs, rhs in
            if lhs.dueDate == rhs.dueDate {
                return lhs.title < rhs.title
            }
            return lhs.dueDate < rhs.dueDate
        }
    }

    var body: some View {
        List {
            if !todosForDay.isEmpty {
                Section("Todos") {
                    ForEach(todosForDay) { todo in
                        DayDetailTodoRow(
                            todo: todo,
                            calendar: calendar,
                            locale: locale,
                            onToggleCompletion: {
                                data.toggleTaskCompletion(id: todo.id)
                            },
                            onStart: {
                                data.startTaskProgress(id: todo.id)
                            },
                            onPause: {
                                data.pauseTaskProgress(id: todo.id)
                            },
                            onFinish: {
                                data.completeTaskProgress(id: todo.id)
                            }
                        )
                    }
                }
            }

            if !assignmentsForDay.isEmpty {
                Section("Assignments") {
                    ForEach(assignmentsForDay) { assignment in
                        DayDetailAssignmentRow(
                            assignment: assignment,
                            calendar: calendar,
                            locale: locale,
                            onToggleCompletion: {
                                data.toggleAssignmentCompletion(id: assignment.id)
                            },
                            onStart: {
                                data.startAssignmentProgress(id: assignment.id)
                            },
                            onPause: {
                                data.pauseAssignmentProgress(id: assignment.id)
                            },
                            onFinish: {
                                data.completeAssignmentProgress(id: assignment.id)
                            }
                        )
                    }
                }
            }

            if !segmentsForDay.isEmpty {
                Section("Segments") {
                    ForEach(segmentsForDay) { segment in
                        TaskSegmentRow(
                            segment: segment,
                            parentTitle: parentTitle(for: segment),
                            onToggleCompletion: {
                                data.toggleSegmentCompletion(id: segment.id)
                            },
                            onStart: {
                                data.startSegmentProgress(id: segment.id)
                            },
                            onPause: {
                                data.pauseSegmentProgress(id: segment.id)
                            },
                            onFinish: {
                                data.completeSegmentProgress(id: segment.id)
                            },
                            onEdit: {
                                segmentDraft = TaskSegmentDraft(segment: segment)
                                editingSegment = segment
                                segmentParentTitle = parentTitle(for: segment)
                                isPresentingSegmentSheet = true
                            }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                data.removeSegment(id: segment.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if todosForDay.isEmpty && assignmentsForDay.isEmpty && segmentsForDay.isEmpty {
                Section {
                    Text("No items for this day.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(dayTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    prepareDraftForSelectedDay()
                    isPresentingAddTodo = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add todo")
            }
        }
        .sheet(isPresented: $isPresentingAddTodo) {
            TaskEditorSheet(mode: .create, draft: $draftTodo) { draft in
                let newTask = TaskItem(
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDate: draft.dueDate,
                    startDate: draft.startDate,
                    priority: draft.priority,
                    estimatedDurationMinutes: draft.estimatedDurationMinutes,
                    location: draft.location,
                    travelEstimates: draft.travelEstimates
                )
                data.add(task: newTask)
                for segmentDraft in draft.segments {
                    let segment = TaskSegment(
                        parentType: .todo,
                        parentIdentifier: newTask.id.uuidString,
                        title: segmentDraft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        dueDate: segmentDraft.dueDate,
                        startDate: segmentDraft.startDate,
                        hasDeadline: segmentDraft.hasDeadline,
                        priority: segmentDraft.priority,
                        estimatedDurationMinutes: segmentDraft.estimatedDurationMinutes
                    )
                    data.add(segment: segment)
                }
            }
        }
        .sheet(isPresented: $isPresentingSegmentSheet) {
            TaskSegmentEditorSheet(
                mode: .edit,
                draft: $segmentDraft,
                parentName: segmentParentTitle.isEmpty ? "Segment" : segmentParentTitle
            ) { draft in
                guard let editingSegment else { return }
                var updated = editingSegment
                updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.dueDate = draft.dueDate
                updated.startDate = draft.startDate
                updated.hasDeadline = draft.hasDeadline
                updated.priority = draft.priority
                updated.estimatedDurationMinutes = draft.estimatedDurationMinutes
                data.update(segment: updated)
                self.editingSegment = nil
            }
        }
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.calendar = calendar
        return formatter.string(from: date)
    }

    private func timeString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.calendar = calendar
        return fmt.string(from: date)
    }

    private func timeRangeString(start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.calendar = calendar
        return "\(fmt.string(from: start)) - \(fmt.string(from: end))"
    }

    private func prepareDraftForSelectedDay() {
        var draft = DraftTask()
        let startOfDay = calendar.startOfDay(for: date)
        if let due = calendar.date(byAdding: .hour, value: 21, to: startOfDay) {
            draft.dueDate = due
        } else {
            draft.dueDate = date
        }
        draft.startDate = nil
        draft.hasDeadline = true
        draftTodo = draft
    }

    private func parentTitle(for segment: TaskSegment) -> String {
        switch segment.parentType {
        case .todo:
            if let uuid = UUID(uuidString: segment.parentIdentifier),
               let todo = data.todos.first(where: { $0.id == uuid }) {
                return todo.title
            }
            return "Todo"
        case .assignment:
            if let assignment = data.assignments.first(where: { $0.id == segment.parentIdentifier }) {
                return assignment.title
            }
            return "Assignment"
        }
    }
}


private struct DayDetailTodoRow: View {
    let todo: TaskItem
    let calendar: Calendar
    let locale: Locale
    let onToggleCompletion: () -> Void
    let onStart: () -> Void
    let onPause: () -> Void
    let onFinish: () -> Void
    @State private var showFinishConfirmation = false

    private var hasTrackingStarted: Bool {
        todo.actualStartTime != nil
    }

    private var hasTrackingCompleted: Bool {
        todo.actualEndTime != nil
    }

    private var isTimerRunning: Bool {
        todo.activeTimerStart != nil
    }

    private var isInProgress: Bool {
        hasTrackingStarted && !hasTrackingCompleted
    }

    private var elapsedSeconds: TimeInterval? {
        if let activeStart = todo.activeTimerStart {
            let accumulated = todo.actualDurationSeconds ?? 0
            return max(0, accumulated + Date().timeIntervalSince(activeStart))
        }
        if let total = todo.actualDurationSeconds {
            return max(0, total)
        }
        if let start = todo.actualStartTime {
            let end = todo.actualEndTime ?? Date()
            return max(0, end.timeIntervalSince(start))
        }
        return nil
    }

    private var stopwatchText: String? {
        guard let seconds = elapsedSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggleCompletion) {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.isCompleted ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading) {
                    Text(todo.title)
                        .font(.headline)
                        .strikethrough(todo.isCompleted, color: .primary)
                    if let deadline = deadlineText {
                        Text(deadline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Deadline not set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let start = todo.actualStartTime {
                Label("Start: \(formattedDateTime(start))", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let stopwatchText {
                Label("\(hasTrackingCompleted ? "Total time" : "Elapsed"): \(stopwatchText)", systemImage: "stopwatch")
                    .font(.caption)
                    .foregroundStyle(isTimerRunning ? Color.accentColor : .secondary)
            }
            if let end = todo.actualEndTime {
                Label("Finish: \(formattedDateTime(end))", systemImage: "flag.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !hasTrackingStarted && !hasTrackingCompleted {
                    Button("Start", action: onStart)
                        .buttonStyle(.bordered)
                }
                if isInProgress {
                    if isTimerRunning {
                        Button("Pause", action: onPause)
                            .buttonStyle(.bordered)
                    } else {
                        Button("Resume", action: onStart)
                            .buttonStyle(.bordered)
                    }
                    Button("Done") {
                        showFinishConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog("Are you really done?", isPresented: $showFinishConfirmation, titleVisibility: .visible) {
            Button("Yes, finished", role: .destructive, action: onFinish)
            Button("Cancel", role: .cancel, action: {})
        }
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var deadlineText: String? {
        guard todo.hasDeadline else { return nil }
        return formattedDateTime(todo.dueDate)
    }
}

private struct DayDetailAssignmentRow: View {
    let assignment: SchoolAssignment
    let calendar: Calendar
    let locale: Locale
    let onToggleCompletion: () -> Void
    let onStart: () -> Void
    let onPause: () -> Void
    let onFinish: () -> Void
    @State private var showFinishConfirmation = false

    private var hasTrackingStarted: Bool {
        assignment.actualStartTime != nil
    }

    private var hasTrackingCompleted: Bool {
        assignment.actualEndTime != nil
    }

    private var isTimerRunning: Bool {
        assignment.activeTimerStart != nil
    }

    private var isInProgress: Bool {
        hasTrackingStarted && !hasTrackingCompleted
    }

    private var elapsedSeconds: TimeInterval? {
        if let activeStart = assignment.activeTimerStart {
            let accumulated = assignment.actualDurationSeconds ?? 0
            return max(0, accumulated + Date().timeIntervalSince(activeStart))
        }
        if let total = assignment.actualDurationSeconds {
            return max(0, total)
        }
        if let start = assignment.actualStartTime {
            let end = assignment.actualEndTime ?? Date()
            return max(0, end.timeIntervalSince(start))
        }
        return nil
    }

    private var stopwatchText: String? {
        guard let seconds = elapsedSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggleCompletion) {
                    Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(assignment.isCompleted ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading) {
                    Text(assignment.title)
                        .font(.headline)
                        .strikethrough(assignment.isCompleted, color: .primary)
                    Text(assignmentRangeText())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let start = assignment.actualStartTime {
                Label("Start: \(formattedDateTime(start))", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let stopwatchText {
                Label("\(hasTrackingCompleted ? "Total time" : "Elapsed"): \(stopwatchText)", systemImage: "stopwatch")
                    .font(.caption)
                    .foregroundStyle(isTimerRunning ? Color.accentColor : .secondary)
            }
            if let end = assignment.actualEndTime {
                Label("Finish: \(formattedDateTime(end))", systemImage: "flag.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !hasTrackingStarted && !hasTrackingCompleted {
                    Button("Start", action: onStart)
                        .buttonStyle(.bordered)
                }
                if isInProgress {
                    if isTimerRunning {
                        Button("Pause", action: onPause)
                            .buttonStyle(.bordered)
                    } else {
                        Button("Resume", action: onStart)
                            .buttonStyle(.bordered)
                    }
                    Button("Done") {
                        showFinishConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog("Are you really done?", isPresented: $showFinishConfirmation, titleVisibility: .visible) {
            Button("Yes, finished", role: .destructive, action: onFinish)
            Button("Cancel", role: .cancel, action: {})
        }
    }

    private func assignmentRangeText() -> String {
        if let end = assignment.displayEndDate(using: calendar) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            let start = formatter.string(from: assignment.dueDate)
            let endText = formatter.string(from: end)
            return "\(start) - \(endText)"
        }
        return formattedDateTime(assignment.dueDate)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        DayDetailView(date: Date())
            .environmentObject(AppData())
    }
}
