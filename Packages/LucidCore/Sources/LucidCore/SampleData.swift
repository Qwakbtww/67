import Foundation

public enum SampleData {
    /// A 50K evaluation with three weeks of plausible MES/MNQ trades, ending yesterday.
    public static func demoAccount(now: Date = Date()) -> TradingAccount {
        let rules = RulePreset.all.first { $0.id == "50k" }!.rules
        var account = TradingAccount(name: "Demo 50K Eval", accountNumber: "DEMO-0001", phase: .evaluation, rules: rules)

        var generator = SeededGenerator(seed: 42)
        let symbols = ["MNQZ6", "MESZ6", "NQZ6", "ESZ6"]
        let calendar = Calendar(identifier: .gregorian)
        var trades: [Trade] = []
        for dayOffset in stride(from: 21, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 { continue }
            let count = Int.random(in: 2...5, using: &generator)
            for n in 0..<count {
                let exit = calendar.date(bySettingHour: 10 + n, minute: Int.random(in: 0...59, using: &generator), second: 0, of: day) ?? day
                let pnl = (Double.random(in: -420...560, using: &generator) / 5).rounded() * 5
                let qty = Int.random(in: 1...3, using: &generator)
                trades.append(Trade(
                    symbol: symbols.randomElement(using: &generator)!,
                    quantity: qty,
                    entryTime: exit.addingTimeInterval(-Double.random(in: 120...2400, using: &generator)),
                    exitTime: exit,
                    grossPnL: pnl,
                    fees: Double(qty) * 1.04
                ))
            }
        }
        account.merge(trades)
        return account
    }
}

/// Deterministic RNG so demo data is the same every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
