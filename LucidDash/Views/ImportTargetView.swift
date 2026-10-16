import SwiftUI
import LucidCore

/// A CSV waiting to be imported, from Tradovate's in-app page or "Open in LucidDash".
struct PendingImport: Identifiable {
    let id = UUID()
    let fileURL: URL
    let sourceName: String
}

/// Asks which account a downloaded/shared CSV belongs to, then imports it.
struct ImportTargetView: View {
    let pending: PendingImport

    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var result: String?
    @State private var showingNewAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(pending.sourceName.isEmpty ? "Trade report" : pending.sourceName, systemImage: "doc.text")
                } footer: {
                    Text("Trades already in the account are skipped.")
                }
                Section("Add trades to") {
                    ForEach(store.accounts) { account in
                        Button {
                            importInto(account.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(account.name)
                                    if !account.accountNumber.isEmpty {
                                        Text(account.accountNumber).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(account.trades.count) trades").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        showingNewAccount = true
                    } label: {
                        Label("New account…", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Import trades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showingNewAccount) { AccountEditorView(account: nil) }
            .alert("Import", isPresented: Binding(isPresenting: $result)) {
                Button("OK") { dismiss() }
            } message: {
                Text(result ?? "")
            }
        }
    }

    private func importInto(_ accountID: UUID) {
        do {
            let r = try store.importCSV(from: pending.fileURL, into: accountID, timeZone: settings.importTimeZone)
            var parts = ["Added \(r.added) trade\(r.added == 1 ? "" : "s")."]
            if r.duplicates > 0 { parts.append("\(r.duplicates) already imported.") }
            if r.skipped > 0 { parts.append("\(r.skipped) row\(r.skipped == 1 ? "" : "s") couldn't be read.") }
            result = parts.joined(separator: " ")
        } catch {
            result = error.localizedDescription
        }
    }
}
