import SwiftUI

@main
struct LucidDashApp: App {
    @StateObject private var store = AccountStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .tint(.accentColor)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            AccountsListView()
                .tabItem { Label("Accounts", systemImage: "chart.line.uptrend.xyaxis") }
            PortalView()
                .tabItem { Label("Lucid Portal", systemImage: "globe") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
