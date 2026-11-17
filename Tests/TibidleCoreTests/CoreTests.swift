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
        settings.layout = .featured
        settings.tabOrder = [3, 2, 1, 0]
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)

        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load().accounts.map(\.name), ["Conta 1", "Conta 2", "Conta 3", "Conta 4"])
    }

    func testProfileIdentifiersAreStableAndUnique() {
        XCTAssertEqual(Set(ProfileIdentity.identifiers).count, accountCount)
    }

    func testLegacyGridSettingBecomesLayout() throws {
        let decode = { (json: String) in try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).layout }
        XCTAssertEqual(try decode(#"{"gridView":true}"#), .grid)
        XCTAssertEqual(try decode(#"{"gridView":false}"#), .single)
        XCTAssertEqual(try decode(#"{}"#), .single)
        XCTAssertEqual(try decode(#"{"gridView":true,"layout":"featured"}"#), .featured)
        XCTAssertEqual(try decode(#"{"gridView":true,"layout":"bogus"}"#), .grid)
    }

    func testLayout() {
        let bounds = CGRect(x: 0, y: 0, width: 1006, height: 806)
        let single = BrowserLayout.frames(count: 4, in: bounds, layout: .single, selectedPosition: 2)
        XCTAssertEqual(single.compactMap { $0 }.count, 1)
        XCTAssertEqual(single[2], bounds)

        let grid = BrowserLayout.frames(count: 4, in: bounds, layout: .grid, selectedPosition: 0).map { $0! }
        XCTAssertEqual(grid[0], CGRect(x: 6, y: 406, width: 494, height: 394)) // top-left
        XCTAssertEqual(grid[1], CGRect(x: 506, y: 406, width: 494, height: 394)) // top-right
        XCTAssertEqual(grid[2], CGRect(x: 6, y: 6, width: 494, height: 394)) // bottom-left
        XCTAssertEqual(grid[3], CGRect(x: 506, y: 6, width: 494, height: 394)) // bottom-right

        // 1 + 3: 1200 of width after the gaps, 800 for the main pane and 400 for the column.
        let wide = CGRect(x: 0, y: 0, width: 1218, height: 810)
        let featured = BrowserLayout.frames(count: 4, in: wide, layout: .featured, selectedPosition: 3).map { $0! }
        XCTAssertEqual(featured[0], CGRect(x: 6, y: 6, width: 800, height: 798)) // main, full height
        XCTAssertEqual(featured[1], CGRect(x: 812, y: 542, width: 400, height: 262)) // top-right
        XCTAssertEqual(featured[2], CGRect(x: 812, y: 274, width: 400, height: 262))
        XCTAssertEqual(featured[3], CGRect(x: 812, y: 6, width: 400, height: 262)) // bottom-right
    }
}
