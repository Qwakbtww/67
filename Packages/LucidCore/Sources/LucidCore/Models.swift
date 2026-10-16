import Foundation

/// A single closed (round-trip) trade.
public struct Trade: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var symbol: String
    public var quantity: Int
    public var entryTime: Date?
    public var exitTime: Date
    /// Realized P&L before commissions/fees.
    public var grossPnL: Double
    /// Commissions and fees (positive number).
    public var fees: Double
    public var note: String?

    public var netPnL: Double { grossPnL - fees }

    public init(
        id: UUID = UUID(),
        symbol: String,
        quantity: Int,
        entryTime: Date? = nil,
        exitTime: Date,
        grossPnL: Double,
        fees: Double = 0,
        note: String? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.quantity = quantity
        self.entryTime = entryTime
        self.exitTime = exitTime
        self.grossPnL = grossPnL
        self.fees = fees
        self.note = note
    }

    /// Key used to skip duplicates when the same export is imported twice.
    public var dedupeKey: String {
        "\(symbol.uppercased())|\(quantity)|\(Int(exitTime.timeIntervalSince1970))|\(Int((grossPnL * 100).rounded()))"
    }
}

public enum DrawdownType: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Threshold trails the highest end-of-day balance.
    case endOfDay
    /// Threshold trails the highest balance after any closed trade.
    case trailing
    /// Threshold never moves.
    case fixed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .endOfDay: "End-of-day trailing"
        case .trailing: "Trailing (per trade)"
        case .fixed: "Static"
        }
    }
}

public enum AccountPhase: String, Codable, CaseIterable, Sendable, Identifiable {
    case evaluation
    case funded

    public var id: String { rawValue }
    public var label: String { self == .evaluation ? "Evaluation" : "Funded" }
}

/// The rules a prop account is measured against. All money values are in account currency.
public struct AccountRules: Codable, Hashable, Sendable {
    public var startingBalance: Double
    /// Profit needed above the starting balance (evaluations), or nil.
    public var profitTarget: Double?
    /// Maximum drawdown distance from the peak balance.
    public var maxDrawdown: Double
    public var drawdownType: DrawdownType
    /// The drawdown threshold stops trailing once it reaches `startingBalance + drawdownLockOffset`.
    /// nil means it never locks.
    public var drawdownLockOffset: Double?
    /// Max loss allowed in a single trading day, or nil.
    public var dailyLossLimit: Double?
    /// Max share of total profit a single day may account for (0.5 = 50%), or nil.
    public var consistencyLimit: Double?

    public init(
        startingBalance: Double,
        profitTarget: Double? = nil,
        maxDrawdown: Double,
        drawdownType: DrawdownType = .endOfDay,
        drawdownLockOffset: Double? = nil,
        dailyLossLimit: Double? = nil,
        consistencyLimit: Double? = nil
    ) {
        self.startingBalance = startingBalance
        self.profitTarget = profitTarget
        self.maxDrawdown = maxDrawdown
        self.drawdownType = drawdownType
        self.drawdownLockOffset = drawdownLockOffset
        self.dailyLossLimit = dailyLossLimit
        self.consistencyLimit = consistencyLimit
    }
}

public struct TradingAccount: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Account number as shown by Lucid / the platform (optional, for reference).
    public var accountNumber: String
    public var phase: AccountPhase
    public var rules: AccountRules
    public var trades: [Trade]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        accountNumber: String = "",
        phase: AccountPhase = .evaluation,
        rules: AccountRules,
        trades: [Trade] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.accountNumber = accountNumber
        self.phase = phase
        self.rules = rules
        self.trades = trades
        self.createdAt = createdAt
    }

    /// Adds trades, skipping any that already exist. Returns how many were added.
    @discardableResult
    public mutating func merge(_ newTrades: [Trade]) -> Int {
        var keys = Set(trades.map(\.dedupeKey))
        var added = 0
        for trade in newTrades where !keys.contains(trade.dedupeKey) {
            trades.append(trade)
            keys.insert(trade.dedupeKey)
            added += 1
        }
        trades.sort { $0.exitTime < $1.exitTime }
        return added
    }
}

/// Starting points for common account sizes. Values are editable per account —
/// always confirm them against your plan's current rules on Lucid's site.
public struct RulePreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let rules: AccountRules

    public static let all: [RulePreset] = [
        RulePreset(id: "25k", name: "25K", rules: AccountRules(
            startingBalance: 25_000, profitTarget: 1_250, maxDrawdown: 1_000,
            drawdownType: .endOfDay, drawdownLockOffset: 100, consistencyLimit: 0.5)),
        RulePreset(id: "50k", name: "50K", rules: AccountRules(
            startingBalance: 50_000, profitTarget: 3_000, maxDrawdown: 2_000,
            drawdownType: .endOfDay, drawdownLockOffset: 100, consistencyLimit: 0.5)),
        RulePreset(id: "100k", name: "100K", rules: AccountRules(
            startingBalance: 100_000, profitTarget: 6_000, maxDrawdown: 3_000,
            drawdownType: .endOfDay, drawdownLockOffset: 100, consistencyLimit: 0.5)),
        RulePreset(id: "150k", name: "150K", rules: AccountRules(
            startingBalance: 150_000, profitTarget: 9_000, maxDrawdown: 4_500,
            drawdownType: .endOfDay, drawdownLockOffset: 100, consistencyLimit: 0.5)),
    ]
}
