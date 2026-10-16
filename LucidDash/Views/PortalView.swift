import SwiftUI
import LucidCore

/// Lucid's own web dashboard. Login cookies persist, and "Read numbers" pulls the
/// balance / drawdown figures off the page so they can be saved to an account.
struct PortalView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = WebViewModel()
    @State private var figures: [PageFigure]?
    @State private var nothingFound = false

    var body: some View {
        BrowserScreen(fallbackTitle: "Lucid", homeURL: settings.resolvedPortalURL, model: model) {
            Button {
                model.pageText { text in
                    let found = PageFigureParser.parse(text ?? "")
                    if found.isEmpty { nothingFound = true } else { figures = found }
                }
            } label: {
                Label("Read numbers", systemImage: "text.viewfinder")
            }
        }
        .sheet(isPresented: Binding(isPresenting: $figures)) {
            CaptureFiguresView(figures: figures ?? [])
        }
        .alert("No numbers found", isPresented: $nothingFound) {
            Button("OK") {}
        } message: {
            Text("Open the page that shows your account balance and drawdown, then tap Read numbers again.")
        }
    }
}

/// Lets the user assign figures read from Lucid's page to one of their accounts.
struct CaptureFiguresView: View {
    let figures: [PageFigure]

    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss

    @State private var accountID: UUID?
    @State private var balanceIndex: Int?
    @State private var floorIndex: Int?
    @State private var remainingIndex: Int?

    var body: some View {
        NavigationStack {
            Form {
                if store.accounts.isEmpty {
                    Section {
                        Text("Add an account on the Accounts tab first, then come back and read the numbers again.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Save to account") {
                        Picker("Account", selection: $accountID) {
                            ForEach(store.accounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                    }
                    Section {
                        figurePicker("Balance", selection: $balanceIndex)
                        figurePicker("Drawdown floor", selection: $floorIndex)
                        if floorIndex == nil {
                            figurePicker("…or drawdown left", selection: $remainingIndex)
                        }
                    } header: {
                        Text("Lucid's numbers")
                    } footer: {
                        Text("The floor is the balance your account must stay above. If the page only shows how much drawdown is left, pick that and the floor is worked out from the balance.")
                    }
                    if let preview {
                        Section("Will save") {
                            if let b = preview.balance { LabeledContent("Balance", value: b.currency) }
                            if let f = preview.drawdownFloor { LabeledContent("Floor", value: f.currency) }
                            if let buffer = preview.buffer { LabeledContent("Room to floor", value: buffer.currency) }
                        }
                    }
                }
                Section("Found on the page") {
                    ForEach(figures) { figure in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(figure.label)
                                if let hint = figure.accountHint {
                                    Text(hint).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(figure.amount.currency).monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Lucid numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let accountID, let preview { store.setReported(preview, for: accountID) }
                        dismiss()
                    }
                    .disabled(accountID == nil || preview == nil)
                }
            }
            .onAppear(perform: preselect)
            .onChange(of: accountID) { preselectFigures() }
        }
    }

    private var preview: ReportedFigures? {
        let balance = balanceIndex.map { figures[$0].amount }
        var floor = floorIndex.map { figures[$0].amount }
        if floor == nil, let balance, let remaining = remainingIndex.map({ figures[$0].amount }) {
            floor = balance - remaining
        }
        guard balance != nil || floor != nil else { return nil }
        return ReportedFigures(balance: balance, drawdownFloor: floor)
    }

    private func figurePicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(Int?.none)
            ForEach(figures) { figure in
                Text("\(figure.label) · \(figure.amount.currency)").tag(Optional(figure.index))
            }
        }
    }

    private func preselect() {
        // Prefer the account whose number appears on the page.
        let hints = Set(figures.compactMap(\.accountHint))
        accountID = store.accounts.first { !$0.accountNumber.isEmpty && hints.contains($0.accountNumber) }?.id
            ?? store.accounts.first?.id
        preselectFigures()
    }

    private func preselectFigures() {
        let number = store.accounts.first { $0.id == accountID }?.accountNumber ?? ""
        let scoped = figures.filter { !number.isEmpty && $0.accountHint == number }
        let pool = scoped.isEmpty ? figures : scoped
        balanceIndex = pool.first { $0.kind == .balance }?.index
        floorIndex = pool.first { $0.kind == .drawdownFloor }?.index
        remainingIndex = floorIndex == nil ? pool.first { $0.kind == .drawdownRemaining }?.index : nil
    }
}
