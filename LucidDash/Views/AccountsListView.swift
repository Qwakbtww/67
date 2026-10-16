import SwiftUI
import LucidCore

struct AccountsListView: View {
    @EnvironmentObject private var store: AccountStore
    @State private var showingNewAccount = false

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Lucid Accounts")
            .navigationDestination(for: UUID.self) { id in
                AccountDashboardView(accountID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
                if !store.accounts.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .sheet(isPresented: $showingNewAccount) {
                AccountEditorView(account: nil)
            }
            .alert("Something went wrong", isPresented: Binding(isPresenting: $store.lastError)) {
                Button("OK") {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    private var list: some View {
        List {
            Section {
                PortfolioSummary(accounts: store.accounts)
            }
            Section("Accounts") {
                ForEach(store.accounts) { account in
                    NavigationLink(value: account.id) {
                        AccountRow(account: account)
                    }
                }
                .onDelete { store.delete(at: $0) }
                .onMove { store.move(from: $0, to: $1) }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: "chart.bar.doc.horizontal")
        } description: {
            Text("Add your Lucid account and import a trade export from your platform to see balance, drawdown and rule progress.")
        } actions: {
            Button("Add Account") { showingNewAccount = true }
                .buttonStyle(.borderedProminent)
            Button("Load Demo Account") { store.addDemoAccount() }
        }
    }
}

private struct PortfolioSummary: View {
    let accounts: [TradingAccount]

    var body: some View {
        let snapshots = accounts.map { RulesEngine.snapshot(for: $0) }
        let today = snapshots.reduce(0) { $0 + $1.todayPnL }
        let total = snapshots.reduce(0) { $0 + $1.profit }
        let atRisk = snapshots.filter { $0.status == .warning || $0.status == .breached }.count

        HStack {
            stat("Today", today.signedCurrency, color: today.pnlColor)
            Divider()
            stat("Total P&L", total.signedCurrency, color: total.pnlColor)
            Divider()
            stat("At risk", "\(atRisk)", color: atRisk > 0 ? .orange : .secondary)
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AccountRow: View {
    let account: TradingAccount

    var body: some View {
        let s = RulesEngine.snapshot(for: account)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.headline)
                    Text([account.phase.label, account.accountNumber].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: s.status)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(s.balance.currency).font(.title3.weight(.semibold).monospacedDigit())
                Text(s.todayPnL.signedCurrency + " today")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(s.todayPnL.pnlColor)
                Spacer()
                Text("Buffer \((account.reported?.buffer ?? s.drawdownBuffer).currency)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(s.status == .active || s.status == .passed ? Color.secondary : s.status.color)
            }
            if let progress = s.targetProgress, account.phase == .evaluation {
                ProgressView(value: progress)
                    .tint(progress >= 1 ? .green : .accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}
