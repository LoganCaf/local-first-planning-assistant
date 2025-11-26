import SwiftUI

struct ContentView: View {
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    private var preferredScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearanceModeRaw) ?? .system {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var body: some View {
        TabView {
            NavigationStack {
                CalendarHomeView()
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }

            CombinedTasksView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }

            RoutineView()
                .tabItem {
                    Label("ROUTINES", systemImage: "repeat")
                }

            NavigationStack {
                ScheduleChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .preferredColorScheme(preferredScheme)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppData())
    }
}
