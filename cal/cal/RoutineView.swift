import SwiftUI

struct RoutineView: View {
    @EnvironmentObject private var data: AppData
    @State private var isPresentingAdd = false
    @State private var draftTitle: String = ""
    @State private var draftStart: Date = Date()
    @State private var draftEnd: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var draftWeekdays: Set<Int> = Set(1...7)
    @State private var draftIcon: String = "repeat"
    @State private var draftColorHex: String = RoutineItem.defaultColorHex
    @State private var activeRoutine: RoutineItem?
    @State private var safeAreaInsets: EdgeInsets = .init()
    @State private var didScrollToCurrentTime = false
    @State private var viewMode: RoutineViewMode = .sevenDays
    @State private var anchorDate: Date = Date()
    @State private var previousMultiDayMode: RoutineViewMode = .sevenDays

    private let iconChoices: [String] = [
        "repeat", "sun.max", "moon.fill", "flame.fill", "leaf.fill", "book.fill", "star.fill", "bell.fill"
    ]

    private let colorOptions = RoutineColorPalette.options

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                SafeAreaInsetsReader()
                    .onPreferenceChange(SafeAreaInsetsKey.self) { safeAreaInsets = $0 }
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        let columns = viewMode.columns(for: anchorDate)
                        let swipeGesture = DragGesture(minimumDistance: 24, coordinateSpace: .local)
                            .onEnded { value in
                                guard viewMode == .oneDay else { return }
                                let horizontal = value.translation.width
                                let vertical = value.translation.height
                                guard abs(horizontal) > abs(vertical), abs(horizontal) > 40 else { return }
                                let direction = horizontal < 0 ? 1 : -1
                                if let newDate = Calendar.current.date(byAdding: .day, value: direction, to: anchorDate) {
                                    anchorDate = newDate
                                    didScrollToCurrentTime = false
                                }
                            }
                        let grid = WeeklyScheduleGrid(
                            routines: data.routines,
                            columns: columns,
                            currentDate: timeline.date,
                            focusedDate: anchorDate,
                            shouldScrollToNow: !didScrollToCurrentTime,
                            onDidScrollToNow: { didScrollToCurrentTime = true },
                            accessoryView: topControls,
                            onTapDay: { column in
                                if viewMode != .oneDay {
                                    previousMultiDayMode = viewMode
                                }
                                anchorDate = column.date
                                viewMode = .oneDay
                                didScrollToCurrentTime = false
                            }
                        ) { routine in
                            activeRoutine = routine
                        }

