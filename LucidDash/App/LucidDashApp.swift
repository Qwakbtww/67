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
    @EnvironmentObject private var store: AccountStore

    var body: some View {
        TabView {
            AccountsListView()
                .tabItem { Label("Accounts", systemImage: "chart.line.uptrend.xyaxis") }
            PortalView()
                .tabItem { Label("Lucid", systemImage: "globe") }
            TradovateView()
                .tabItem { Label("Tradovate", systemImage: "arrow.down.doc") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(item: $store.pendingImport) { pending in
            ImportTargetView(pending: pending)
        }
        // CSVs shared to the app ("Open in LucidDash" / Share → LucidDash).
        .onOpenURL { url in
            store.pendingImport = PendingImport(fileURL: url, sourceName: url.lastPathComponent)
        }
    }
}
