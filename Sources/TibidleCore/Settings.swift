import Foundation

public let accountCount = 4

public struct AccountSettings: Codable, Equatable {
    public var name: String
    public var muted: Bool
    /// Page zoom per pane size (`PaneSize.rawValue`): a small pane of the 1 + 3 view needs less than the same account alone.
    public var zoom: [String: Double]

    public init(name: String, muted: Bool = false, zoom: [String: Double] = [:]) {
        self.name = name
        self.muted = muted
        self.zoom = zoom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
        zoom = (try? c.decodeIfPresent([String: Double].self, forKey: .zoom)) ?? [:]
    }

    public static let zoomRange: ClosedRange<Double> = 0.3...3

    public func zoom(for size: PaneSize) -> Double { zoom[size.rawValue] ?? 1 }
}

/// How big an account's pane is in the current view; each keeps its own zoom.
public enum PaneSize: String, CaseIterable {
    case full      // Tela normal
    case main      // the large pane of 1 + 3
    case side      // the small panes of 1 + 3
    case quarter   // 4 telas

    public static func of(position: Int, in layout: ViewLayout) -> PaneSize {
        switch layout {
        case .single: return .full
        case .featured: return position == 0 ? .main : .side
        case .grid: return .quarter
        }
    }
}

/// How the account panes share the window. The case order is the order of the buttons and of ⇧⌘G.
public enum ViewLayout: String, Codable, CaseIterable {
    /// Only the selected account, full size.
    case single
    /// The first account in tab order large on the left, the other three stacked on the right.
    case featured
    /// 2 × 2 grid.
    case grid
}

public struct AppSettings: Codable, Equatable {
    public var accounts: [AccountSettings]
    public var selectedTab: Int
    public var layout: ViewLayout
    public var tabOrder: [Int]
    /// Pages drawn in sRGB instead of the display's color profile (less color conversion for the GPU on some monitors).
    public var srgbColors: Bool
    /// Other devices on the network can open the dashboard; off, only this Mac can.
    public var dashboardOnNetwork: Bool

    public init() {
        accounts = []
        selectedTab = 0
        layout = .single
        tabOrder = Array(0..<accountCount)
        srgbColors = false
        dashboardOnNetwork = true
    }

    /// Settings saved before `layout` existed only had the grid on or off.
    private enum LegacyKeys: String, CodingKey { case gridView }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = (try? c.decodeIfPresent([AccountSettings].self, forKey: .accounts)) ?? []
        selectedTab = (try? c.decodeIfPresent(Int.self, forKey: .selectedTab)) ?? 0
        if let saved = try? c.decodeIfPresent(ViewLayout.self, forKey: .layout) {
            layout = saved
        } else {
            let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
            layout = (try? legacy?.decodeIfPresent(Bool.self, forKey: .gridView)) == true ? .grid : .single
        }
        tabOrder = (try? c.decodeIfPresent([Int].self, forKey: .tabOrder)) ?? []
        srgbColors = (try? c.decodeIfPresent(Bool.self, forKey: .srgbColors)) ?? false
        dashboardOnNetwork = (try? c.decodeIfPresent(Bool.self, forKey: .dashboardOnNetwork)) ?? true
    }

    /// Fills missing accounts, trims names and repairs the tab order and selection.
    public mutating func normalize() {
        accounts = (0..<accountCount).map { i in
            var account = i < accounts.count ? accounts[i] : AccountSettings(name: "")
            let trimmed = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            account.name = trimmed.isEmpty ? "Conta \(i + 1)" : String(trimmed.prefix(Self.maxNameLength))
            account.zoom = account.zoom.filter { PaneSize(rawValue: $0.key) != nil && $0.value.isFinite }
                .mapValues { min(max($0, AccountSettings.zoomRange.lowerBound), AccountSettings.zoomRange.upperBound) }
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
