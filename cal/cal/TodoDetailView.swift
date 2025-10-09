import SwiftUI

struct TodoDetailView: View {
    let todoID: UUID

    @EnvironmentObject private var data: AppData
    @Environment(\.calendar) private var calendar
    @State private var isPresentingEditSheet = false
    @State private var draft = DraftTask()

    private var todo: TaskItem? {
        data.todos.first(where: { $0.id == todoID })
    }

    var body: some View {
        Group {
            if let todo = todo {
                List {
                    Section {
                        Text(todo.title)
                            .font(.title3.weight(.semibold))

                        HStack {
                            Button(todo.isCompleted ? "Mark as not completed" : "Mark as completed") {
                                data.toggleTaskCompletion(id: todo.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(todo.isCompleted ? .orange : .green)
                        }
                    }

                    Section("Schedule") {
                        if let start = todo.startDate {
                            detailRow(title: "Start", value: dateTimeString(for: start))
                        } else if let inferredStart = inferredStartDate(for: todo) {
                            detailRow(title: "Estimated start", value: dateTimeString(for: inferredStart))
                        }

                        detailRow(title: "Due", value: dateTimeString(for: todo.dueDate))

                        if let predictedEnd = predictedEndDate(for: todo) {
                            detailRow(title: "Estimated finish", value: dateTimeString(for: predictedEnd))
                        }

                        if let minutes = todo.estimatedDurationMinutes {
                            detailRow(title: "Duration", value: durationText(for: minutes))
                        }
                    }

                    if todo.actualStartTime != nil || todo.actualEndTime != nil || todo.actualDurationSeconds != nil {
                        Section("Progress") {
                            if let actualStart = todo.actualStartTime {
                                detailRow(title: "Actual start", value: dateTimeString(for: actualStart))
                            }
                            if let actualEnd = todo.actualEndTime {
                                detailRow(title: "Actual finish", value: dateTimeString(for: actualEnd))
                            }
                            if let seconds = todo.actualDurationSeconds {
                                let minutes = Int((seconds / 60.0).rounded())
                                detailRow(title: "Tracked duration", value: durationText(for: minutes))
                            }
                        }
                    }

                    if let location = todo.location {
                        Section("Location") {
                            detailRow(title: "Name", value: location.name)
                            if let subtitle = location.subtitle {
                                detailRow(title: "Address", value: subtitle)
                            }
                        }
                    }

                    if let travel = todo.travelEstimates, travel.hasData {
                        Section("Travel Time") {
                            if let driving = travel.drivingMinutes {
                                detailRow(title: "Driving", value: "\(driving) min")
                            }
                            if let walking = travel.walkingMinutes {
                                detailRow(title: "Walking", value: "\(walking) min")
                            }
                            if let updated = travel.lastUpdated {
                                detailRow(title: "Updated", value: dateTimeString(for: updated))
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Todo Detail")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") {
                            draft = DraftTask(task: todo)
                            isPresentingEditSheet = true
                        }
                    }
                }
                .sheet(isPresented: $isPresentingEditSheet) {
                    TaskEditorSheet(mode: .edit, draft: $draft) { draft in
                        var updated = todo
                        updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.dueDate = draft.dueDate
                        updated.startDate = draft.startDate
                        updated.priority = draft.priority
                        updated.estimatedDurationMinutes = draft.estimatedDurationMinutes
                        data.update(task: updated)
                    }
                }
            } else {
                ContentUnavailableView("Todo not found", systemImage: "questionmark.circle", description: Text("Select another todo from the list."))
            }
        }
    }

    private func inferredStartDate(for task: TaskItem) -> Date? {
        guard task.startDate == nil,
              let minutes = task.estimatedDurationMinutes,
              minutes > 0 else {
            return nil
        }
        return task.dueDate.addingTimeInterval(-TimeInterval(minutes * 60))
    }

    private func predictedEndDate(for task: TaskItem) -> Date? {
        guard let start = task.startDate,
              let minutes = task.estimatedDurationMinutes,
              minutes > 0 else {
            return nil
        }
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func dateTimeString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func durationText(for minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours > 0 && remaining > 0 {
            return "\(hours)h \(remaining)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        return "\(remaining)m"
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

#Preview {
    NavigationStack {
        TodoDetailView(todoID: UUID())
            .environmentObject(AppData())
    }
}
