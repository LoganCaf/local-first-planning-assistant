import SwiftUI

struct RoutineView: View {
    @EnvironmentObject private var data: AppData
    @State private var isPresentingAdd = false
    @State private var draftTitle: String = ""
    @State private var draftStart: Date = Date()
    @State private var draftEnd: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var draftWeekdays: Set<Int> = Set(1...7)
    @State private var draftIcon: String = "repeat"
    @State private var activeRoutine: RoutineItem?

    private let iconChoices: [String] = [
        "repeat", "sun.max", "moon.fill", "flame.fill", "leaf.fill", "book.fill", "star.fill", "bell.fill"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if data.routines.isEmpty {
                    ContentUnavailableView("No routines yet", systemImage: "repeat", description: Text("Add routines to run every day."))
                } else {
                    List {
                        ForEach(data.routines) { routine in
                            HStack {
                                Image(systemName: routine.iconName)
                                    .font(.title2)
                                    .foregroundStyle(routine.isEnabled ? Color.accentColor : Color.secondary)
                                    .frame(width: 36, height: 36)

                                VStack(alignment: .leading) {
                                    Text(routine.title)
                                        .font(.headline)
                                    Text(routine.timeRangeString())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(routine.weekdayDisplayString())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeRoutine = routine
                            }
                        }
                        .onDelete(perform: data.removeRoutines)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("ROUTINES")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        draftTitle = ""
                        draftStart = Date()
                        draftEnd = Calendar.current.date(byAdding: .hour, value: 1, to: draftStart) ?? Date()
                        draftWeekdays = Set(1...7)
                        isPresentingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            routineForm(isEditing: false)
        }
        .sheet(item: $activeRoutine) { routine in
            routineForm(isEditing: true, existing: routine)
        }
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
                    VStack(spacing: 8) {
                        let cols = Array(repeating: GridItem(.flexible()), count: 7)
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(Weekday.allCases) { day in
                                Button(action: {
                                    if draftWeekdays.contains(day.rawValue) {
                                        draftWeekdays.remove(day.rawValue)
                                    } else {
                                        draftWeekdays.insert(day.rawValue)
                                    }
                                }) {
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
                }
                Section("Icon") {
                    let cols = Array(repeating: GridItem(.flexible()), count: 4)
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(iconChoices, id: \ .self) { icon in
                            Button(action: { draftIcon = icon }) {
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
                            data.update(routine: updated)
                            activeRoutine = nil
                        } else {
                            let item = RoutineItem(title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines), startTime: startComps, endTime: endComps, isEnabled: true, weekdays: draftWeekdays, iconName: draftIcon)
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
                    if let s = Calendar.current.date(from: existing.startTime) {
                        draftStart = s
                    }
                    if let e = Calendar.current.date(from: existing.endTime) {
                        draftEnd = e
                    }
                    draftWeekdays = existing.weekdays
                    draftIcon = existing.iconName
                } else {
                    draftTitle = ""
                    draftStart = Date()
                    draftEnd = Calendar.current.date(byAdding: .hour, value: 1, to: draftStart) ?? Date()
                    draftWeekdays = Set(1...7)
                    draftIcon = "repeat"
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    RoutineView()
        .environmentObject(AppData())
}
