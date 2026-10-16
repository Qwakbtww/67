import Foundation

/// Maps timestamps to futures trading days. The CME session opens at 6 PM New York time,
/// so a trade closed at 7 PM Monday counts toward Tuesday.
public struct TradingCalendar: Sendable {
    /// Time zone the session boundary is defined in.
    public var timeZone: TimeZone
    public var sessionStartHour: Int
    /// Time zone the returned day dates are meant to be displayed in.
    public var displayTimeZone: TimeZone

    public static var cme: TradingCalendar {
        TradingCalendar(timeZone: TimeZone(identifier: "America/New_York")!, sessionStartHour: 18)
    }

    public init(timeZone: TimeZone, sessionStartHour: Int, displayTimeZone: TimeZone = .current) {
        self.timeZone = timeZone
        self.sessionStartHour = sessionStartHour
        self.displayTimeZone = displayTimeZone
    }

    /// The trading day `date` belongs to, as noon of that calendar date in
    /// `displayTimeZone`, so formatting it on the device shows the right date.
    public func tradingDay(for date: Date) -> Date {
        var session = Calendar(identifier: .gregorian)
        session.timeZone = timeZone
        let shifted = date.addingTimeInterval(TimeInterval((24 - sessionStartHour) * 3600))
        var parts = session.dateComponents([.year, .month, .day], from: shifted)
        parts.hour = 12

        var display = Calendar(identifier: .gregorian)
        display.timeZone = displayTimeZone
        return display.date(from: parts)!
    }
}

public struct DailySummary: Identifiable, Hashable, Sendable {
    public var id: Date { day }
    public let day: Date
    public let netPnL: Double
    public let tradeCount: Int
    public let endBalance: Double
}

public struct EquityPoint: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let date: Date
    public let balance: Double
    public let threshold: Double
}

public enum AccountStatus: String, Sendable {
    case active, warning, passed, breached

    public var label: String {
        switch self {
        case .active: "Active"
        case .warning: "At risk"
        case .passed: "Target hit"
        case .breached: "Breached"
        }
    }
}

public struct AccountSnapshot: Sendable {
    public let balance: Double
    public let profit: Double
    public let peakBalance: Double
    public let drawdownThreshold: Double
    /// Money left before the drawdown threshold is touched.
    public let drawdownBuffer: Double
    public let drawdownLocked: Bool

    public let todayPnL: Double
    /// nil when the account has no daily loss limit.
    public let dailyLossRemaining: Double?

    /// 0...1, nil when the account has no profit target.
    public let targetProgress: Double?
    public let targetRemaining: Double?

    /// Largest winning day / total profit; nil when total profit <= 0.
    public let consistencyRatio: Double?
    public let consistencyOK: Bool

    public let winRate: Double?
    public let profitFactor: Double?
    public let averageWin: Double?
    public let averageLoss: Double?
    public let tradeCount: Int
    public let tradingDays: Int

    public let days: [DailySummary]
    public let equityCurve: [EquityPoint]
    public let status: AccountStatus
}

public enum RulesEngine {
    /// Buffer below this share of max drawdown flags the account as at risk.
    public static let warningShare = 0.25

