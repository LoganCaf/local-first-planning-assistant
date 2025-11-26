import SwiftUI
import MapKit
#if os(iOS)
import UIKit
#endif

struct TodoListView: View {
    @EnvironmentObject private var data: AppData
    var showNavigationTitle: Bool = true
    @State private var isPresentingAddTask = false
    @State private var draftTask = DraftTask()
    @State private var editingTask: TaskItem?
    @State private var editingDraft = DraftTask()

    var body: some View {
        NavigationStack {
            Group {
                if data.todos.isEmpty {
                    ContentUnavailableView(
                        "No todos",
                        systemImage: "checklist",
                        description: Text("Tap the + button to add a new todo.")
                    )
                } else {
                    List {
                        ForEach(data.todos) { task in
                            NavigationLink {
                                TodoDetailView(todoID: task.id)
                            } label: {
                                TodoRow(
                                    task: task,
                                    onToggleCompletion: {
                                        data.toggleTaskCompletion(id: task.id)
                                    },
                                    onEdit: {
                                        beginEditing(task)
                                    }
                                )
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button("Edit") {
                                    beginEditing(task)
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: removeTasks)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        draftTask = DraftTask()
                        isPresentingAddTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add todo")
                }
            }
            .navigationTitle(showNavigationTitle ? "Todo List" : "")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isPresentingAddTask) {
            TaskEditorSheet(mode: .create, draft: $draftTask) { draft in
                let newTask = TaskItem(
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDate: draft.dueDate,
                    startDate: draft.startDate,
                    priority: draft.priority,
                    estimatedDurationMinutes: draft.estimatedDurationMinutes,
                    location: draft.location,
                    travelEstimates: draft.travelEstimates,
                    hasDeadline: draft.hasDeadline
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
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(mode: .edit, draft: $editingDraft) { draft in
                var updated = task
                updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.dueDate = draft.dueDate
                updated.startDate = draft.startDate
                updated.priority = draft.priority
                updated.estimatedDurationMinutes = draft.estimatedDurationMinutes
                updated.location = draft.location
                updated.travelEstimates = draft.travelEstimates
                updated.hasDeadline = draft.hasDeadline
                data.update(task: updated)
            }
        }
    }

    private func removeTasks(at offsets: IndexSet) {
        data.removeTasks(at: offsets)
    }

    private func beginEditing(_ task: TaskItem) {
        editingDraft = DraftTask(task: task)
        editingTask = task
    }
}

struct DraftTask {
    var id: UUID?
    var title: String = ""
    var dueDate: Date = Date()
    var startDate: Date? = nil
    var hasDeadline: Bool = true
    var priority: TaskPriority = .medium
    var estimatedDurationMinutes: Int? = nil
    var location: TaskLocation? = nil
    var travelEstimates: TravelEstimates? = nil
    var segments: [TaskSegmentDraft] = []

    var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if hasDeadline, let startDate, startDate > dueDate {
            return false
        }
        return true
    }

    init() {}

    init(task: TaskItem) {
        id = task.id
        title = task.title
        dueDate = task.dueDate
        startDate = task.startDate
        hasDeadline = task.hasDeadline
        priority = task.priority
        estimatedDurationMinutes = task.estimatedDurationMinutes
        location = task.location
        travelEstimates = task.travelEstimates
        segments = []
    }
}

struct TodoRow: View {
    let task: TaskItem
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private var isLate: Bool {
        task.hasDeadline && !task.isCompleted && task.dueDate < Date()
    }

    private var deadlineText: String? {
        guard task.hasDeadline else { return nil }
        return formattedDateTime(task.dueDate)
    }

    private var actualStartText: String? {
        guard let start = task.startDate else { return nil }
        return formattedDateTime(start)
    }

    private var inferredStartText: String? {
        guard task.hasDeadline,
              task.startDate == nil,
              let minutes = task.estimatedDurationMinutes,
              minutes > 0 else {
            return nil
        }
        let inferred = task.dueDate.addingTimeInterval(-TimeInterval(minutes * 60))
        return formattedDateTime(inferred)
    }

    private var predictedEndText: String? {
        guard let start = task.startDate,
              let minutes = task.estimatedDurationMinutes,
              minutes > 0 else {
            return nil
        }
        let predicted = start.addingTimeInterval(TimeInterval(minutes * 60))
        return formattedDateTime(predicted)
    }

    private var durationText: String? {
        guard let minutes = task.estimatedDurationMinutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(remainingMinutes)m"
        }
    }

    private var locationName: String? {
        task.location?.name
    }

    private var locationSubtitle: String? {
        task.location?.subtitle
    }

    private var drivingEstimateText: String? {
        guard let minutes = task.travelEstimates?.drivingMinutes else { return nil }
        return "차 \(minutes)분"
    }

    private var walkingEstimateText: String? {
        guard let minutes = task.travelEstimates?.walkingMinutes else { return nil }
        return "도보 \(minutes)분"
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                    .accessibilityLabel(task.isCompleted ? "Mark todo incomplete" : "Mark todo complete")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted, color: .primary)
                    .opacity(task.isCompleted ? 0.6 : 1)

                VStack(alignment: .leading, spacing: 6) {
                    if let deadlineText {
                        Label("Due: \(deadlineText)", systemImage: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(isLate ? Color.red : Color.secondary)
                    } else {
                        Label("Deadline: TBD", systemImage: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }

                    Label("Priority: \(task.priority.displayName)", systemImage: task.priority.systemImageName)
                        .font(.caption)
                        .foregroundStyle(task.priority.tintColor)

                    if let startText = actualStartText {
                        Label("Start: \(startText)", systemImage: "play.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let inferred = inferredStartText {
                        Label("Est. start: \(inferred)", systemImage: "play.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let predictedEnd = predictedEndText {
                        Label("Est. finish: \(predictedEnd)", systemImage: "flag.checkered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let durationText {
                        Label("Duration: \(durationText)", systemImage: "hourglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let locationName {
                        Label(locationName, systemImage: "mappin.circle")
                            .font(.caption)
                        if let locationSubtitle {
                            Text(locationSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let drivingEstimateText {
                        Label(drivingEstimateText, systemImage: "car.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let walkingEstimateText {
                        Label(walkingEstimateText, systemImage: "figure.walk")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isLate {
                        Text("Late")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if task.isCompleted {
                        Text("Completed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .opacity(task.isCompleted ? 0.7 : 1)
        .contextMenu {
            Button("Edit", action: onEdit)
        }
    }
}

struct TaskEditorSheet: View {
    enum Mode {
        case create
        case edit
    }

    let mode: Mode
    @Binding var draft: DraftTask
    var onSave: (DraftTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var locationServices = LocationServices.shared
    @State private var isComputingTravel = false
    @State private var travelError: String?
    @State private var isPresentingSegmentSheet = false
    @State private var segmentEditorMode: TaskSegmentEditorSheet.Mode = .create
    @State private var activeSegmentDraft = TaskSegmentDraft()
    @State private var editingSegmentIndex: Int?

    private let durationOptions: [Int] = Array(stride(from: 0, through: 8 * 60, by: 30))

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $draft.title)
                }

                Section("Start time") {
                    Toggle("Provide start time", isOn: providesStartBinding)
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

                Section("Deadline") {
                    Toggle("Provide deadline", isOn: hasDeadlineBinding)
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

                Section("Location") {
                    if let location = draft.location {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.name)
                                .font(.headline)
                            if let subtitle = location.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("선택된 장소가 없어요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let estimates = draft.travelEstimates, estimates.hasData {
                        VStack(alignment: .leading, spacing: 4) {
                            if let driving = estimates.drivingMinutes {
                                Label("차 : \(driving)분", systemImage: "car.fill")
                            }
                            if let walking = estimates.walkingMinutes {
                                Label("도보 : \(walking)분", systemImage: "figure.walk")
                            }
                            if let updated = estimates.lastUpdated {
                                Text("마지막 계산: \(relativeDateString(from: updated))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }

                    if let travelError {
                        Text(travelError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    NavigationLink("장소 선택") {
                        PlaceSearchView { location in
                            draft.location = location
                            Task {
                                await recomputeTravelEstimates()
                            }
                        }
                    }

                    if draft.location != nil {
                        Button("장소 제거", role: .destructive) {
                            draft.location = nil
                            draft.travelEstimates = nil
                        }
                    }

                    if locationServices.currentLocation == nil {
                        Button("현재 위치 사용 요청") {
                            requestLocationAccess()
                        }
                    }

                    Button {
                        Task {
                            await recomputeTravelEstimates()
                        }
                    } label: {
                        if isComputingTravel {
                            ProgressView()
                        } else {
                            Text("이동 시간 다시 계산")
                        }
                    }
                    .disabled(draft.location == nil || isComputingTravel)
                }

                Section("Priority") {
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Estimated duration") {
                    Picker("Duration", selection: durationBinding) {
                        Text("None").tag(0)
                        ForEach(durationOptions.filter { $0 > 0 }, id: \.self) { minutes in
                            Text(durationLabel(for: minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if mode == .create {
                    Section("Segments") {
                        if draft.segments.isEmpty {
                            Text("No segments yet. Tap the button below to add one.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(draft.segments.enumerated()), id: \.offset) { index, segment in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(segment.title.isEmpty ? "Untitled segment" : segment.title)
                                        .font(.headline)
                                    if segment.hasDeadline {
                                        Text("Due: \(formattedDateTime(segment.dueDate))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("No deadline")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let start = segment.startDate {
                                        Text("Start: \(formattedDateTime(start))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let duration = segment.estimatedDurationMinutes {
                                        Text("Duration: \(durationLabel(for: duration))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 12) {
                                        Button("Edit") {
                                            segmentEditorMode = .edit
                                            editingSegmentIndex = index
                                            activeSegmentDraft = segment
                                            isPresentingSegmentSheet = true
                                        }
                                        .buttonStyle(.borderless)

                                        Button("Delete", role: .destructive) {
                                            draft.segments.remove(at: index)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .font(.caption)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Button {
                            segmentEditorMode = .create
                            editingSegmentIndex = nil
                            activeSegmentDraft = TaskSegmentDraft()
                            activeSegmentDraft.dueDate = draft.dueDate
                            activeSegmentDraft.hasDeadline = draft.hasDeadline
                            activeSegmentDraft.startDate = draft.startDate
                            activeSegmentDraft.priority = draft.priority
                            isPresentingSegmentSheet = true
                        } label: {
                            Label("Add segment", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle(mode == .create ? "Add todo" : "Edit todo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $isPresentingSegmentSheet) {
            TaskSegmentEditorSheet(
                mode: segmentEditorMode,
                draft: $activeSegmentDraft,
                parentName: draft.title.isEmpty ? "New Todo" : draft.title
            ) { savedDraft in
                switch segmentEditorMode {
                case .create:
                    draft.segments.append(savedDraft)
                case .edit:
                    if let index = editingSegmentIndex, draft.segments.indices.contains(index) {
                        draft.segments[index] = savedDraft
                    }
                }
                editingSegmentIndex = nil
            }
        }
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
            }
        )
    }

    private var hasDeadlineBinding: Binding<Bool> {
        Binding(
            get: { draft.hasDeadline },
            set: { newValue in
                let previous = draft.hasDeadline
                draft.hasDeadline = newValue
                if newValue {
                    if !previous {
                        let baseline = draft.startDate ?? Date()
                        if draft.dueDate < baseline {
                            draft.dueDate = baseline
                        }
                    }
                    ensureStartBeforeDue()
                }
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
            return "\(hours)h \(remaining)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(remaining)m"
        }
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
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

    private func requestLocationAccess() {
        switch locationServices.authorizationStatus {
        case .notDetermined:
            locationServices.requestAuthorization()
        case .denied, .restricted:
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
        default:
            locationServices.startUpdating()
        }
    }

    private func recomputeTravelEstimates() async {
        guard let destination = draft.location?.coordinate else { return }

        await MainActor.run {
            isComputingTravel = true
            travelError = nil
        }

        let origin = await MainActor.run { locationServices.currentLocation?.coordinate }

        guard let origin else {
            await MainActor.run {
                travelError = TravelTimeError.missingOrigin.localizedDescription
                isComputingTravel = false
            }
            return
        }

        do {
            let estimates = try await TravelTimeCalculator.estimateTravel(origin: origin, destination: destination)
            await MainActor.run {
                draft.travelEstimates = estimates
                travelError = nil
                isComputingTravel = false
            }
        } catch {
            await MainActor.run {
                travelError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isComputingTravel = false
            }
        }
    }
}

#Preview {
    TodoListView()
        .environmentObject(AppData())
}
