import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

enum ReminderUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours

    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject private var appData: AppData
    @AppStorage("calendarIndicatorStyle") private var indicatorStyle: String = "centered"
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("assignmentReminderMinutes") private var reminderMinutes: Int = 60
    @AppStorage("assignmentReminderUnit") private var reminderUnitRaw: String = ReminderUnit.minutes.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var reminderUnit: ReminderUnit {
        ReminderUnit(rawValue: reminderUnitRaw) ?? .minutes
    }

    private var reminderValueBinding: Binding<Int> {
        Binding(
            get: {
                switch reminderUnit {
                case .minutes:
                    return reminderMinutes
                case .hours:
                    return max(1, reminderMinutes / 60)
                }
            },
            set: { newValue in
                let safeValue = max(1, newValue)
                switch reminderUnit {
                case .minutes:
                    reminderMinutes = min(720, safeValue)
                case .hours:
                    reminderMinutes = min(720, safeValue * 60)
                }
                appData.refreshAssignmentReminders()
            }
        )
    }

    private var reminderRange: ClosedRange<Int> {
        switch reminderUnit {
        case .minutes:
            return 5...720
        case .hours:
            return 1...12
        }
    }

    private var reminderStep: Int {
        reminderUnit == .minutes ? 5 : 1
    }

    private var reminderLabel: String {
        switch reminderUnit {
        case .minutes:
            return "Notify me \(reminderValueBinding.wrappedValue) minutes before due"
        case .hours:
            let hours = reminderValueBinding.wrappedValue
            let unit = hours == 1 ? "hour" : "hours"
            return "Notify me \(hours) \(unit) before due"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Color scheme", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Choose between light, dark, or follow the system setting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Calendar indicators")) {
                    Picker("Indicator style", selection: $indicatorStyle) {
                        Text("Centered (circle)").tag("centered")
                        Text("Centered (shapes)").tag("centeredShape")
                        Text("Bottom dot").tag("bottom")
                    }
                    .pickerStyle(.inline)

                    Text("Choose how calendar event indicators are shown on each day cell.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Assignment reminders")) {
                    Picker("Units", selection: $reminderUnitRaw) {
                        Text("Minutes").tag(ReminderUnit.minutes.rawValue)
                        Text("Hours").tag(ReminderUnit.hours.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: reminderUnitRaw) { _ in
                        // Normalize minutes when switching units and reschedule
                        switch reminderUnit {
                        case .minutes:
                            reminderMinutes = max(5, reminderMinutes)
                        case .hours:
                            reminderMinutes = max(60, ((reminderMinutes + 59) / 60) * 60)
                        }
                        appData.refreshAssignmentReminders()
                    }

                    Stepper(value: reminderValueBinding, in: reminderRange, step: reminderStep) {
                        Text(reminderLabel)
                    }
                    Text("Choose how long before an assignment is due you’d like a reminder (5–720 minutes or 1–12 hours).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppData())
    }
}
