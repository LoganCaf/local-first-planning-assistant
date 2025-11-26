import SwiftUI

struct TaskSegmentDraft {
    var title: String = ""
    var dueDate: Date = Date()
    var startDate: Date? = nil
    var hasDeadline: Bool = true
    var priority: TaskPriority = .medium
    var estimatedDurationMinutes: Int? = nil

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!hasDeadline || startDate == nil || startDate! <= dueDate)
    }

    init() {}

    init(segment: TaskSegment) {
        title = segment.title
        dueDate = segment.dueDate
        startDate = segment.startDate
        hasDeadline = segment.hasDeadline
        priority = segment.priority
        estimatedDurationMinutes = segment.estimatedDurationMinutes
    }
}

struct TaskSegmentEditorSheet: View {
    enum Mode {
        case create
        case edit
    }

    let mode: Mode
    @Binding var draft: TaskSegmentDraft
    var parentName: String
    var onSave: (TaskSegmentDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    private let durationOptions: [Int] = Array(stride(from: 0, through: 8 * 60, by: 30))

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("단계 제목", text: $draft.title)
                    Text("원본: \(parentName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("시작 시간") {
                    Toggle("시작 시간 제공", isOn: providesStartBinding)
                    if draft.startDate != nil {
                        DatePicker(
                            "Start",
                            selection: startDateBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } else {
                        Text("시작 시간 미정")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("마감") {
                    Toggle("마감 제공", isOn: hasDeadlineBinding)
                    if draft.hasDeadline {
                        DatePicker(
                            "Due",
                            selection: dueDateBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } else {
                        Text("마감 미정")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("우선순위") {
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("예상 소요 시간") {
                    Picker("Duration", selection: durationBinding) {
                        Text("선택 안 함").tag(0)
                        ForEach(durationOptions.filter { $0 > 0 }, id: \.self) { minutes in
                            Text(durationLabel(for: minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle(mode == .create ? "단계 추가" : "단계 편집")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { draft.estimatedDurationMinutes ?? 0 },
            set: { newValue in
                draft.estimatedDurationMinutes = newValue == 0 ? nil : newValue
            }
        )
    }

    private var providesStartBinding: Binding<Bool> {
        Binding(
            get: { draft.startDate != nil },
            set: { newValue in
                if newValue {
                    if draft.startDate == nil {
                        draft.startDate = defaultStartDate()
                    }
                } else {
                    draft.startDate = nil
                }
                ensureStartBeforeDue()
            }
        )
    }

    private var hasDeadlineBinding: Binding<Bool> {
        Binding(
            get: { draft.hasDeadline },
            set: { newValue in
                draft.hasDeadline = newValue
                ensureStartBeforeDue()
            }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { draft.startDate ?? defaultStartDate() },
            set: { newValue in
                draft.startDate = newValue
                ensureStartBeforeDue()
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { draft.dueDate },
            set: { newValue in
                draft.dueDate = newValue
                ensureStartBeforeDue()
            }
        )
    }

    private func durationLabel(for minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours > 0 && remaining > 0 {
            return "\(hours)시간 \(remaining)분"
        } else if hours > 0 {
            return "\(hours)시간"
        }
        return "\(remaining)분"
    }

    private func defaultStartDate() -> Date {
        if draft.hasDeadline {
            return draft.dueDate.addingTimeInterval(-30 * 60)
        }
        return Date()
    }

    private func ensureStartBeforeDue() {
        guard draft.hasDeadline else { return }
        if let start = draft.startDate, start > draft.dueDate {
            draft.dueDate = start
        }
    }
}
