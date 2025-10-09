import SwiftUI

struct DayDetailView: View {
    @EnvironmentObject private var data: AppData
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    let date: Date

    private var todosForDay: [TaskItem] {
        data.todos.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var assignmentsForDay: [SchoolAssignment] {
        data.assignments.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
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
                            onFinish: {
                                data.completeAssignmentProgress(id: assignment.id)
                            }
                        )
                    }
                }
            }

            if todosForDay.isEmpty && assignmentsForDay.isEmpty {
                Section {
                    Text("No items for this day.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(dayTitle)
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
}


private struct DayDetailTodoRow: View {
    let todo: TaskItem
    let calendar: Calendar
    let locale: Locale
    let onToggleCompletion: () -> Void
    let onStart: () -> Void
    let onFinish: () -> Void
    @State private var showFinishConfirmation = false

    private var isTrackingActive: Bool {
        todo.actualStartTime != nil && todo.actualEndTime == nil
    }

    private var hasTrackingCompleted: Bool {
        todo.actualStartTime != nil && todo.actualEndTime != nil
    }

    private var stopwatchText: String? {
        guard let start = todo.actualStartTime else { return nil }
        let end = todo.actualEndTime ?? Date()
        let seconds = max(0, end.timeIntervalSince(start))
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
                    Text(formattedDateTime(todo.dueDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let start = todo.actualStartTime {
                Label("시작: \(formattedDateTime(start))", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let stopwatchText {
                Label("\(hasTrackingCompleted ? "총 소요" : "경과"): \(stopwatchText)", systemImage: "stopwatch")
                    .font(.caption)
                    .foregroundStyle(isTrackingActive ? Color.accentColor : .secondary)
            }
            if let end = todo.actualEndTime {
                Label("종료: \(formattedDateTime(end))", systemImage: "flag.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !isTrackingActive && !hasTrackingCompleted {
                    Button("Start", action: onStart)
                        .buttonStyle(.bordered)
                }
                if isTrackingActive {
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
}

private struct DayDetailAssignmentRow: View {
    let assignment: SchoolAssignment
    let calendar: Calendar
    let locale: Locale
    let onToggleCompletion: () -> Void
    let onStart: () -> Void
    let onFinish: () -> Void
    @State private var showFinishConfirmation = false

    private var isTrackingActive: Bool {
        assignment.actualStartTime != nil && assignment.actualEndTime == nil
    }

    private var hasTrackingCompleted: Bool {
        assignment.actualStartTime != nil && assignment.actualEndTime != nil
    }

    private var stopwatchText: String? {
        guard let start = assignment.actualStartTime else { return nil }
        let end = assignment.actualEndTime ?? Date()
        let seconds = max(0, end.timeIntervalSince(start))
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
                Label("시작: \(formattedDateTime(start))", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let stopwatchText {
                Label("\(hasTrackingCompleted ? "총 소요" : "경과"): \(stopwatchText)", systemImage: "stopwatch")
                    .font(.caption)
                    .foregroundStyle(isTrackingActive ? Color.accentColor : .secondary)
            }
            if let end = assignment.actualEndTime {
                Label("종료: \(formattedDateTime(end))", systemImage: "flag.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !isTrackingActive && !hasTrackingCompleted {
                    Button("Start", action: onStart)
                        .buttonStyle(.bordered)
                }
                if isTrackingActive {
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
