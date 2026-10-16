import Foundation

public enum CSVImportError: LocalizedError, Equatable {
    case empty
    case missingColumn(String)
    case noTrades

    public var errorDescription: String? {
        switch self {
        case .empty: "The file is empty."
        case .missingColumn(let name): "Couldn't find a \(name) column in the file."
        case .noTrades: "No trades could be read from the file."
        }
    }
}

public struct CSVImportResult: Sendable {
    public let trades: [Trade]
    /// Row numbers (1-based, header excluded) that couldn't be parsed.
    public let skippedRows: [Int]
}

/// Reads trade exports. Understands Tradovate's "Performance" report
/// (symbol, qty, pnl, boughtTimestamp, soldTimestamp) and generic files with
/// columns like Symbol / Quantity / P&L / Exit Time / Fees.
public enum CSVImporter {
    public static func parse(_ text: String, timeZone: TimeZone = .current) throws -> CSVImportResult {
        let rows = parseRows(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = rows.first else { throw CSVImportError.empty }
        let columns = header.map(normalize)

        func find(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let i = columns.firstIndex(of: candidate) { return i }
            }
            return nil
        }

        let symbolCol = find(["symbol", "contract", "instrument", "product", "ticker"])
        let qtyCol = find(["qty", "quantity", "size", "contracts", "paidqty"])
        guard let pnlCol = find(["pnl", "netpnl", "realizedpnl", "profitloss", "grosspnl", "profit", "pl", "netprofit"]) else {
            throw CSVImportError.missingColumn("P&L")
        }
        let feesCol = find(["fees", "fee", "commission", "commissions", "totalfees"])
        let boughtCol = find(["boughttimestamp", "buytime"])
        let soldCol = find(["soldtimestamp", "selltime"])
        let entryCol = find(["entrytime", "opentime", "entrydate", "opendate"])
        let exitCol = find(["exittime", "closetime", "exitdate", "closedate", "timestamp", "datetime", "date", "time"])
        guard exitCol != nil || (boughtCol != nil && soldCol != nil) else {
            throw CSVImportError.missingColumn("date/time")
        }

        var trades: [Trade] = []
        var skipped: [Int] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            func value(_ col: Int?) -> String? {
                guard let col, col < row.count else { return nil }
                let v = row[col].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }

            guard let pnl = value(pnlCol).flatMap(parseMoney) else {
                skipped.append(offset + 1)
                continue
            }

            var entry: Date?
            var exit: Date?
            if let b = value(boughtCol).flatMap({ parseDate($0, timeZone: timeZone) }),
               let s = value(soldCol).flatMap({ parseDate($0, timeZone: timeZone) }) {
                entry = min(b, s)
                exit = max(b, s)
            } else {
                exit = value(exitCol).flatMap { parseDate($0, timeZone: timeZone) }
                entry = value(entryCol).flatMap { parseDate($0, timeZone: timeZone) }
            }
            guard let exit else {
                skipped.append(offset + 1)
                continue
            }

            let qty = value(qtyCol).flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }.map { abs(Int($0)) } ?? 1
            let fees = value(feesCol).flatMap(parseMoney).map(abs) ?? 0

            trades.append(Trade(
                symbol: value(symbolCol) ?? "—",
                quantity: qty,
                entryTime: entry,
                exitTime: exit,
                grossPnL: pnl,
                fees: fees
            ))
        }

        guard !trades.isEmpty else { throw CSVImportError.noTrades }
        trades.sort { $0.exitTime < $1.exitTime }
        return CSVImportResult(trades: trades, skippedRows: skipped)
    }

    // MARK: - Helpers

    static func normalize(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Parses "$1,234.50", "-$25.00", "$(25.00)", "(25.00)", "25".
    public static func parseMoney(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        if s.hasPrefix("-") {
            negative.toggle()
            s.removeFirst()
        }
        guard let value = Double(s) else { return nil }
        return negative ? -value : value
    }

    private static let dateFormats = [
        "MM/dd/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "MM/dd/yyyy h:mm:ss a",
        "MM/dd/yyyy h:mm a",
        "M/d/yyyy H:mm:ss",
        "M/d/yyyy H:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "MM/dd/yyyy",
        "M/d/yyyy",
        "yyyy-MM-dd",
    ]

    public static func parseDate(_ raw: String, timeZone: TimeZone) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in dateFormats {
            formatter.dateFormat = format
            if let d = formatter.date(from: s) { return d }
        }
        return nil
    }

    /// RFC 4180-style parsing: quoted fields, escaped quotes, CRLF or LF.
    static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()

        while let c = pending {
            pending = iterator.next()
            if inQuotes {
                if c == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        if var first = rows.first, let firstField = first.first, firstField.hasPrefix("\u{FEFF}") {
            first[0] = String(firstField.dropFirst())
            rows[0] = first
        }
        return rows
    }
}
