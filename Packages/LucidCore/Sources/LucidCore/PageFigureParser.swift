import Foundation

/// A labelled dollar amount found in a web page's visible text.
public struct PageFigure: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let label: String
    public let amount: Double
    /// What the label most likely means, if recognised.
    public let kind: Kind?
    /// Nearest account-number-looking string above the figure, if any.
    public let accountHint: String?

    public enum Kind: String, Sendable {
        case balance
        case drawdownFloor
        case drawdownRemaining
        case profit
        case target
        case dailyLoss
    }
}

/// Pulls "Label … $1,234.56" pairs out of a page's innerText so numbers from
/// Lucid's dashboard can be assigned to accounts without knowing its markup.
public enum PageFigureParser {
    public static func parse(_ text: String) -> [PageFigure] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var figures: [PageFigure] = []
        var lastAccount: String?
        var consumed = Set<Int>()

        for (i, line) in lines.enumerated() {
            if let account = accountNumber(in: line) { lastAccount = account }
            guard !consumed.contains(i), isLabel(line) else { continue }

            // Value on the same line ("Balance: $50,120.00") or within the next two lines.
            var amount: Double?
            if let inline = amounts(in: line).last {
                amount = inline
            } else {
                for j in (i + 1)..<min(i + 3, lines.count) {
                    if isLabel(lines[j]) && amounts(in: lines[j]).isEmpty { break }
                    if let found = amounts(in: lines[j]).first {
                        amount = found
                        consumed.insert(j)
                        break
                    }
                }
            }
            guard let amount else { continue }
            let label = cleanLabel(line)
            figures.append(PageFigure(index: figures.count, label: label, amount: amount,
                                      kind: kind(for: label), accountHint: lastAccount))
        }
        return figures
    }

    static func kind(for label: String) -> PageFigure.Kind? {
        let l = label.lowercased()
        if l.contains("threshold") || l.contains("liquidation") || l.contains("floor")
            || l.contains("max loss limit") || l.contains("min balance") || l.contains("minimum balance") {
            return .drawdownFloor
        }
        if l.contains("drawdown") || l.contains("max loss") { return .drawdownRemaining }
        if l.contains("daily") { return .dailyLoss }
        if l.contains("target") { return .target }
        if l.contains("balance") || l.contains("net liq") || l.contains("equity") { return .balance }
        if l.contains("p&l") || l.contains("pnl") || l.contains("profit") { return .profit }
        return nil
    }

    private static let labelWords = [
        "balance", "equity", "net liq", "drawdown", "threshold", "liquidation", "floor",
        "max loss", "loss limit", "profit", "target", "p&l", "pnl", "daily", "min balance", "minimum balance",
    ]

    static func isLabel(_ line: String) -> Bool {
        let l = line.lowercased()
        guard line.count <= 60 else { return false }
        return labelWords.contains { l.contains($0) }
    }

    static func cleanLabel(_ line: String) -> String {
        var label = line
        if let dollar = label.firstIndex(where: { $0 == "$" || $0 == "-" || $0 == "(" || $0.isNumber }),
           label[label.startIndex..<dollar].contains(where: \.isLetter) {
            label = String(label[label.startIndex..<dollar])
        }
        return label.trimmingCharacters(in: CharacterSet(charactersIn: " :–-\t"))
    }

    /// Dollar amounts in a line. Requires a "$" or a decimal amount so stray integers
    /// (dates, contract counts) aren't picked up.
    static func amounts(in line: String) -> [Double] {
        let pattern = #"(\(?-?\$?\(?-?\s?\$?\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?\)?|\(?-?\$?\d+(?:\.\d{1,2})?\)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let token = ns.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            guard token.contains("$") || token.contains(".") else { return nil }
            return CSVImporter.parseMoney(token)
        }
    }

    /// Strings like "LFE0501234567" or "LT-12345": mixed letters and 5+ digits.
    static func accountNumber(in line: String) -> String? {
        let pattern = #"\b[A-Z]{2,}[A-Z0-9-]*\d{5,}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return nil }
        return (line as NSString).substring(with: match.range)
    }
}
