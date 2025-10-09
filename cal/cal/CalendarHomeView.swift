import SwiftUI
import Combine

struct CalendarHomeView: View {
    @EnvironmentObject private var data: AppData
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var now: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var activeCountdownRoute: CountdownRoute? = nil

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CalendarMonthView(onDayTap: { date in
                    selectedDate = date
                }, eventsProvider: { date in
                    // Count todos and assignments for the given date
                    let todoCount = data.todos.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }.count
                    let assignmentCount = data.assignments.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }.count
                    let total = todoCount + assignmentCount
                    return total > 0 ? total : nil
                })

                TodayCountdownSection(
                    items: todaysCountdowns,
                    now: now,
                    calendar: calendar,
                    locale: locale,
                    onToggleCompletion: handleCompletionToggle,
                    onStartTracking: handleStartTracking,
                    onFinishTracking: handleFinishTracking,
                    onSelectItem: { route in
                        activeCountdownRoute = route
                    }
                )

                if !activeTrackingItems.isEmpty {
                    ActiveTrackingSection(
                        items: activeTrackingItems,
                        now: now,
                        calendar: calendar,
                        locale: locale,
                        onToggleCompletion: handleCompletionToggle,
                        onStartTracking: handleStartTracking,
                        onFinishTracking: handleFinishTracking,
                        onSelectItem: { route in
                            activeCountdownRoute = route
                        }
                    )
                }
            }
            .padding(.top, 8)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    .background(Color(.systemGroupedBackground))
        .onAppear {
            now = Date()
        }
        .onReceive(timer) { output in
            now = output
        }
        .navigationDestination(isPresented: Binding(get: { selectedDate != nil }, set: { if !$0 { selectedDate = nil } })) {
            if let date = selectedDate {
                DayDetailView(date: date)
                    .environmentObject(data)
            }
        }
        .navigationDestination(isPresented: Binding(get: { activeCountdownRoute != nil }, set: { if !$0 { activeCountdownRoute = nil } })) {
            if let route = activeCountdownRoute {
                switch route {
                case .todo(let id):
                    TodoDetailView(todoID: id)
                        .environmentObject(data)
                case .assignment(let id):
                    AssignmentDetailView(assignmentID: id)
                        .environmentObject(data)
                }
            }
        }
    }

    private var todaysCountdowns: [CountdownItem] {
        let currentDayStart = calendar.startOfDay(for: now)
        guard let currentDayEnd = calendar.date(byAdding: .day, value: 1, to: currentDayStart) else {
            return []
        }

        var items: [CountdownItem] = []

        for task in data.todos {
            if calendar.isDate(task.dueDate, inSameDayAs: now) {
                items.append(CountdownItem(task: task))
            }
        }

        for assignment in data.assignments {
            if calendar.isDate(assignment.dueDate, inSameDayAs: now) {
                items.append(CountdownItem(assignment: assignment, calendar: calendar))
            }
        }

        return items
            .filter { $0.endDate >= currentDayStart && $0.startDate < currentDayEnd }
            .sorted { $0.endDate < $1.endDate }
    }

    private var activeTrackingItems: [CountdownItem] {
        let todoItems = data.todos
            .filter { $0.actualStartTime != nil && $0.actualEndTime == nil }
            .map { CountdownItem(task: $0) }
        let assignmentItems = data.assignments
            .filter { $0.actualStartTime != nil && $0.actualEndTime == nil }
            .map { CountdownItem(assignment: $0, calendar: calendar) }
        return (todoItems + assignmentItems).sorted {
            let lhs = $0.actualStartTime ?? $0.startDate
            let rhs = $1.actualStartTime ?? $1.startDate
            return lhs < rhs
        }
    }
}

private extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension CalendarHomeView {
    func handleCompletionToggle(for item: CountdownItem) {
        switch item.source {
        case .todo(let task):
            data.toggleTaskCompletion(id: task.id)
        case .assignment(let assignment):
            data.toggleAssignmentCompletion(id: assignment.id)
        }
    }

    func handleStartTracking(for item: CountdownItem) {
        switch item.source {
        case .todo(let task):
            data.startTaskProgress(id: task.id)
        case .assignment(let assignment):
            data.startAssignmentProgress(id: assignment.id)
        }
    }

    func handleFinishTracking(for item: CountdownItem) {
        switch item.source {
        case .todo(let task):
            data.completeTaskProgress(id: task.id)
        case .assignment(let assignment):
            data.completeAssignmentProgress(id: assignment.id)
        }
    }
}

private enum CountdownRoute: Hashable {
    case todo(UUID)
    case assignment(String)
}

