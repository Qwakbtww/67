import XCTest
@testable import LucidCore

final class RulesEngineTests: XCTestCase {
    let ny = TimeZone(identifier: "America/New_York")!

    func date(_ s: String) -> Date {
        CSVImporter.parseDate(s, timeZone: ny)!
    }

    func testTradingDayRollsAtSixPM() {
        let cal = TradingCalendar.cme
        XCTAssertEqual(cal.tradingDay(for: date("2026-10-12 17:59:00")), cal.tradingDay(for: date("2026-10-12 09:00:00")))
        XCTAssertEqual(cal.tradingDay(for: date("2026-10-12 18:00:00")), cal.tradingDay(for: date("2026-10-13 09:00:00")))
    }

    func testEndOfDayTrailingAndLock() {
        let rules = AccountRules(startingBalance: 50_000, profitTarget: 3_000, maxDrawdown: 2_000,
                                 drawdownType: .endOfDay, drawdownLockOffset: 100)
        var account = TradingAccount(name: "t", rules: rules)
        account.merge([
            Trade(symbol: "MNQ", quantity: 1, exitTime: date("2026-10-12 10:00:00"), grossPnL: 1_000),
            // Intraday spike that is given back the same day: must not move an EOD threshold.
            Trade(symbol: "MNQ", quantity: 1, exitTime: date("2026-10-13 10:00:00"), grossPnL: 800),
            Trade(symbol: "MNQ", quantity: 1, exitTime: date("2026-10-13 11:00:00"), grossPnL: -800),
        ])
        let s = RulesEngine.snapshot(for: account, now: date("2026-10-14 09:00:00"))
        XCTAssertEqual(s.balance, 51_000)
        XCTAssertEqual(s.peakBalance, 51_000)
        XCTAssertEqual(s.drawdownThreshold, 49_000)
        XCTAssertEqual(s.drawdownBuffer, 2_000)
        XCTAssertFalse(s.drawdownLocked)
        XCTAssertEqual(s.tradingDays, 2)

        account.merge([Trade(symbol: "MNQ", quantity: 1, exitTime: date("2026-10-14 10:00:00"), grossPnL: 1_500)])
        let s2 = RulesEngine.snapshot(for: account, now: date("2026-10-15 09:00:00"))
        // Peak 52,500 → trailed 50,500, but locks at 50,100.
        XCTAssertEqual(s2.drawdownThreshold, 50_100)
        XCTAssertTrue(s2.drawdownLocked)
    }

    func testTodayDoesNotMoveEODThreshold() {
        let rules = AccountRules(startingBalance: 50_000, maxDrawdown: 2_000, drawdownType: .endOfDay)
        var account = TradingAccount(name: "t", rules: rules)
        account.merge([Trade(symbol: "ES", quantity: 1, exitTime: date("2026-10-14 10:00:00"), grossPnL: 1_000)])
        let s = RulesEngine.snapshot(for: account, now: date("2026-10-14 12:00:00"))
        XCTAssertEqual(s.drawdownThreshold, 48_000)
        XCTAssertEqual(s.todayPnL, 1_000)
    }

    func testTrailingPerTrade() {
        let rules = AccountRules(startingBalance: 50_000, maxDrawdown: 2_000, drawdownType: .trailing)
        var account = TradingAccount(name: "t", rules: rules)
        account.merge([
            Trade(symbol: "ES", quantity: 1, exitTime: date("2026-10-14 10:00:00"), grossPnL: 800),
            Trade(symbol: "ES", quantity: 1, exitTime: date("2026-10-14 11:00:00"), grossPnL: -800),
        ])
        let s = RulesEngine.snapshot(for: account, now: date("2026-10-14 12:00:00"))
        XCTAssertEqual(s.drawdownThreshold, 48_800)
    }

    func testBreachAndDailyLoss() {
        let rules = AccountRules(startingBalance: 50_000, maxDrawdown: 2_000, dailyLossLimit: 1_000)
        var account = TradingAccount(name: "t", rules: rules)
        account.merge([Trade(symbol: "ES", quantity: 1, exitTime: date("2026-10-14 10:00:00"), grossPnL: -1_000)])
        let s = RulesEngine.snapshot(for: account, now: date("2026-10-14 12:00:00"))
        XCTAssertEqual(s.dailyLossRemaining, 0)
        XCTAssertEqual(s.status, .breached)

        account.merge([Trade(symbol: "ES", quantity: 1, exitTime: date("2026-10-15 10:00:00"), grossPnL: -500)])
        let s2 = RulesEngine.snapshot(for: account, now: date("2026-10-15 12:00:00"))
        XCTAssertEqual(s2.dailyLossRemaining, 500)
        XCTAssertEqual(s2.drawdownBuffer, 500)
        XCTAssertEqual(s2.status, .warning)
    }

