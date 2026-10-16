import SwiftUI

/// Tradovate's web trader. Any CSV it downloads (Reports → Performance → Download)
/// is handed to the importer so trades land in an account without the Files app.
struct TradovateView: View {
    static let homeURL = URL(string: "https://trader.tradovate.com")!

    @EnvironmentObject private var store: AccountStore
    @StateObject private var model = WebViewModel()
    @State private var showingHelp = false

    var body: some View {
        BrowserScreen(fallbackTitle: "Tradovate", homeURL: Self.homeURL, model: model) {
            Button { showingHelp = true } label: { Image(systemName: "questionmark.circle") }
        }
        .onAppear {
            model.onDownload = { url, name in
                store.pendingImport = PendingImport(fileURL: url, sourceName: name)
            }
        }
        .sheet(isPresented: $showingHelp) {
            NavigationStack {
                List {
                    Section("Import your trades") {
                        Label("Log in with your Tradovate username and password (the one Lucid gave you).", systemImage: "1.circle")
                        Label("Open the menu and go to Reports (on a phone, turn it sideways or use the desktop layout if the menu is hidden).", systemImage: "2.circle")
                        Label("Choose the Performance tab, select your Lucid account and the date range.", systemImage: "3.circle")
                        Label("Tap Download / Export CSV. The app catches the file and asks which account to add it to.", systemImage: "4.circle")
                    }
                    Section {
                        Text("Importing the same report again is safe; trades already in the app are skipped.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("How to import")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { showingHelp = false } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
