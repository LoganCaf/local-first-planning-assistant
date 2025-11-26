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

struct SettingsView: View {
    @AppStorage("calendarIndicatorStyle") private var indicatorStyle: String = "centered"
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
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
            }
            .navigationTitle("Settings")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
