import SwiftUI
import Combine

struct CalendarHomeView: View {
    @EnvironmentObject private var data: AppData
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @State private var now: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var activeCountdownRoute: CountdownRoute? = nil

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(calendarCardColor)
                        .shadow(color: Color.black.opacity(calendarCardShadowOpacity), radius: 12, y: 4)
                    CalendarMonthView(onDayTap: { date in
                        selectedDate = date
                    }, eventsProvider: { date in
                        // Count todos and assignments for the given date
                        let todoCount = data.todos.filter { $0.hasDeadline && calendar.isDate($0.dueDate, inSameDayAs: date) }.count
                        let assignmentCount = data.assignments.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }.count
                        let total = todoCount + assignmentCount
                        return total > 0 ? total : nil
                    })
                    .padding()
                }
                .padding(.horizontal, 4)

                TodayCountdownSection(
                    items: todaysCountdowns,
                    now: now,
                    calendar: calendar,
                    locale: locale,
                    onToggleCompletion: handleCompletionToggle,
                    onStartTracking: handleStartTracking,
                    onPauseTracking: handlePauseTracking,
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
                        onPauseTracking: handlePauseTracking,
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
            if task.hasDeadline, calendar.isDate(task.dueDate, inSameDayAs: now) {
                items.append(CountdownItem(task: task))
            }
        }

        for assignment in data.assignments {
            if calendar.isDate(assignment.dueDate, inSameDayAs: now) {
                items.append(CountdownItem(assignment: assignment, calendar: calendar))
            }
        }

        for segment in data.taskSegments {
            if calendar.isDate(segment.dueDate, inSameDayAs: now) {
                items.append(CountdownItem(segment: segment, calendar: calendar, parentTitle: segmentParentTitle(for: segment)))
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
        let segmentItems = data.taskSegments
            .filter { $0.actualStartTime != nil && $0.actualEndTime == nil }
            .map { CountdownItem(segment: $0, calendar: calendar, parentTitle: segmentParentTitle(for: $0)) }
        return (todoItems + assignmentItems + segmentItems).sorted {
            let lhs = $0.actualStartTime ?? $0.startDate
            let rhs = $1.actualStartTime ?? $1.startDate
            return lhs < rhs
        }
    }
}

private extension CalendarHomeView {
    var calendarCardColor: Color {
        if colorScheme == .dark {
            return Color(.systemGray5)
        }
        return Color(.white)
    }

