import SwiftUI

@main
struct SimpleCalendarApp: App {
    @StateObject private var data = AppData()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(data)
        }
    }
}
