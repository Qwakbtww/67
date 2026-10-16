import SwiftUI
import LucidCore

struct TradesListView: View {
    let accountID: UUID

    @EnvironmentObject private var store: AccountStore
    @State private var search = ""

    var body: some View {
        let trades = (store.account(id: accountID)?.trades ?? [])
            .filter { search.isEmpty || $0.symbol.localizedCaseInsensitiveContains(search) }
            .sorted { $0.exitTime > $1.exitTime }
        let grouped = Dictionary(grouping: trades) { TradingCalendar.cme.tradingDay(for: $0.exitTime) }
        let days = grouped.keys.sorted(by: >)

        List {
            ForEach(days, id: \.self) { day in
                let dayTrades = grouped[day] ?? []
                let total = dayTrades.reduce(0) { $0 + $1.netPnL }
                Section {
                    ForEach(dayTrades) { trade in
                        TradeRow(trade: trade)
                    }
                    .onDelete { offsets in
                        store.deleteTrades(ids: Set(offsets.map { dayTrades[$0].id }), from: accountID)
                    }
                } header: {
                    HStack {
                        Text(day, format: .dateTime.weekday(.wide).month().day().year())
                        Spacer()
                        Text(total.signedCurrency).foregroundStyle(total.pnlColor).monospacedDigit()
                    }
                }
            }
        }
        .overlay {
            if trades.isEmpty {
                ContentUnavailableView.search
            }
        }
        .searchable(text: $search, prompt: "Symbol")
        .navigationTitle("Trades")
    }
}

private struct TradeRow: View {
    let trade: Trade

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trade.symbol).font(.headline)
                HStack(spacing: 6) {
                    Text("\(trade.quantity) ct")
                    Text(trade.exitTime, format: .dateTime.hour().minute())
                    if trade.fees > 0 {
                        Text("fees \(trade.fees.currency)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(trade.netPnL.signedCurrency)
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(trade.netPnL.pnlColor)
        }
    }
}
