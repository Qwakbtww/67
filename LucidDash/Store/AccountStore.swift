import Foundation
import LucidCore

/// Holds every tracked account and persists them as JSON in the app's Documents folder.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [TradingAccount] = []
    @Published var lastError: String?
    /// A CSV waiting for the user to choose an account (from Tradovate or the share sheet).
    @Published var pendingImport: PendingImport?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("accounts.json")
        load()
    }

    func account(id: UUID) -> TradingAccount? {
        accounts.first { $0.id == id }
    }

    func upsert(_ account: TradingAccount) {
        if let i = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[i] = account
        } else {
            accounts.append(account)
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        accounts.remove(atOffsets: offsets)
        save()
    }

    func delete(id: UUID) {
        accounts.removeAll { $0.id == id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Imports a CSV export into an account. Returns (added, duplicates, skipped rows).
    func importCSV(from url: URL, into accountID: UUID, timeZone: TimeZone) throws -> (added: Int, duplicates: Int, skipped: Int) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CSVImportError.empty
        }
        let result = try CSVImporter.parse(text, timeZone: timeZone)
        guard var account = account(id: accountID) else { return (0, 0, 0) }
        let added = account.merge(result.trades)
        upsert(account)
        return (added, result.trades.count - added, result.skippedRows.count)
    }

    func addTrade(_ trade: Trade, to accountID: UUID) {
        guard var account = account(id: accountID) else { return }
        account.merge([trade])
        upsert(account)
    }

    func deleteTrades(ids: Set<UUID>, from accountID: UUID) {
        guard var account = account(id: accountID) else { return }
        account.trades.removeAll { ids.contains($0.id) }
        upsert(account)
    }

    func setReported(_ figures: ReportedFigures, for accountID: UUID) {
        guard var account = account(id: accountID) else { return }
        account.reported = figures
        upsert(account)
    }

    func addDemoAccount() {
        upsert(SampleData.demoAccount())
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            accounts = try JSONDecoder().decode([TradingAccount].self, from: data)
        } catch {
            lastError = "Couldn't read saved accounts: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            lastError = "Couldn't save accounts: \(error.localizedDescription)"
        }
    }
}
