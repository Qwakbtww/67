import Foundation

final class AppSettings: ObservableObject {
    static let defaultPortalURL = "https://lucidtrading.com"

    private let defaults: UserDefaults

    /// Page the Portal tab opens. Set it to your Lucid dashboard login page.
    @Published var portalURL: String {
        didSet { defaults.set(portalURL, forKey: "portalURL") }
    }

    /// Time zone the timestamps in imported CSV files are written in.
    @Published var importTimeZoneID: String {
        didSet { defaults.set(importTimeZoneID, forKey: "importTimeZone") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        portalURL = defaults.string(forKey: "portalURL") ?? AppSettings.defaultPortalURL
        importTimeZoneID = defaults.string(forKey: "importTimeZone") ?? TimeZone.current.identifier
    }

    var importTimeZone: TimeZone {
        TimeZone(identifier: importTimeZoneID) ?? .current
    }

    var resolvedPortalURL: URL {
        let trimmed = portalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme) ?? URL(string: AppSettings.defaultPortalURL)!
    }
}