    var calendarCardShadowOpacity: Double {
        colorScheme == .dark ? 0 : 0.08
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
        case .segment(let segment, _):
            data.toggleSegmentCompletion(id: segment.id)
        }
    }

    func handleStartTracking(for item: CountdownItem) {
        switch item.source {
        case .todo(let task):
            data.startTaskProgress(id: task.id)
        case .assignment(let assignment):
            data.startAssignmentProgress(id: assignment.id)
        case .segment(let segment, _):
            data.startSegmentProgress(id: segment.id)
        }
    }

    func handlePauseTracking(for item: CountdownItem) {
        switch item.source {
        case .todo(let task):
            data.pauseTaskProgress(id: task.id)
        case .assignment(let assignment):
            data.pauseAssignmentProgress(id: assignment.id)
        case .segment(let segment, _):
            data.pauseSegmentProgress(id: segment.id)
        }
    }

    func handleFinishTracking(for item: CountdownItem) {
        switch item.source {
        case .todo(let task):
            data.completeTaskProgress(id: task.id)
        case .assignment(let assignment):
            data.completeAssignmentProgress(id: assignment.id)
        case .segment(let segment, _):
            data.completeSegmentProgress(id: segment.id)
        }
    }

    func segmentParentTitle(for segment: TaskSegment) -> String {
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
    let onPauseTracking: (CountdownItem) -> Void
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
                    description: Text("Add a todo, assignment, or segment and you'll see the countdown here.")
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
                            onPause: {
                                onPauseTracking(item)
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
    let onPauseTracking: (CountdownItem) -> Void
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
                        onPause: {
                            onPauseTracking(item)
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
    let onPause: () -> Void
    let onFinish: () -> Void
    let onSelect: ((CountdownRoute) -> Void)?
    @State private var showFinishConfirmation = false
    @Environment(\.colorScheme) private var colorScheme

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
                        .accessibilityLabel(isCompleted ? "Mark item incomplete" : "Mark item complete")
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
                        Text("Late")
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
                case .segment(let segment, _):
                    switch segment.parentType {
                    case .todo:
                        if let uuid = UUID(uuidString: segment.parentIdentifier) {
                            onSelect?(.todo(uuid))
                        }
                    case .assignment:
                        onSelect?(.assignment(segment.parentIdentifier))
                    }
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
                        Label("Start: \(actualStartText)", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let stopwatchText {
                        Label("\(item.hasTrackingCompleted ? "Total time" : "Elapsed"): \(stopwatchText)", systemImage: "stopwatch")
                            .font(.caption)
                            .foregroundStyle(item.isTimerRunning ? Color.accentColor : .secondary)
                    }
                    if let actualEndText {
                        Label("Finish: \(actualEndText)", systemImage: "flag.checkered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                if !item.hasTrackingStarted && !item.hasTrackingCompleted {
                    Button {
                        onStart()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }

                if item.hasTrackingStarted && !item.hasTrackingCompleted {
                    if item.isTimerRunning {
                        Button {
                            onPause()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            onStart()
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                    }

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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(rowBackground)
                .shadow(color: Color.black.opacity(rowShadowOpacity), radius: 4, x: 0, y: 2)
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
            return "Completed"
        }
        if isLate {
            return "Late"
        }

        if remainingInterval <= 0 {
            return "Past due"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.calendar = calendar
        formatter.maximumUnitCount = 2

        if let formatted = formatter.string(from: remainingInterval) {
            return "\(formatted) left"
        }
        return "Due soon"
    }

    private var dueTimeText: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let dueString = formatter.string(from: item.endDate)
        if item.usesFallbackEnd {
            return "\(dueString) (default 23:59)"
        }
        return dueString
    }

    private var rowBackground: Color {
        if colorScheme == .dark {
            return Color(.systemGray5)
        }
        return Color(.white)
    }

    private var rowShadowOpacity: Double {
        colorScheme == .dark ? 0 : 0.05
    }
}


private struct CountdownItem: Identifiable {
    enum Source {
        case todo(TaskItem)
        case assignment(SchoolAssignment)
        case segment(TaskSegment, parentTitle: String?)
    }

    let source: Source
    let startDate: Date
    let endDate: Date
    let usesFallbackEnd: Bool
    let actualStartTime: Date?
    let actualEndTime: Date?
    let actualDurationSeconds: Double?
    let activeTimerStart: Date?

    init(task: TaskItem) {
        source = .todo(task)
        let durationInterval = TimeInterval(task.estimatedDurationMinutes ?? 0) * 60
        let fallbackDue = task.startDate ?? Date()
        let baseDue = task.hasDeadline ? task.dueDate : fallbackDue

        let derivedStart: Date
        if let explicitStart = task.startDate {
            derivedStart = explicitStart
        } else if durationInterval > 0 {
            derivedStart = baseDue.addingTimeInterval(-durationInterval)
        } else {
            derivedStart = baseDue
        }

        var derivedEnd: Date
        if let explicitStart = task.startDate, durationInterval > 0 {
            derivedEnd = explicitStart.addingTimeInterval(durationInterval)
        } else if durationInterval > 0 {
            derivedEnd = baseDue
        } else {
            derivedEnd = baseDue
        }

        if derivedEnd < derivedStart {
            derivedEnd = derivedStart
        }

        startDate = derivedStart
        endDate = derivedEnd
        usesFallbackEnd = !task.hasDeadline
        actualStartTime = task.actualStartTime
        actualEndTime = task.actualEndTime
        actualDurationSeconds = task.actualDurationSeconds
        activeTimerStart = task.activeTimerStart
    }

    init(assignment: SchoolAssignment, calendar: Calendar) {
        source = .assignment(assignment)
        startDate = assignment.dueDate
        endDate = assignment.displayEndDate(using: calendar) ?? assignment.dueDate
        usesFallbackEnd = assignment.usesFallbackEnd
        actualStartTime = assignment.actualStartTime
        actualEndTime = assignment.actualEndTime
        actualDurationSeconds = assignment.actualDurationSeconds
        activeTimerStart = assignment.activeTimerStart
    }

    init(segment: TaskSegment, calendar: Calendar, parentTitle: String?) {
        source = .segment(segment, parentTitle: parentTitle)
        let durationInterval = TimeInterval(segment.estimatedDurationMinutes ?? 0) * 60
        let baseDue = segment.dueDate

        let derivedStart: Date
        if let explicitStart = segment.startDate {
            derivedStart = explicitStart
        } else if segment.hasDeadline && durationInterval > 0 {
            derivedStart = baseDue.addingTimeInterval(-durationInterval)
        } else {
            derivedStart = baseDue
        }

        var derivedEnd: Date
        if let explicitStart = segment.startDate, durationInterval > 0 {
            derivedEnd = explicitStart.addingTimeInterval(durationInterval)
        } else if segment.hasDeadline {
            derivedEnd = baseDue
        } else if durationInterval > 0 {
            derivedEnd = derivedStart.addingTimeInterval(durationInterval)
        } else {
            derivedEnd = baseDue
        }

        if derivedEnd < derivedStart {
            derivedEnd = derivedStart
        }

        startDate = derivedStart
        endDate = derivedEnd
        usesFallbackEnd = !segment.hasDeadline
        actualStartTime = segment.actualStartTime
        actualEndTime = segment.actualEndTime
        actualDurationSeconds = segment.actualDurationSeconds
        activeTimerStart = segment.activeTimerStart
    }

    var id: String {
        switch source {
        case .todo(let task):
            return "todo-\(task.id.uuidString)"
        case .assignment(let assignment):
            return "assignment-\(assignment.id)"
        case .segment(let segment, _):
            return "segment-\(segment.id.uuidString)"
        }
    }

    var title: String {
        switch source {
        case .todo(let task):
            return task.title
        case .assignment(let assignment):
            return assignment.title
        case .segment(let segment, _):
            return segment.title
        }
    }

    var subtitle: String? {
        switch source {
        case .todo(let task):
            return task.priority.displayName
        case .assignment(let assignment):
            return assignment.course ?? "Canvas assignment"
        case .segment(_, let parentTitle):
            return parentTitle
        }
    }

    var accentColor: Color {
        switch source {
        case .todo(let task):
            return task.priority.tintColor
        case .assignment:
            return .purple
        case .segment(let segment, _):
            return segment.priority.tintColor
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
        case .segment(let segment, _):
            switch segment.priority {
            case .high:
                return "flame.fill"
            case .medium:
                return "clock.fill"
            case .low:
                return "circle.dotted"
            }
        }
    }

    var isCompleted: Bool {
        switch source {
        case .todo(let task):
            return task.isCompleted
        case .assignment(let assignment):
            return assignment.isCompleted
        case .segment(let segment, _):
            return segment.isCompleted
        }
    }

    var hasTrackingStarted: Bool {
        actualStartTime != nil
    }

    var isTimerRunning: Bool {
        activeTimerStart != nil
    }

    var isTrackingActive: Bool {
        hasTrackingStarted && actualEndTime == nil
    }

    var hasTrackingCompleted: Bool {
        actualEndTime != nil
    }

    func elapsedSeconds(relativeTo now: Date = Date()) -> TimeInterval? {
        if let activeStart = activeTimerStart {
            let accumulated = actualDurationSeconds ?? 0
            return max(0, accumulated + now.timeIntervalSince(activeStart))
        }
        if let total = actualDurationSeconds {
            return max(0, total)
        }
        if let start = actualStartTime {
            let end = actualEndTime ?? now
            return max(0, end.timeIntervalSince(start))
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
                    TaskItem(title: "Submit assignment", dueDate: Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date(), priority: .high),
                    TaskItem(title: "Prepare meeting", dueDate: Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date(), priority: .medium)
                ]
                return data
            }())
    }
}