private struct TodayCountdownSection: View {
    let items: [CountdownItem]
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let onToggleCompletion: (CountdownItem) -> Void
    let onStartTracking: (CountdownItem) -> Void
    let onFinishTracking: (CountdownItem) -> Void
    let onSelectItem: ((CountdownRoute) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's countdown")
                .font(.title3.bold())

            if items.isEmpty {
                ContentUnavailableView(
                    "No events today",
                    systemImage: "sun.max",
                    description: Text("Add a todo or assignment and you'll see the countdown here.")
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(items) { item in
                        CountdownRow(
                            item: item,
                            now: now,
                            calendar: calendar,
                            locale: locale,
                            onToggleCompletion: {
                                onToggleCompletion(item)
                            },
                            onStart: {
                                onStartTracking(item)
                            },
                            onFinish: {
                                onFinishTracking(item)
                            },
                            onSelect: { route in
                                onSelectItem?(route)
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct ActiveTrackingSection: View {
    let items: [CountdownItem]
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let onToggleCompletion: (CountdownItem) -> Void
    let onStartTracking: (CountdownItem) -> Void
    let onFinishTracking: (CountdownItem) -> Void
    let onSelectItem: ((CountdownRoute) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Started")
                .font(.title3.bold())

            LazyVStack(spacing: 16) {
                ForEach(items) { item in
                    CountdownRow(
                        item: item,
                        now: now,
                        calendar: calendar,
                        locale: locale,
                        onToggleCompletion: {
                            onToggleCompletion(item)
                        },
                        onStart: {
                            onStartTracking(item)
                        },
                        onFinish: {
                            onFinishTracking(item)
                        },
                        onSelect: { route in
                            onSelectItem?(route)
                        }
                    )
                }
            }
        }
    }
}

private struct CountdownRow: View {
    let item: CountdownItem
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let onToggleCompletion: () -> Void
    let onStart: () -> Void
    let onFinish: () -> Void
    let onSelect: ((CountdownRoute) -> Void)?
    @State private var showFinishConfirmation = false

    private var dayStart: Date {
        calendar.startOfDay(for: now)
    }

    private var isCompleted: Bool {
        item.isCompleted
    }

    private var isLate: Bool {
        item.isOverdue(relativeTo: now)
    }

    private var totalInterval: TimeInterval {
        max(item.endDate.timeIntervalSince(dayStart), 1)
    }

    private var remainingInterval: TimeInterval {
        guard !isCompleted else { return 0 }
        return item.endDate.timeIntervalSince(now)
    }

    private var clampedProgress: Double {
        guard !isCompleted else { return 0 }
        let progress = remainingInterval / totalInterval
        return min(max(progress, 0), 1)
    }

    private var gaugeColor: Color {
        if isCompleted {
            return .green
        }
        if isLate {
            return .red
        }
        let hue = max(0.0, min(0.33, 0.33 * clampedProgress))
        return Color(hue: hue, saturation: 0.9, brightness: 0.9)
    }

    private var actualStartText: String? {
        guard let actual = item.actualStartTime else { return nil }
        return DateFormatter.shortDateTime.string(from: actual)
    }

    private var actualEndText: String? {
        guard let actual = item.actualEndTime else { return nil }
        return DateFormatter.shortDateTime.string(from: actual)
    }

    private var stopwatchText: String? {
        guard let seconds = item.elapsedSeconds(relativeTo: now) else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggleCompletion) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isCompleted ? Color.green : Color.secondary)
                        .accessibilityLabel(isCompleted ? "완료 취소" : "완료 표시")
                }
                .buttonStyle(.plain)

                Image(systemName: item.iconName)
                    .font(.title3)
                    .foregroundStyle(isCompleted ? Color.green.opacity(0.6) : item.accentColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .strikethrough(isCompleted, color: .primary)
                        .opacity(isCompleted ? 0.6 : 1)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.timelineDescription(using: calendar, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isLate {
                        Text("늦음")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Text(dueTimeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isLate ? .red : .secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                switch item.source {
                case .todo(let task):
                    onSelect?(.todo(task.id))
                case .assignment(let assignment):
                    onSelect?(.assignment(assignment.id))
                }
            }

            Gauge(value: clampedProgress) {
                Text(remainingText)
                    .font(.caption)
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(gaugeColor)

            if actualStartText != nil || stopwatchText != nil || actualEndText != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let actualStartText {
                        Label("시작: \(actualStartText)", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let stopwatchText {
                        Label("\(item.hasTrackingCompleted ? "총 소요" : "경과"): \(stopwatchText)", systemImage: "stopwatch")
                            .font(.caption)
                            .foregroundStyle(item.isTrackingActive ? Color.accentColor : .secondary)
                    }
                    if let actualEndText {
                        Label("종료: \(actualEndText)", systemImage: "flag.checkered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                if !item.isTrackingActive && !item.hasTrackingCompleted {
                    Button {
                        onStart()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                }

                if item.isTrackingActive {
                    Button {
                        showFinishConfirmation = true
                    } label: {
                        Label("Done", systemImage: "checkmark.circle")
                    }
                    .tint(.green)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .opacity(isCompleted ? 0.7 : 1)
        .confirmationDialog("Are you really done?", isPresented: $showFinishConfirmation, titleVisibility: .visible) {
            Button("Yes, finished", role: .destructive) {
                onFinish()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var remainingText: String {
        if isCompleted {
            return "완료됨"
        }
        if isLate {
            return "늦음"
        }

        if remainingInterval <= 0 {
            return "마감 지남"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.calendar = calendar
        formatter.maximumUnitCount = 2

        if let formatted = formatter.string(from: remainingInterval) {
            return "\(formatted) 남음"
        }
        return "곧 마감"
    }

    private var dueTimeText: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let dueString = formatter.string(from: item.endDate)
        if item.usesFallbackEnd {
            return "\(dueString) (기본 23:59)"
        }
        return dueString
    }
}


private struct CountdownItem: Identifiable {
    enum Source {
        case todo(TaskItem)
        case assignment(SchoolAssignment)
    }

    let source: Source
    let startDate: Date
    let endDate: Date
    let usesFallbackEnd: Bool
    let actualStartTime: Date?
    let actualEndTime: Date?
    let actualDurationSeconds: Double?

    init(task: TaskItem) {
        source = .todo(task)
        let durationInterval = TimeInterval(task.estimatedDurationMinutes ?? 0) * 60

        let derivedStart: Date
        if let explicitStart = task.startDate {
            derivedStart = explicitStart
        } else if durationInterval > 0 {
            derivedStart = task.dueDate.addingTimeInterval(-durationInterval)
        } else {
            derivedStart = task.dueDate
        }

        var derivedEnd: Date
        if let explicitStart = task.startDate, durationInterval > 0 {
            derivedEnd = explicitStart.addingTimeInterval(durationInterval)
        } else if durationInterval > 0 {
            derivedEnd = task.dueDate
        } else {
            derivedEnd = task.dueDate
        }

        if derivedEnd < derivedStart {
            derivedEnd = derivedStart
        }

        startDate = derivedStart
        endDate = derivedEnd
        usesFallbackEnd = false
        actualStartTime = task.actualStartTime
        actualEndTime = task.actualEndTime
        actualDurationSeconds = task.actualDurationSeconds
    }

    init(assignment: SchoolAssignment, calendar: Calendar) {
        source = .assignment(assignment)
        startDate = assignment.dueDate
        endDate = assignment.displayEndDate(using: calendar) ?? assignment.dueDate
        usesFallbackEnd = assignment.usesFallbackEnd
        actualStartTime = assignment.actualStartTime
        actualEndTime = assignment.actualEndTime
        actualDurationSeconds = assignment.actualDurationSeconds
    }

    var id: String {
        switch source {
        case .todo(let task):
            return "todo-\(task.id.uuidString)"
        case .assignment(let assignment):
            return "assignment-\(assignment.id)"
        }
    }

    var title: String {
        switch source {
        case .todo(let task):
            return task.title
        case .assignment(let assignment):
            return assignment.title
        }
    }

    var subtitle: String? {
        switch source {
        case .todo(let task):
            return task.priority.displayName
        case .assignment(let assignment):
            return assignment.course ?? "Canvas assignment"
        }
    }

    var accentColor: Color {
        switch source {
        case .todo(let task):
            return task.priority.tintColor
        case .assignment:
            return .purple
        }
    }

    var iconName: String {
        switch source {
        case .todo(let task):
            switch task.priority {
            case .high:
                return "exclamationmark.circle.fill"
            case .medium:
                return "checkmark.circle.fill"
            case .low:
                return "circle.dashed"
            }
        case .assignment:
            return "book.closed.fill"
        }
    }

    var isCompleted: Bool {
        switch source {
        case .todo(let task):
            return task.isCompleted
        case .assignment(let assignment):
            return assignment.isCompleted
        }
    }

    var isTrackingActive: Bool {
        actualStartTime != nil && actualEndTime == nil
    }

    var hasTrackingCompleted: Bool {
        actualStartTime != nil && actualEndTime != nil
    }

    func elapsedSeconds(relativeTo now: Date = Date()) -> TimeInterval? {
        if let start = actualStartTime {
            let end = actualEndTime ?? now
            return max(0, end.timeIntervalSince(start))
        }
        if let stored = actualDurationSeconds {
            return stored
        }
        return nil
    }

    func isOverdue(relativeTo now: Date) -> Bool {
        guard !isCompleted else { return false }
        let deadline = endDate
        return deadline < now
    }

    func timelineDescription(using calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        if usesFallbackEnd && calendar.isDate(startDate, inSameDayAs: endDate) {
            let end = formatter.string(from: endDate)
            return "All day · Ends \(end)"
        }

        if calendar.isDate(startDate, inSameDayAs: endDate) {
            let start = formatter.string(from: startDate)
            let end = formatter.string(from: endDate)
            if start == end {
                return "\(start)"
            }
            return "\(start) - \(end)"
        } else {
            formatter.dateStyle = .short
            let start = formatter.string(from: startDate)
            let end = formatter.string(from: endDate)
            return "\(start) ~ \(end)"
        }
    }
}

#Preview {
    NavigationStack {
        CalendarHomeView()
            .environmentObject({
                let data = AppData()
                data.todos = [
                    TaskItem(title: "과제 제출", dueDate: Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date(), priority: .high),
                    TaskItem(title: "회의 준비", dueDate: Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date(), priority: .medium)
                ]
                return data
            }())
    }
}
