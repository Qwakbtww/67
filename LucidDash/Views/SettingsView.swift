import SwiftUI
import WebKit
import LucidCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: AccountStore
    @State private var confirmingSignOut = false
    @State private var signedOut = false

    private let timeZones = [
        "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
        "Europe/London", "Europe/Berlin", "Asia/Singapore", "Australia/Sydney", "UTC",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Portal address", text: $settings.portalURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Reset to default") { settings.portalURL = AppSettings.defaultPortalURL }
                } header: {
                    Text("Lucid Portal")
                } footer: {
                    Text("The page the Portal tab opens. Point it at your Lucid dashboard sign-in page.")
                }

                Section {
                    Picker("CSV time zone", selection: $settings.importTimeZoneID) {
                        ForEach(zoneOptions, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("Time zone your platform writes timestamps in. Trades are grouped into CME trading days (6 PM–5 PM New York time).")
                }

                Section("Data") {
                    Button("Add Demo Account") { store.addDemoAccount() }
                    Button("Sign Out of Portal", role: .destructive) { confirmingSignOut = true }
                }

                Section("About") {
                    LabeledContent("Accounts", value: "\(store.accounts.count)")
                    Text("LucidDash is an unofficial companion app and isn't affiliated with Lucid Trading. Rule tracking is calculated from the trades you import and may differ from Lucid's own numbers; Lucid's dashboard is always the source of truth.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Clear the portal's saved login and cookies?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    WKWebsiteDataStore.default().removeData(
                        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                        modifiedSince: .distantPast
                    ) { signedOut = true }
                }
            }
            .alert("Signed out of the portal", isPresented: $signedOut) {
                Button("OK") {}
            }
        }
    }

    private var zoneOptions: [String] {
        timeZones.contains(settings.importTimeZoneID) ? timeZones : [settings.importTimeZoneID] + timeZones
    }
}
