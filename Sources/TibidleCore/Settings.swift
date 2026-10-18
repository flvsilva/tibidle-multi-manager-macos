import Foundation

public let accountCount = 4

public struct AccountSettings: Codable, Equatable {
    public var name: String
    public var muted: Bool

    public init(name: String, muted: Bool = false) {
        self.name = name
        self.muted = muted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
    }
}

public struct AppSettings: Codable, Equatable {
    public var accounts: [AccountSettings]
    public var selectedTab: Int
    public var gridView: Bool
    public var tabOrder: [Int]

    public init() {
        accounts = []
        selectedTab = 0
        gridView = false
        tabOrder = Array(0..<accountCount)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = (try? c.decodeIfPresent([AccountSettings].self, forKey: .accounts)) ?? []
        selectedTab = (try? c.decodeIfPresent(Int.self, forKey: .selectedTab)) ?? 0
        gridView = (try? c.decodeIfPresent(Bool.self, forKey: .gridView)) ?? false
        tabOrder = (try? c.decodeIfPresent([Int].self, forKey: .tabOrder)) ?? []
    }

    /// Fills missing accounts, trims names and repairs the tab order and selection.
    public mutating func normalize() {
        accounts = (0..<accountCount).map { i in
            var account = i < accounts.count ? accounts[i] : AccountSettings(name: "")
            let trimmed = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            account.name = trimmed.isEmpty ? "Conta \(i + 1)" : String(trimmed.prefix(Self.maxNameLength))
            return account
        }
        selectedTab = min(max(selectedTab, 0), accountCount - 1)
        var seen = Set<Int>()
        tabOrder = (tabOrder.filter { (0..<accountCount).contains($0) } + Array(0..<accountCount))
            .filter { seen.insert($0).inserted }
    }

    public static let maxNameLength = 24
}

/// Fixed browser profile identifiers. Renaming or reordering an account never changes them,
/// so the login stored in each profile always stays with the same account slot.
public enum ProfileIdentity {
    public static let identifiers: [UUID] = [
        "7A1B0C01-5D1E-4B6A-9E00-000000000001",
        "7A1B0C01-5D1E-4B6A-9E00-000000000002",
        "7A1B0C01-5D1E-4B6A-9E00-000000000003",
        "7A1B0C01-5D1E-4B6A-9E00-000000000004",
    ].map { UUID(uuidString: $0)! }
}

public struct SettingsStore {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TibidleMultiManager", isDirectory: true)
    }

    public var fileURL: URL { root.appendingPathComponent("settings.json") }

    public func load() -> AppSettings {
        var settings = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        settings.normalize()
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
