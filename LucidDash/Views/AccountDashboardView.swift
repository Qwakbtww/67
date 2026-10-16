import SwiftUI
import Charts
import UniformTypeIdentifiers
import LucidCore

struct AccountDashboardView: View {
    let accountID: UUID

    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var settings: AppSettings

    @State private var showingEditor = false
    @State private var showingImporter = false
    @State private var showingAddTrade = false
    @State private var importMessage: String?

    var body: some View {
        if let account = store.account(id: accountID) {
            content(account)
        } else {
            ContentUnavailableView("Account removed", systemImage: "trash")
        }
    }

    private func content(_ account: TradingAccount) -> some View {
        let s = RulesEngine.snapshot(for: account)
        return ScrollView {
            VStack(spacing: 16) {
                header(account, s)
                if let reported = account.reported {
                    ReportedCard(reported: reported, snapshot: s)
                }
                if account.trades.isEmpty {
                    noTradesCard
                } else {
                    RuleCards(account: account, snapshot: s)
                    EquityChartCard(snapshot: s)
                    DailyPnLCard(days: s.days)
                    StatsCard(snapshot: s)
                    NavigationLink {
                        TradesListView(accountID: accountID)
                    } label: {
                        HStack {
                            Label("All trades", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Text("\(s.tradeCount)").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingImporter = true } label: {
                        Label("Import CSV…", systemImage: "square.and.arrow.down")
                    }
                    Button { showingAddTrade = true } label: {
                        Label("Add Trade", systemImage: "plus.circle")
                    }
                    Button { showingEditor = true } label: {
                        Label("Edit Account & Rules", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) { AccountEditorView(account: account) }
        .sheet(isPresented: $showingAddTrade) { AddTradeView(accountID: accountID) }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text]
        ) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: Binding(isPresenting: $importMessage)) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func header(_ account: TradingAccount, _ s: AccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.phase.label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(status: s.status)
            }
            Text(s.balance.currency)
                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 16) {
                Label(s.todayPnL.signedCurrency, systemImage: "sun.max")
                    .foregroundStyle(s.todayPnL.pnlColor)
                Label(s.profit.signedCurrency, systemImage: "sum")
                    .foregroundStyle(s.profit.pnlColor)
            }
            .font(.subheadline.monospacedDigit())
            Text("Start \(account.rules.startingBalance.currency) · \(account.rules.drawdownType.label) drawdown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var noTradesCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(.secondary)
            Text("No trades yet").font(.headline)
            Text("Open the Tradovate tab, log in and download your Performance report: the app imports it automatically. You can also import a CSV from Files or add trades by hand.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Import CSV") { showingImporter = true }.buttonStyle(.borderedProminent)
                Button("Add Trade") { showingAddTrade = true }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription
        case .success(let url):
            do {
                let r = try store.importCSV(from: url, into: accountID, timeZone: settings.importTimeZone)
                var parts = ["Added \(r.added) trade\(r.added == 1 ? "" : "s")."]
                if r.duplicates > 0 { parts.append("\(r.duplicates) already imported.") }
                if r.skipped > 0 { parts.append("\(r.skipped) row\(r.skipped == 1 ? "" : "s") couldn't be read.") }
                importMessage = parts.joined(separator: " ")
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Cards

extension View {
    func card() -> some View {
        padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Numbers read from Lucid's own dashboard, shown next to the app's calculation.
private struct ReportedCard: View {
    let reported: ReportedFigures
    let snapshot: AccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("From Lucid's dashboard", systemImage: "checkmark.shield")
                    .font(.headline)
                Spacer()
                Text(reported.capturedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("Lucid").font(.caption).foregroundStyle(.secondary)
                    Text("This app").font(.caption).foregroundStyle(.secondary)
                }
                row("Balance", reported.balance, snapshot.balance)
                row("Floor", reported.drawdownFloor, snapshot.drawdownThreshold)
                row("Room", reported.buffer, snapshot.drawdownBuffer)
            }
            if let buffer = reported.buffer, abs(buffer - snapshot.drawdownBuffer) >= 1 {
                Text("The numbers differ. Lucid's are the official ones; import your latest trades or adjust the account rules to line them up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Update from the Lucid tab → Read numbers.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ title: String, _ lucid: Double?, _ ours: Double) -> some View {
        GridRow {
            Text(title).font(.subheadline)
            Text(lucid?.currency ?? "—").font(.subheadline.weight(.semibold).monospacedDigit())
            Text(ours.currency).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

private struct RuleCards: View {
    let account: TradingAccount
    let snapshot: AccountSnapshot

    var body: some View {
        let rules = account.rules
        let s = snapshot
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            RuleGauge(
                title: "Drawdown buffer",
                value: s.drawdownBuffer.currency,
                detail: "Floor \(s.drawdownThreshold.currency)" + (s.drawdownLocked ? " · locked" : ""),
                progress: rules.maxDrawdown > 0 ? s.drawdownBuffer / rules.maxDrawdown : 0,
                tint: s.drawdownBuffer <= rules.maxDrawdown * RulesEngine.warningShare ? .red : .green
            )
            if let target = rules.profitTarget, let progress = s.targetProgress {
                RuleGauge(
                    title: "Profit target",
                    value: progress.percent,
                    detail: s.targetRemaining == 0 ? "Reached \(target.currency)" : "\(s.targetRemaining!.currency) to go",
                    progress: progress,
                    tint: progress >= 1 ? .green : .accentColor
                )
            }
            if let limit = rules.dailyLossLimit, let remaining = s.dailyLossRemaining {
                RuleGauge(
                    title: "Daily loss left",
                    value: remaining.currency,
                    detail: "Limit \(limit.currency)",
                    progress: limit > 0 ? remaining / limit : 0,
                    tint: remaining <= limit * RulesEngine.warningShare ? .red : .green
                )
            }
            if let limit = rules.consistencyLimit {
                RuleGauge(
                    title: "Consistency",
                    value: s.consistencyRatio?.percent ?? "—",
                    detail: "Best day ≤ \(limit.percent) of profit",
                    progress: s.consistencyRatio.map { min($0 / limit, 1) } ?? 0,
                    tint: s.consistencyOK ? .green : .orange
                )
            }
        }
    }
}

private struct RuleGauge: View {
    let title: String
    let value: String
    let detail: String
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
            ProgressView(value: min(max(progress, 0), 1)).tint(tint)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct EquityChartCard: View {
    let snapshot: AccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Balance vs. drawdown floor").font(.headline)
            Chart(snapshot.equityCurve) { point in
                LineMark(x: .value("Trade", point.index), y: .value("Balance", point.balance),
                         series: .value("Series", "Balance"))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Trade", point.index), y: .value("Floor", point.threshold),
                         series: .value("Series", "Floor"))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .interpolationMethod(.stepEnd)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxisLabel("Trade #")
            .frame(height: 200)
            HStack(spacing: 16) {
                legend(Color.accentColor, "Balance")
                legend(.red, "Drawdown floor")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .card()
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

private struct DailyPnLCard: View {
    let days: [DailySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily P&L").font(.headline)
            Chart(days.suffix(30)) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("P&L", day.netPnL))
                    .foregroundStyle(day.netPnL >= 0 ? Color.green : Color.red)
            }
            .frame(height: 160)

            ForEach(days.suffix(5).reversed()) { day in
                HStack {
                    Text(day.day, format: .dateTime.weekday(.abbreviated).month().day())
                    Text("\(day.tradeCount) trades").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(day.netPnL.signedCurrency)
                        .monospacedDigit()
                        .foregroundStyle(day.netPnL.pnlColor)
                }
                .font(.subheadline)
            }
        }
        .card()
    }
}

private struct StatsCard: View {
    let snapshot: AccountSnapshot

    var body: some View {
        let s = snapshot
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    stat("Win rate", s.winRate?.percent ?? "—")
                    stat("Profit factor", s.profitFactor.map { String(format: "%.2f", $0) } ?? "—")
                }
                GridRow {
                    stat("Avg win", s.averageWin?.currency ?? "—")
                    stat("Avg loss", s.averageLoss?.currency ?? "—")
                }
                GridRow {
                    stat("Trades", "\(s.tradeCount)")
                    stat("Trading days", "\(s.tradingDays)")
                }
                GridRow {
                    stat("Peak balance", s.peakBalance.currency)
                    stat("Best day", s.days.map(\.netPnL).max()?.signedCurrency ?? "—")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
