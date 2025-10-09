import SwiftUI
import MapKit

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
                            TodoRow(
                                task: task,
                                onToggleCompletion: {
                                    data.toggleTaskCompletion(id: task.id)
                                },
                                onEdit: {
                                    beginEditing(task)
                                }
                            )
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
                    travelEstimates: draft.travelEstimates
                )
                data.add(task: newTask)
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
    var usesDueTime: Bool = true
    var priority: TaskPriority = .medium
    var estimatedDurationMinutes: Int? = nil
    var location: TaskLocation? = nil
    var travelEstimates: TravelEstimates? = nil

    var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let startDate, startDate > dueDate {
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
        let calendar = Calendar.current
        let endOfDay = calendar.endOfDay(for: calendar.startOfDay(for: task.dueDate)) ?? task.dueDate
        usesDueTime = !calendar.isDate(task.dueDate, equalTo: endOfDay, toGranularity: .minute)
        priority = task.priority
        estimatedDurationMinutes = task.estimatedDurationMinutes
        location = task.location
        travelEstimates = task.travelEstimates
    }
}

struct TodoRow: View {
    let task: TaskItem
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private var isLate: Bool {
        !task.isCompleted && task.dueDate < Date()
    }

    private var deadlineText: String {
        formattedDateTime(task.dueDate)
    }

    private var actualStartText: String? {
        guard let start = task.startDate else { return nil }
        return formattedDateTime(start)
    }

    private var inferredStartText: String? {
        guard task.startDate == nil,
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
                    Label("Due: \(deadlineText)", systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(isLate ? Color.red : Color.secondary)

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
    @State private var isShowingPlaceSearch = false
    @State private var isComputingTravel = false
    @State private var travelError: String?

    private let durationOptions: [Int] = Array(stride(from: 0, through: 8 * 60, by: 30))

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $draft.title)
                }

                Section("Start time") {
                    Toggle("Provide start time", isOn: usesStartBinding)
                    if draft.startDate != nil {
                        DatePicker("Start", selection: startDateBinding, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Deadline") {
                    Toggle("Provide deadline", isOn: usesDueTimeBinding)
                    if draft.usesDueTime {
                        DatePicker("Due date & time", selection: dueDateTimeBinding, displayedComponents: [.date, .hourAndMinute])
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

                    Button("장소 선택") {
                        isShowingPlaceSearch = true
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
                    .pickerStyle(.wheel)
                    .frame(height: 160)
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
        .sheet(isPresented: $isShowingPlaceSearch) {
            PlaceSearchView { location in
                draft.location = location
                Task {
                    await recomputeTravelEstimates()
                }
            }
        }
        .onAppear {
            if locationServices.authorizationStatus == .notDetermined {
                locationServices.requestAuthorization()
            } else {
                locationServices.startUpdating()
            }
        }
        .onDisappear {
            locationServices.stopUpdating()
        }
    }

    private var usesStartBinding: Binding<Bool> {
        Binding(
            get: { draft.startDate != nil },
            set: { newValue in
                if newValue {
                    if draft.startDate == nil {
                        draft.startDate = draft.dueDate.addingTimeInterval(-30 * 60)
                    }
                } else {
                    draft.startDate = nil
                }
            }
        )
    }

    private var usesDueTimeBinding: Binding<Bool> {
        Binding(
            get: { draft.usesDueTime },
            set: { newValue in
                applyDueTimeToggle(newValue)
            }
        )
    }

    private var dueDateTimeBinding: Binding<Date> {
        Binding(
            get: { draft.dueDate },
            set: { newValue in
                draft.dueDate = newValue
                ensureStartNotAfterDue()
            }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { draft.startDate ?? draft.dueDate },
            set: { newValue in
                draft.startDate = newValue
                if draft.dueDate < newValue {
                    draft.dueDate = newValue
                }
            }
        )
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { draft.estimatedDurationMinutes ?? 0 },
            set: { newValue in
                draft.estimatedDurationMinutes = newValue == 0 ? nil : newValue
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

    private func ensureStartNotAfterDue() {
        if let start = draft.startDate, start > draft.dueDate {
            if draft.usesDueTime {
                draft.dueDate = start
            } else {
                let base = Calendar.current.startOfDay(for: start)
                draft.dueDate = Calendar.current.endOfDay(for: base) ?? start
            }
        }
    }

    private func applyDueTimeToggle(_ enabled: Bool) {
        draft.usesDueTime = enabled
        let calendar = Calendar.current
        if enabled {
            let baseDay = calendar.startOfDay(for: draft.dueDate)
            draft.dueDate = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: baseDay) ?? draft.dueDate
            if draft.startDate == nil {
                draft.startDate = draft.dueDate.addingTimeInterval(-30 * 60)
            }
        } else {
            draft.startDate = nil
            draft.dueDate = calendar.endOfDay(for: draft.dueDate) ?? draft.dueDate
        }
        ensureStartNotAfterDue()
    }

    private func requestLocationAccess() {
        locationServices.requestAuthorization()
        locationServices.startUpdating()
    }

    @MainActor
    private func recomputeTravelEstimates() async {
        guard let location = draft.location else {
            return
        }
        guard let origin = locationServices.currentLocation else {
            travelError = TravelTimeError.missingOrigin.localizedDescription
            return
        }
        isComputingTravel = true
        travelError = nil
        do {
            let estimates = try await TravelTimeCalculator.estimateTravel(
                origin: origin.coordinate,
                destination: location.coordinate
            )
            draft.travelEstimates = estimates
        } catch {
            travelError = error.localizedDescription
        }
        isComputingTravel = false
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    TodoListView()
        .environmentObject(AppData())
}