    public static func snapshot(
        for account: TradingAccount,
        now: Date = Date(),
        calendar: TradingCalendar = .cme
    ) -> AccountSnapshot {
        let rules = account.rules
        let trades = account.trades.sorted { $0.exitTime < $1.exitTime }
        let today = calendar.tradingDay(for: now)

        // Daily summaries.
        var dayOrder: [Date] = []
        var dayPnL: [Date: Double] = [:]
        var dayCount: [Date: Int] = [:]
        for trade in trades {
            let day = calendar.tradingDay(for: trade.exitTime)
            if dayPnL[day] == nil { dayOrder.append(day) }
            dayPnL[day, default: 0] += trade.netPnL
            dayCount[day, default: 0] += 1
        }
        var running = rules.startingBalance
        let days: [DailySummary] = dayOrder.map { day in
            running += dayPnL[day]!
            return DailySummary(day: day, netPnL: dayPnL[day]!, tradeCount: dayCount[day]!, endBalance: running)
        }
        let balance = running

        // Threshold computation, replayed trade by trade so the curve shows how it moved.
        let lockLevel = rules.drawdownLockOffset.map { rules.startingBalance + $0 }
        func threshold(forPeak peak: Double) -> Double {
            guard rules.drawdownType != .fixed else { return rules.startingBalance - rules.maxDrawdown }
            let trailed = peak - rules.maxDrawdown
            if let lockLevel { return min(trailed, lockLevel) }
            return trailed
        }

        var peak = rules.startingBalance
        var curve: [EquityPoint] = []
        var bal = rules.startingBalance
        var breachedAtSomePoint = false
        curve.append(EquityPoint(index: 0, date: trades.first?.exitTime ?? now, balance: bal, threshold: threshold(forPeak: peak)))
        for (i, trade) in trades.enumerated() {
            bal += trade.netPnL
            let current = threshold(forPeak: peak)
            if bal <= current { breachedAtSomePoint = true }
            switch rules.drawdownType {
            case .trailing:
                peak = max(peak, bal)
            case .endOfDay:
                // Peak updates only at the close of a completed trading day.
                let day = calendar.tradingDay(for: trade.exitTime)
                let isLastOfDay = i == trades.count - 1 || calendar.tradingDay(for: trades[i + 1].exitTime) != day
                if isLastOfDay && day < today { peak = max(peak, bal) }
            case .fixed:
                break
            }
            curve.append(EquityPoint(index: i + 1, date: trade.exitTime, balance: bal, threshold: threshold(forPeak: peak)))
        }

        let drawdownThreshold = threshold(forPeak: peak)
        let buffer = balance - drawdownThreshold
        let locked = lockLevel.map { rules.drawdownType != .fixed && drawdownThreshold >= $0 } ?? false

        // Daily loss.
        let todayPnL = dayPnL[today] ?? 0
        let dailyRemaining = rules.dailyLossLimit.map { $0 + min(todayPnL, 0) }
        let dailyBreached = rules.dailyLossLimit.map { todayPnL <= -$0 } ?? false

        // Target.
        let profit = balance - rules.startingBalance
        let targetProgress = rules.profitTarget.map { $0 > 0 ? min(max(profit / $0, 0), 1) : 1 }
        let targetRemaining = rules.profitTarget.map { max($0 - profit, 0) }

        // Consistency.
        let bestDay = days.map(\.netPnL).max() ?? 0
        let consistencyRatio: Double? = profit > 0 && bestDay > 0 ? bestDay / profit : nil
        let consistencyOK: Bool = {
            guard let limit = rules.consistencyLimit else { return true }
            guard let ratio = consistencyRatio else { return true }
            return ratio <= limit
        }()

        // Trade stats.
        let wins = trades.filter { $0.netPnL > 0 }
        let losses = trades.filter { $0.netPnL < 0 }
        let grossWin = wins.reduce(0) { $0 + $1.netPnL }
        let grossLoss = -losses.reduce(0) { $0 + $1.netPnL }

        let status: AccountStatus
        if breachedAtSomePoint || buffer <= 0 || dailyBreached {
            status = .breached
        } else if buffer <= rules.maxDrawdown * warningShare
                    || (rules.dailyLossLimit.map { dailyRemaining! <= $0 * warningShare } ?? false) {
            status = .warning
        } else if account.phase == .evaluation, let target = rules.profitTarget, profit >= target, consistencyOK {
            status = .passed
        } else {
            status = .active
        }

        return AccountSnapshot(
            balance: balance,
            profit: profit,
            peakBalance: peak,
            drawdownThreshold: drawdownThreshold,
            drawdownBuffer: buffer,
            drawdownLocked: locked,
            todayPnL: todayPnL,
            dailyLossRemaining: dailyRemaining,
            targetProgress: targetProgress,
            targetRemaining: targetRemaining,
            consistencyRatio: consistencyRatio,
            consistencyOK: consistencyOK,
            winRate: trades.isEmpty ? nil : Double(wins.count) / Double(trades.count),
            profitFactor: grossLoss > 0 ? grossWin / grossLoss : nil,
            averageWin: wins.isEmpty ? nil : grossWin / Double(wins.count),
            averageLoss: losses.isEmpty ? nil : -grossLoss / Double(losses.count),
            tradeCount: trades.count,
            tradingDays: days.count,
            days: days,
            equityCurve: curve,
            status: status
        )
    }
}