                        if viewMode == .oneDay {
                            grid.gesture(swipeGesture)
                        } else {
                            grid
                        }
                    }
                    .padding(.top, 0)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 0)
                    .overlay {
                        if data.routines.isEmpty {
                            ContentUnavailableView(
                                "No routines yet",
                                systemImage: "repeat",
                                description: Text("Add routines to run every day.")
                            )
                            .padding(.horizontal, 24)
                        }
                    }
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isPresentingAdd) {
            routineForm(isEditing: false)
        }
        .sheet(item: $activeRoutine) { routine in
            routineForm(isEditing: true, existing: routine)
        }
        .onChange(of: viewMode) { mode in
            didScrollToCurrentTime = false
            if mode != .oneDay {
                previousMultiDayMode = mode
            }
        }
    }

    private var topControls: AnyView {
        AnyView(
            HStack(spacing: 12) {
                if viewMode == .oneDay {
                    exitSingleDayButton
                }
                viewModeControl
                addRoutineButton
            }
            .padding(.top,0)
            .padding(.trailing, 12)
        )
    }

    private var viewModeControl: some View {
        Menu {
            ForEach(RoutineViewMode.allCases) { mode in
                Button {
                    if mode == .oneDay && viewMode != .oneDay {
                        previousMultiDayMode = viewMode
                    }
                    if mode != .oneDay {
                        previousMultiDayMode = mode
                        anchorDate = Date()
                    }
                    viewMode = mode
                } label: {
                    if viewMode == mode {
                        Label(mode.menuTitle, systemImage: "checkmark")
                    } else {
                        Text(mode.menuTitle)
                    }
                }
            }
        } label: {
            Label(viewMode.shortTitle, systemImage: "calendar")
                .font(.system(size: 15, weight: .semibold))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Change routine view")
    }

    private var exitSingleDayButton: some View {
        Button {
            viewMode = previousMultiDayMode
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6))
                .clipShape(Circle())
        }
        .accessibilityLabel("Back to multi-day view")
    }

    private var addRoutineButton: some View {
        Button {
            prepareDraftForCreation()
            isPresentingAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .accessibilityLabel("Add routine")
    }

    private func prepareDraftForCreation() {
        draftTitle = ""
        draftStart = Date()
        draftEnd = Calendar.current.date(byAdding: .hour, value: 1, to: draftStart) ?? Date()
        draftWeekdays = Set(1...7)
        draftIcon = "repeat"
        draftColorHex = RoutineItem.defaultColorHex
    }

    @ViewBuilder
    private func routineForm(isEditing: Bool, existing: RoutineItem? = nil) -> some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Title", text: $draftTitle)
                }

                Section("Start / End") {
                    DatePicker("Start", selection: $draftStart, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $draftEnd, displayedComponents: .hourAndMinute)
                }

                Section("Repeat") {
                    let columns = Array(repeating: GridItem(.flexible()), count: 7)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Weekday.allCases) { day in
                            Button {
                                if draftWeekdays.contains(day.rawValue) {
                                    draftWeekdays.remove(day.rawValue)
                                } else {
                                    draftWeekdays.insert(day.rawValue)
                                }
                            } label: {
                                Text(day.localizedShortName)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                                    .background(draftWeekdays.contains(day.rawValue) ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Color") {
                    let columns = Array(repeating: GridItem(.flexible()), count: 4)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(colorOptions) { option in
                            Button {
                                draftColorHex = option.hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: option.hex))
                                        .frame(width: 44, height: 44)

                                    if draftColorHex == option.hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(Color.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(draftColorHex == option.hex ? 0.0 : 0.1), lineWidth: 1)
                                        .frame(width: 44, height: 44)
                                )
                                .accessibilityElement()
                                .accessibilityLabel(option.accessibilityName)
                                .accessibilityAddTraits(draftColorHex == option.hex ? .isSelected : [])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Icon") {
                    let columns = Array(repeating: GridItem(.flexible()), count: 4)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(iconChoices, id: \.self) { icon in
                            Button {
                                draftIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .padding(8)
                                    .background(draftIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if isEditing, let existing {
                    Section {
                        Button(role: .destructive) {
                            data.removeRoutine(id: existing.id)
                            activeRoutine = nil
                        } label: {
                            Text("Delete Routine")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Routine" : "Add Routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresentingAdd = false
                        activeRoutine = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let startComps = Calendar.current.dateComponents([.hour, .minute], from: draftStart)
                        let endComps = Calendar.current.dateComponents([.hour, .minute], from: draftEnd)

                        if isEditing, let existing = existing {
                            var updated = existing
                            updated.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            updated.startTime = startComps
                            updated.endTime = endComps
                            updated.weekdays = draftWeekdays
                            updated.iconName = draftIcon
                            updated.colorHex = draftColorHex
                            data.update(routine: updated)
                            activeRoutine = nil
                        } else {
                            let item = RoutineItem(
                                title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                startTime: startComps,
                                endTime: endComps,
                                isEnabled: true,
                                weekdays: draftWeekdays,
                                iconName: draftIcon,
                                colorHex: draftColorHex
                            )
                            data.add(routine: item)
                            isPresentingAdd = false
                        }
                    }
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let existing = existing {
                    draftTitle = existing.title
                    if let start = Calendar.current.date(from: existing.startTime) {
                        draftStart = start
                    }
                    if let end = Calendar.current.date(from: existing.endTime) {
                        draftEnd = end
                    }
                    draftWeekdays = existing.weekdays
                    draftIcon = existing.iconName
                    draftColorHex = existing.colorHex
                } else {
                    prepareDraftForCreation()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private enum RoutineViewMode: String, CaseIterable, Identifiable {
    case oneDay
    case threeDays
    case sevenDays

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .oneDay:
            return "1 Day"
        case .threeDays:
            return "3 Days"
        case .sevenDays:
            return "7 Days"
        }
    }

    var menuTitle: String {
        switch self {
        case .oneDay:
            return "1 Day · Today"
        case .threeDays:
            return "3 Days · Yesterday, Today, Tomorrow"
        case .sevenDays:
            return "7 Days · Sun - Sat"
        }
    }

    func columns(for anchorDate: Date, calendar: Calendar = .current) -> [DayColumn] {
        let normalized = calendar.startOfDay(for: anchorDate)
        let weekdayNumber = calendar.component(.weekday, from: normalized)
        guard let anchorWeekday = Weekday(rawValue: weekdayNumber) else {
            return Weekday.allCases.enumerated().compactMap { offset, weekday in
                guard let date = calendar.date(byAdding: .day, value: offset, to: normalized) else { return nil }
                return DayColumn(index: offset, date: date, weekday: weekday, display: weekday.localizedTinyName)
            }
        }

        switch self {
        case .oneDay:
            return [DayColumn(index: 0, date: normalized, weekday: anchorWeekday, display: anchorWeekday.localizedTinyName)]
        case .threeDays:
            let previousDate = calendar.date(byAdding: .day, value: -1, to: normalized) ?? normalized
            let nextDate = calendar.date(byAdding: .day, value: 1, to: normalized) ?? normalized
            let orderedDates = [previousDate, normalized, nextDate]
            return orderedDates.enumerated().compactMap { idx, date in
                let weekdayNumber = calendar.component(.weekday, from: date)
                guard let weekday = Weekday(rawValue: weekdayNumber) else { return nil }
                return DayColumn(index: idx, date: date, weekday: weekday, display: weekday.localizedTinyName)
            }
        case .sevenDays:
            let offsetToSunday = (weekdayNumber - 1)
            let sunday = calendar.date(byAdding: .day, value: -offsetToSunday, to: normalized) ?? normalized
            return (0..<7).compactMap { idx in
                guard let date = calendar.date(byAdding: .day, value: idx, to: sunday) else { return nil }
                let weekdayNumber = calendar.component(.weekday, from: date)
                guard let weekday = Weekday(rawValue: weekdayNumber) else { return nil }
                return DayColumn(index: idx, date: date, weekday: weekday, display: weekday.localizedTinyName)
            }
        }
    }
}

private struct DayColumn: Identifiable {
    let index: Int
    let date: Date
    let weekday: Weekday
    let display: String

    var id: Int { index }
}

private extension Weekday {
    var previous: Weekday {
        Weekday(rawValue: rawValue == 1 ? 7 : rawValue - 1) ?? self
    }

    var next: Weekday {
        Weekday(rawValue: rawValue == 7 ? 1 : rawValue + 1) ?? self
    }
}

private struct WeeklyScheduleGrid: View {
    let routines: [RoutineItem]
    let columns: [DayColumn]
    let currentDate: Date
    let focusedDate: Date
    let shouldScrollToNow: Bool
    var onDidScrollToNow: () -> Void
    var accessoryView: AnyView? = nil
    var onTapDay: (DayColumn) -> Void
    var onTapRoutine: (RoutineItem) -> Void

    static let hourLabelWidth: CGFloat = 34
    private let minColumnWidth: CGFloat = 0
    private let cellHeight: CGFloat = 60
    private let currentTimeAnchorID = "currentTimeAnchor"

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let columnCount = max(columns.count, 1)
            let columnWidth = max(minColumnWidth, (totalWidth - Self.hourLabelWidth) / CGFloat(columnCount))

            VStack(alignment: .leading, spacing: 0) {
                if let accessoryView {
                    HStack {
                        Spacer()
                        accessoryView
                    }
                    .padding(.bottom, 8)
                }

                headerRow(columnsWidth: columnWidth)
                    .padding(.bottom, 8)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            hourGrid(columnsWidth: columnWidth)

                            ForEach(routines) { routine in
                                if routine.isEnabled {
                                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                                        let blocks = blocks(for: routine, column: column, columnIndex: index, columnWidth: columnWidth)
                                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                            Button {
                                                onTapRoutine(routine)
                                            } label: {
                                                routineBlock(for: routine, block: block)
                                            }
                                            .buttonStyle(.plain)
                                            .frame(width: block.width, height: block.height)
                                            .position(x: block.midX, y: block.midY)
                                        }
                                    }
                                }
                            }

                            GeometryReader { markerGeo in
                                let height = markerGeo.size.height
                                if let y = currentTimeOffset(for: currentDate) {
                                    let clampedY = min(max(y, 0), height)
                                    Group {
                                        currentTimeLine(width: markerGeo.size.width)
                                            .position(x: markerGeo.size.width / 2, y: clampedY)
                                        Color.clear
                                            .frame(height: 1)
                                            .position(x: markerGeo.size.width / 2, y: clampedY)
                                            .id(currentTimeAnchorID)
                                    }
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .frame(height: cellHeight * 24)
                        .padding(.bottom, 32)
                    }
                    .onAppear {
                        scrollToCurrentTimeIfNeeded(using: proxy)
                    }
                    .onChange(of: shouldScrollToNow) { _ in
                        scrollToCurrentTimeIfNeeded(using: proxy)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: cellHeight * 12)
    }

    private func headerRow(columnsWidth: CGFloat) -> some View {
        let calendar = Calendar.current
        return HStack(spacing: 0) {
            Text("")
                .frame(width: Self.hourLabelWidth)
            ForEach(columns) { column in
                let isToday = calendar.isDate(column.date, inSameDayAs: Date())
                let isFocused = calendar.isDate(column.date, inSameDayAs: focusedDate) && columns.count == 1

                Button {
                    onTapDay(column)
                } label: {
                    Text(column.display.uppercased())
                        .font(.callout.weight(.semibold))
                        .frame(width: columnsWidth)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isFocused ? Color.accentColor.opacity(0.4) : (isToday ? Color.accentColor.opacity(0.2) : Color.clear))
                        )
                        .foregroundStyle(isFocused ? Color.white : Color.primary)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func hourGrid(columnsWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 0) {
                    Text(hourLabel(for: hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: Self.hourLabelWidth, height: cellHeight, alignment: .leading)

                    ForEach(0..<columns.count, id: \.self) { columnIndex in
                        Rectangle()
                            .fill(columnIndex % 2 == 0 ? Color(.secondarySystemBackground).opacity(0.35) : Color(.systemBackground).opacity(0.2))
                            .frame(width: columnsWidth, height: cellHeight)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                }
            }

            // Bottom border for 24:00 line
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
                .padding(.leading, Self.hourLabelWidth)
        }
    }

    private func hourLabel(for hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func blocks(for routine: RoutineItem, column: DayColumn, columnIndex: Int, columnWidth: CGFloat) -> [BlockLayout] {
        let x = Self.hourLabelWidth + CGFloat(columnIndex) * columnWidth
        let width = columnWidth

        let startMinutes = minutes(from: routine.startTime)
        let endMinutes = minutes(from: routine.endTime)
        let wrapsPastMidnight = endMinutes <= startMinutes
        let adjustedEnd = wrapsPastMidnight ? endMinutes + 24 * 60 : endMinutes

        var result: [BlockLayout] = []

        func appendBlock(start: Int, end: Int) {
            let clampedStart = min(max(start, 0), 24 * 60)
            let clampedEnd = min(max(end, 0), 24 * 60)
            guard clampedEnd > clampedStart else { return }

            let yStart = CGFloat(clampedStart) / 60.0 * cellHeight
            let height = max(CGFloat(clampedEnd - clampedStart) / 60.0 * cellHeight, 6)
            let midX = x + width / 2
            let midY = yStart + height / 2
            result.append(BlockLayout(width: width, height: height, midX: midX, midY: midY))
        }

        if routine.weekdays.contains(column.weekday.rawValue) {
            if wrapsPastMidnight {
                appendBlock(start: startMinutes, end: 24 * 60)
            } else {
                appendBlock(start: startMinutes, end: min(endMinutes, 24 * 60))
            }
        }

        let previousDay = column.weekday.previous.rawValue
        if routine.weekdays.contains(previousDay) && wrapsPastMidnight {
            let spillover = adjustedEnd - 24 * 60
            if spillover > 0 {
                appendBlock(start: 0, end: min(spillover, 24 * 60))
            }
        }

        return result
    }

    private func currentTimeOffset(for date: Date) -> CGFloat? {
        let cal = Calendar.current
        let components = cal.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        let totalMinutes = hour * 60 + minute
        guard totalMinutes >= 0 && totalMinutes <= 24 * 60 else { return nil }
        return CGFloat(totalMinutes) / 60.0 * cellHeight
    }

    private func currentTimeLine(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.red.opacity(0.85))
                .frame(width: width, height: 2)
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .offset(x: Self.hourLabelWidth - 5, y: 0)
        }
    }

    private func scrollToCurrentTimeIfNeeded(using proxy: ScrollViewProxy) {
        guard shouldScrollToNow else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(currentTimeAnchorID, anchor: .center)
            }
            onDidScrollToNow()
        }
    }

    private func minutes(from components: DateComponents) -> Int {
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }

    private func routineBlock(for routine: RoutineItem, block: BlockLayout) -> some View {
        let baseColor = routine.color
        let titleColor = Color.white
        let detailColor = Color.white.opacity(0.85)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: routine.iconName)
                    .font(.caption)
                    .foregroundStyle(titleColor)
                Text(routine.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(titleColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(routine.timeRangeString())
                .font(.caption2)
                .foregroundStyle(detailColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: max(block.width - 8, 0), maxHeight: max(block.height - 6, 24), alignment: .topLeading)
        .background(baseColor.opacity(routine.isEnabled ? 0.95 : 0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
    }

    private struct BlockLayout {
        let width: CGFloat
        let height: CGFloat
        let midX: CGFloat
        let midY: CGFloat
    }
}

private struct SafeAreaInsetsKey: PreferenceKey {
    static var defaultValue: EdgeInsets = .init()

    static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) {
        let next = nextValue()
        value = EdgeInsets(
            top: max(value.top, next.top),
            leading: max(value.leading, next.leading),
            bottom: max(value.bottom, next.bottom),
            trailing: max(value.trailing, next.trailing)
        )
    }
}

private struct SafeAreaInsetsReader: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: SafeAreaInsetsKey.self, value: geo.safeAreaInsets)
        }
    }
}

private struct RoutineColorPalette {
    static let options: [RoutineColorOption] = [
        RoutineColorOption(name: "Blue", hex: "#4F8DFF"),
        RoutineColorOption(name: "Indigo", hex: "#7A61FF"),
        RoutineColorOption(name: "Teal", hex: "#2CC8A3"),
        RoutineColorOption(name: "Green", hex: "#6AC868"),
        RoutineColorOption(name: "Amber", hex: "#F7B731"),
        RoutineColorOption(name: "Coral", hex: "#FF6B6B"),
        RoutineColorOption(name: "Pink", hex: "#FF8E9E"),
        RoutineColorOption(name: "Slate", hex: "#6E7A8A")
    ]
}

private struct RoutineColorOption: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }

    var accessibilityName: String {
        name
    }
}

#Preview {
    RoutineView()
        .environmentObject(AppData())
}
