import XCTest
@testable import TibidleCore

final class CoreTests: XCTestCase {
    func testTabOrderMove() {
        var order = [0, 1, 2, 3]
        TabOrder.move(&order, account: 3, onto: 0)
        XCTAssertEqual(order, [3, 0, 1, 2])
        TabOrder.move(&order, account: 3, onto: 2)
        XCTAssertEqual(order, [0, 1, 2, 3])
        TabOrder.move(&order, account: 1, onto: 1)
        XCTAssertEqual(order, [0, 1, 2, 3])
    }

    func testNormalizeRepairsBrokenSettings() throws {
        let json = #"{"accounts":[{"name":"  Knight  "},{"name":""}],"selectedTab":9,"tabOrder":[2,2,7,-1]}"#
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        settings.normalize()
        XCTAssertEqual(settings.accounts.map(\.name), ["Knight", "Conta 2", "Conta 3", "Conta 4"])
        XCTAssertEqual(settings.selectedTab, 3)
        XCTAssertEqual(settings.tabOrder, [2, 0, 1, 3])
    }

    func testNameIsTruncated() {
        var settings = AppSettings()
        settings.accounts = [AccountSettings(name: String(repeating: "x", count: 40))]
        settings.normalize()
        XCTAssertEqual(settings.accounts[0].name.count, AppSettings.maxNameLength)
    }

    func testStoreRoundTripAndCorruptFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(root: root)
        var settings = store.load()
        settings.accounts[1].name = "Druid"
        settings.accounts[2].muted = true
        settings.gridView = true
        settings.tabOrder = [3, 2, 1, 0]
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)

        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load().accounts.map(\.name), ["Conta 1", "Conta 2", "Conta 3", "Conta 4"])
    }

    func testProfileIdentifiersAreStableAndUnique() {
        XCTAssertEqual(Set(ProfileIdentity.identifiers).count, accountCount)
    }

    func testLayout() {
        let bounds = CGRect(x: 0, y: 0, width: 1006, height: 806)
        let single = BrowserLayout.frames(count: 4, in: bounds, grid: false, selectedPosition: 2)
        XCTAssertEqual(single.compactMap { $0 }.count, 1)
        XCTAssertEqual(single[2], bounds)

        let grid = BrowserLayout.frames(count: 4, in: bounds, grid: true, selectedPosition: 0).map { $0! }
        XCTAssertEqual(grid[0], CGRect(x: 6, y: 406, width: 494, height: 394)) // top-left
        XCTAssertEqual(grid[1], CGRect(x: 506, y: 406, width: 494, height: 394)) // top-right
        XCTAssertEqual(grid[2], CGRect(x: 6, y: 6, width: 494, height: 394)) // bottom-left
        XCTAssertEqual(grid[3], CGRect(x: 506, y: 6, width: 494, height: 394)) // bottom-right
    }
}