    func testTargetAndConsistency() {
        let rules = AccountRules(startingBalance: 50_000, profitTarget: 3_000, maxDrawdown: 2_000, consistencyLimit: 0.5)
        var account = TradingAccount(name: "t", rules: rules)
        account.merge([
            Trade(symbol: "ES", quantity: 1, exitTime: date("2026-10-12 10:00:00"), grossPnL: 2_000),
            Trade(symbol: "ES", quantity: 1, exitTime: date("2026-10-13 10:00:00"), grossPnL: 1_000),
        ])
        var s = RulesEngine.snapshot(for: account, now: date("2026-10-14 12:00:00"))
        XCTAssertEqual(s.targetProgress, 1)
        XCTAssertEqual(s.consistencyRatio!, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertFalse(s.consistencyOK)
        XCTAssertNotEqual(s.status, .passed)

        account.merge([Trade(symbol: "ES", quantity: 1, exitTime: date("2026-10-14 10:00:00"), grossPnL: 1_000)])
        s = RulesEngine.snapshot(for: account, now: date("2026-10-15 12:00:00"))
        XCTAssertTrue(s.consistencyOK)
        XCTAssertEqual(s.status, .passed)
    }

    func testDemoAccountIsStable() {
        let now = date("2026-10-16 12:00:00")
        let a = SampleData.demoAccount(now: now)
        let b = SampleData.demoAccount(now: now)
        XCTAssertFalse(a.trades.isEmpty)
        XCTAssertEqual(a.trades.map(\.grossPnL), b.trades.map(\.grossPnL))
    }
}

final class CSVImporterTests: XCTestCase {
    let ny = TimeZone(identifier: "America/New_York")!

    func testTradovatePerformanceExport() throws {
        let csv = """
        \u{FEFF}symbol,_priceFormat,_priceFormatType,_tickSize,buyFillId,sellFillId,qty,buyPrice,sellPrice,pnl,boughtTimestamp,soldTimestamp,duration
        MNQZ6,-2,0,0.25,1,2,2,21000.25,21010.50,$41.00,10/14/2026 09:31:02,10/14/2026 09:35:40,4min 38sec\r
        MNQZ6,-2,0,0.25,3,4,1,21020.00,21005.00,$(30.00),10/14/2026 10:12:00,10/14/2026 10:02:11,9min 49sec\r
        "MESZ6",-2,0,0.25,5,6,1,"5,800.00","5,810.00","$1,050.00",10/14/2026 11:00:00,10/14/2026 11:05:00,5min
        """
        let result = try CSVImporter.parse(csv, timeZone: ny)
        XCTAssertEqual(result.trades.count, 3)
        XCTAssertEqual(result.skippedRows, [])
        XCTAssertEqual(result.trades.map(\.grossPnL), [41, -30, 1_050])
        XCTAssertEqual(result.trades[0].quantity, 2)
        XCTAssertEqual(result.trades[2].symbol, "MESZ6")
        // Short trade: sold first, bought later → exit is the later timestamp.
        let short = result.trades[1]
        XCTAssertLessThan(short.entryTime!, short.exitTime)
    }

    func testGenericExport() throws {
        let csv = """
        Date,Symbol,Quantity,P&L,Commission
        2026-10-14 10:00:00,ES,1,-125.50,4.20
        2026-10-14 11:00:00,ES,1,not a number,4.20
        2026-10-15,NQ,2,300,8.40
        """
        let result = try CSVImporter.parse(csv, timeZone: ny)
        XCTAssertEqual(result.trades.count, 2)
        XCTAssertEqual(result.skippedRows, [2])
        XCTAssertEqual(result.trades[0].netPnL, -129.70, accuracy: 1e-9)
    }

    func testMissingPnLColumn() {
        XCTAssertThrowsError(try CSVImporter.parse("date,symbol\n2026-10-14,ES")) { error in
            XCTAssertEqual(error as? CSVImportError, .missingColumn("P&L"))
        }
    }

    func testMoneyParsing() {
        XCTAssertEqual(CSVImporter.parseMoney("$1,234.50"), 1_234.5)
        XCTAssertEqual(CSVImporter.parseMoney("-$25.00"), -25)
        XCTAssertEqual(CSVImporter.parseMoney("$(25.00)"), -25)
        XCTAssertEqual(CSVImporter.parseMoney("(25)"), -25)
        XCTAssertNil(CSVImporter.parseMoney("abc"))
    }

    func testMergeSkipsDuplicates() throws {
        let csv = "date,symbol,qty,pnl\n2026-10-14 10:00:00,ES,1,100\n"
        let trades = try CSVImporter.parse(csv, timeZone: ny).trades
        var account = TradingAccount(name: "t", rules: AccountRules(startingBalance: 50_000, maxDrawdown: 2_000))
        XCTAssertEqual(account.merge(trades), 1)
        XCTAssertEqual(account.merge(try CSVImporter.parse(csv, timeZone: ny).trades), 0)
    }
}

final class TradingCalendarTests: XCTestCase {
    func testTradingDayReadsSameDateAcrossZones() {
        let ny = TimeZone(identifier: "America/New_York")!
        let trade = CSVImporter.parseDate("2026-10-14 09:30:00", timeZone: ny)!
        for id in ["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Singapore", "Pacific/Auckland"] {
            let day = TradingCalendar(timeZone: ny, sessionStartHour: 18, displayTimeZone: TimeZone(identifier: id)!)
                .tradingDay(for: trade)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: id)!
            XCTAssertEqual(cal.component(.day, from: day), 14, id)
        }
    }
}
