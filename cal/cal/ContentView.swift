import SwiftUI

struct ContentView: View {
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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppData())
    }
}
