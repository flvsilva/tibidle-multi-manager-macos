import JavaScriptCore
import XCTest
@testable import TibidleCore

final class CollectorScriptTests: XCTestCase {
    /// Runs the collector against a fake browser: a WebSocket stub and a message handler that records posts.
    private func makeContext(hostname: String = "play.tibidle.com") -> (JSContext, () -> [[String: Any]]) {
        let context = JSContext()!
        context.exceptionHandler = { _, error in XCTFail("JS error: \(error?.toString() ?? "")") }
        context.evaluateScript("""
            var window = globalThis;
            var posts = [];
            var location = { hostname: '\(hostname)', href: 'https://\(hostname)/' };
            var webkit = { messageHandlers: { \(CollectorScript.handlerName): { postMessage: (m) => posts.push(m) } } };
            class URL { constructor(u) { this.hostname = /^wss?:\\/\\/([^\\/:]+)/.exec(u)[1]; } }
            var now = 1000000; Date.now = () => now;
            class FakeSocket {
              constructor(url) { this.url = url; this.listeners = {}; this.sent = []; }
              addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); }
              send(m) { this.sent.push(m); }
              receive(data) { (this.listeners.message || []).forEach((f) => f({ data })); }
              close() { (this.listeners.close || []).forEach((f) => f({})); }
            }
            FakeSocket.OPEN = 1;
            window.WebSocket = FakeSocket;
            """)
        context.evaluateScript(CollectorScript.source)
        let posts = { () -> [[String: Any]] in
            (context.evaluateScript("posts")!.toArray() as? [String] ?? []).compactMap {
                try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            }
        }
        return (context, posts)
    }

    func testForwardsOnlyWhitelistedFields() {
        let (context, posts) = makeContext()
        context.evaluateScript("""
            var ws = new WebSocket('wss://play.tibidle.com/ws');
            ws.receive(JSON.stringify({ type: 'welcome', data: { worldToken: 'SECRET', account: { name: 'Main', level: 10,
              premiumUntil: 1, email: 'x@y' }, roster: [{ name: 'Knight', level: 10, vocation: 'knight', equipment: {} }] } }));
            ws.receive(JSON.stringify({ type: 'resume', data: { huntId: 7, worldToken: 'SECRET', meta: {}, analyzer: { xp: '100',
              xpPerHour: 50, elapsedMs: 1000, secret: 1 }, offline: { elapsedMs: 5, xp: '1' }, state: { character: { name: 'Knight',
              equipment: { a: 1 } }, inventory: [1] } } }));
            ws.receive(JSON.stringify({ type: 'chat_message', data: { text: 'hello' } }));
            ws.receive('not json');
            """)
        let all = posts()
        XCTAssertEqual(all.map { $0["type"] as? String }, ["welcome", "resume"])
        let text = all.map { String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined()
        for forbidden in ["SECRET", "worldToken", "premiumUntil", "email", "equipment", "inventory", "meta", "secret", "hello"] {
            XCTAssertFalse(text.contains(forbidden), "\(forbidden) leaked")
        }
        let welcome = all[0]["data"] as! [String: Any]
        XCTAssertEqual((welcome["account"] as! [String: Any])["name"] as? String, "Main")
        let resume = all[1]["data"] as! [String: Any]
        XCTAssertEqual((resume["analyzer"] as! [String: Any])["xpPerHour"] as? Int, 50)
    }

    func testForwardsInvasionScheduleOnly() {
        let (context, posts) = makeContext()
        context.evaluateScript("""
            var ws = new WebSocket('wss://play.tibidle.com/ws');
            ws.receive(JSON.stringify({ type: 'welcome', data: { worldToken: 'SECRET', meta: { rules: { store: [1] }, invasao: {
              date: 'd', invasionNome: 'Cerco', bossName: 'Boss', inscrito: false, encerrada: false, premio: 'x',
              janelas: [{ idx: 1, startAtMs: 5, estado: 'preparando', windowId: 'secret-id' }] } } } }));
            """)
        let welcome = posts()[0]["data"] as! [String: Any]
        let invasion = welcome["invasao"] as! [String: Any]
        XCTAssertEqual(invasion["inscrito"] as? Bool, false)
        XCTAssertEqual(((invasion["janelas"] as! [[String: Any]])[0])["startAtMs"] as? Int, 5)
        let text = String(data: try! JSONSerialization.data(withJSONObject: welcome), encoding: .utf8)!
        for forbidden in ["SECRET", "windowId", "premio", "rules", "store"] { XCTAssertFalse(text.contains(forbidden), "\(forbidden) leaked") }
    }

    func testThrottlesFramesAndReportsClose() {
        let (context, posts) = makeContext()
        context.evaluateScript("""
            var ws = new WebSocket('wss://play.tibidle.com/ws');
            var frame = JSON.stringify({ type: 'frame', data: { analyzer: { xp: '1' }, state: {}, events: [] } });
            ws.receive(frame); now += 1000; ws.receive(frame); now += 2500; ws.receive(frame);
            ws.close();
            """)
        XCTAssertEqual(posts().map { $0["type"] as? String }, ["frame", "frame", "_closed"])
    }

    func testDoesNotTouchOutgoingMessagesOrOtherSites() {
        let (context, posts) = makeContext()
        context.evaluateScript("""
            var ws = new WebSocket('wss://play.tibidle.com/ws');
            ws.send('{"type":"auth","data":{"token":"T"}}');
            var other = new WebSocket('wss://example.com/ws');
            other.receive(JSON.stringify({ type: 'welcome', data: {} }));
            """)
        XCTAssertTrue(posts().isEmpty)
        XCTAssertEqual(context.evaluateScript("ws instanceof WebSocket && ws.sent.length === 1 && WebSocket.OPEN === 1").toBool(), true)
    }

    func testInactiveOutsideTheGame() {
        let (context, posts) = makeContext(hostname: "accounts.google.com")
        context.evaluateScript("new WebSocket('wss://play.tibidle.com/ws').receive(JSON.stringify({ type: 'welcome', data: {} }))")
        XCTAssertTrue(posts().isEmpty)
    }
}

final class DashboardStoreTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> DashboardStore { DashboardStore(databaseURL: nil, now: { [unowned self] in clock }) }

    private func object(_ data: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: data) as! [String: Any] }

    func testHuntLifecycle() {
        let store = makeStore()
        store.setAccountNames(["A", "B", "C", "D"])
        store.ingest(account: 1, json: #"{"type":"welcome","data":{"account":{"name":"Main","level":5}}}"#)
        store.ingest(account: 1, json: #"{"type":"hunt_started","data":{"huntId":9,"state":{"party":[{"name":"Knight"},{"name":"Druid"}]}}}"#)
        for minute in 0..<3 {
            clock += 60
            store.ingest(account: 1, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":\#((minute + 1) * 60000),"xpPerHour":1200,"lootGold":600,"suppliesGold":100,"xp":"20"}}}"#)
            clock += 5
            store.ingest(account: 1, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":1,"xpPerHour":1}}}"#) // throttled sample
        }
        let state = object(store.stateJSON())
        let account = (state["accounts"] as! [[String: Any]])[1]
        XCTAssertEqual(account["status"] as? String, "hunting")
        XCTAssertEqual(account["label"] as? String, "B")

        let history = object(store.historyJSON(hours: 1))
        let series = (history["series"] as! [String: [[Double]]])["1"]!
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0][1], 1200)       // xp/h
        XCTAssertEqual(series[0][2], 36000)      // 600 / (1/60 h)
        XCTAssertEqual(series[0][3], 30000)      // (600 - 100) / (1/60 h)

        store.ingest(account: 1, json: #"{"type":"ended","data":{"summary":{"huntId":9,"reason":"death","balance":500,"deaths":1}}}"#)
        store.ingest(account: 1, json: #"{"type":"ended","data":{"summary":{"huntId":9,"reason":"death","balance":500,"deaths":1}}}"#)
        let hunts = object(store.huntsJSON(limit: 10))["hunts"] as! [[String: Any]]
        XCTAssertEqual(hunts.count, 1)
        XCTAssertEqual(hunts[0]["characters"] as? [String], ["Knight", "Druid"])
        XCTAssertEqual((hunts[0]["members"] as? [[String: Any]])?.map { $0["name"] as? String }, ["Knight", "Druid"])
        XCTAssertEqual(hunts[0]["label"] as? String, "B")
        let after = (object(store.stateJSON())["accounts"] as! [[String: Any]])[1]
        XCTAssertEqual(after["status"] as? String, "city")
        XCTAssertNotNil(after["lastSummary"])

        store.ingest(account: 1, json: #"{"type":"_closed","data":{}}"#)
        XCTAssertEqual((object(store.stateJSON())["accounts"] as! [[String: Any]])[1]["status"] as? String, "offline")
    }

    func testLevelBenchmarkComparesNearbyLevelsOnTheSameMap() {
        let store = makeStore()
        store.setAccountNames(["A", "B", "C", "D"])
        func finish(_ account: Int, hunt: Int, levels: (Int, Int), seconds: Int, balance: Int) {
            store.ingest(account: account, json: #"{"type":"hunt_started","data":{"huntId":\#(hunt)}}"#)
            clock += 1
            store.ingest(account: account, json: #"{"type":"ended","data":{"summary":{"huntId":\#(hunt),"elapsedSec":\#(seconds),"level":{"start":\#(levels.0),"end":\#(levels.1)},"balance":\#(balance),"suppliesGold":\#(seconds),"killsTotal":\#(seconds)}}}"#)
        }
        finish(1, hunt: 151, levels: (79, 80), seconds: 7200, balance: 100_000)   // counts: B near level 80
        finish(1, hunt: 151, levels: (80, 80), seconds: 3600, balance: 50_000)    // counts
        finish(1, hunt: 151, levels: (90, 91), seconds: 7200, balance: 999_999)   // too far from level 80
        finish(1, hunt: 151, levels: (80, 80), seconds: 600, balance: 999_999)    // too short
        finish(1, hunt: 7, levels: (80, 80), seconds: 7200, balance: 999_999)     // another map
        finish(2, hunt: 151, levels: (81, 82), seconds: 3600, balance: 20_000)    // C, counts
        store.ingest(account: 2, json: #"{"type":"hunt_started","data":{"huntId":151,"state":{"character":{"level":80}}}}"#)

        let account = (object(store.stateJSON())["accounts"] as! [[String: Any]])[2]
        let benchmark = account["benchmark"] as! [String: Any]
        XCTAssertEqual(benchmark["level"] as? Int, 80)
        let rows = benchmark["rows"] as! [[String: Any]]
        XCTAssertEqual(rows.map { $0["label"] as? String }, ["B", "C"])
        XCTAssertEqual(rows[0]["runs"] as? Int, 2)
        XCTAssertEqual(rows[0]["profitPerHour"] as? Int, 50_000)    // 150k over 3h
        XCTAssertEqual(rows[0]["levels"] as? String, "79–80")
        XCTAssertEqual(rows[0]["suppliesPerHour"] as? Int, 3600)
        XCTAssertEqual(rows[1]["profitPerHour"] as? Int, 20_000)
    }

    func testHuntKeepsItsBattleSetupAndComparesWithAnother() {
        let store = makeStore()
        let party = #"{"party":[{"name":"Zolp","vocation":"DRUID","level":80,"suppliesGold":900}]}"#
        store.ingest(account: 2, json: #"{"type":"welcome","data":{"battleConfigs":{"DRUID":{"skills":["Ice Strike"],"heals":[{"name":"Exura Vita","percent":60}],"manaPotion":{"name":"Strong Mana Potion","percent":30}}}}}"#)
        store.ingest(account: 2, json: #"{"type":"hunt_started","data":{"huntId":151,"state":\#(party)}}"#)
        store.ingest(account: 2, json: #"{"type":"ended","data":{"summary":{"huntId":151,"elapsedSec":3600,"balance":10}}}"#)
        clock += 60
        store.ingest(account: 2, json: #"{"type":"resume","data":{"huntId":151,"state":\#(party),"battleConfigs":{"DRUID":{"skills":["Ice Strike"],"heals":[{"name":"Exura Vita","percent":90}],"manaPotion":{"name":"Strong Mana Potion","percent":30}}}}}"#)
        store.ingest(account: 2, json: #"{"type":"ended","data":{"summary":{"huntId":151,"elapsedSec":3600,"balance":20}}}"#)

        let hunts = object(store.huntsJSON(limit: 10))["hunts"] as! [[String: Any]]
        XCTAssertEqual(hunts.count, 2)
        XCTAssertEqual(hunts.map { $0["hasSetup"] as? Bool }, [true, true])
        XCTAssertNil(hunts[0]["setup"], "the setup itself stays out of the hunts list")
        let newer = hunts[0]["id"] as! Int, older = hunts[1]["id"] as! Int

        let result = object(store.huntSetup(id: newer, compare: older))
        let druid = (result["vocations"] as! [[String: Any]]).first!
        XCTAssertEqual(druid["label"] as? String, "Druid")
        XCTAssertEqual(druid["differences"] as? [String], ["Exura Vita: cura abaixo de 90% de vida (era 60%)"])
        XCTAssertTrue((druid["steps"] as! [String]).contains("Cura 1: Exura Vita abaixo de 90% de vida"))
        XCTAssertNotNil(object(store.huntSetup(id: 9999, compare: nil))["error"])
        XCTAssertEqual(DashboardRouter.respond(method: "GET", target: "/api/hunts/setup?id=\(newer)&compare=\(older)", store: store).status, 200)
    }

    func testInsightsCompareWithTheBestRecentHuntAndItsSetup() {
        let store = makeStore()
        store.setAccountNames(["A", "B", "C", "D"])
        func config(_ minimum: Int) -> String {
            #"{"SORCERER":{"skills":["Energy Wave"],"minCreatures":{"Energy Wave":\#(minimum)}}}"#
        }
        func hunt(minimum: Int, seconds: Int, balance: Int, level: Int = 80, map: Int = 151) {
            store.ingest(account: 1, json: #"{"type":"welcome","data":{"battleConfigs":\#(config(minimum))}}"#)
            store.ingest(account: 1, json: #"{"type":"hunt_started","data":{"huntId":\#(map),"state":{"party":[{"name":"B","vocation":"SORCERER","level":80}]}}}"#)
            clock += 60
            store.ingest(account: 1, json: #"{"type":"ended","data":{"summary":{"huntId":\#(map),"elapsedSec":\#(seconds),"level":{"start":\#(level),"end":\#(level)},"balance":\#(balance)}}}"#)
        }
        hunt(minimum: 2, seconds: 7200, balance: 160_000)               // best: 80k/h
        hunt(minimum: 3, seconds: 3600, balance: 50_000)
        hunt(minimum: 2, seconds: 3600, balance: 999_999, level: 95)    // too far from the current level
        hunt(minimum: 2, seconds: 3600, balance: 999_999, map: 7)       // another map
        store.ingest(account: 1, json: #"{"type":"welcome","data":{"battleConfigs":\#(config(5))}}"#)
        store.ingest(account: 1, json: #"{"type":"hunt_started","data":{"huntId":151,"state":{"character":{"level":81},"party":[{"name":"B","vocation":"SORCERER","level":81}]}}}"#)
        store.ingest(account: 1, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":3600000,"lootGold":90000,"suppliesGold":50000}}}"#)

        let state = object(store.stateJSON())
        let insights = (state["accounts"] as! [[String: Any]])[1]["insights"] as! [String: Any]
        XCTAssertEqual((insights["reference"] as! [String: Any])["profitPerHour"] as? Int, 80_000)
        XCTAssertEqual(insights["profitPerHour"] as? Int, 40_000)
        XCTAssertEqual(insights["drop"] as? Double, 0.5)
        let changes = insights["changes"] as! [[String: Any]]
        XCTAssertEqual(changes.first?["differences"] as? [String], ["Energy Wave: mínimo de criaturas de 2 para 5"])
        let attention = state["attention"] as! [[String: Any]]
        XCTAssertTrue(attention.contains { ($0["text"] as? String)?.contains("50% abaixo da sua melhor hunt recente aqui (80k/h") == true })

        // Too early in the hunt to judge the rates: the comparison shows, the warning does not.
        store.ingest(account: 1, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":600000,"lootGold":1,"suppliesGold":50000}}}"#)
        let early = object(store.stateJSON())
        XCTAssertNil(((early["accounts"] as! [[String: Any]])[1]["insights"] as! [String: Any])["drop"])
        XCTAssertFalse((early["attention"] as! [[String: Any]]).contains { $0["kind"] as? String == "setup" })
    }

    func testRejectsInvalidInput() {
        let store = makeStore()
        store.ingest(account: 7, json: #"{"type":"welcome","data":{}}"#)
        store.ingest(account: 0, json: "garbage")
        store.ingest(account: 0, json: #"{"type":"unknown","data":{}}"#)
        store.ingest(account: 0, json: #"{"type":"welcome","data":{"x":""# + String(repeating: "a", count: DashboardStore.maxMessageBytes) + #""}}"#)
        let accounts = object(store.stateJSON())["accounts"] as! [[String: Any]]
        XCTAssertEqual(accounts.map { $0["status"] as? String }, ["offline", "offline", "offline", "offline"])
    }

    func testHistoryPersistsInDatabase() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("d.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let store = DashboardStore(databaseURL: url, now: { [unowned self] in clock })
            store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":1,"balance":5}}}"#)
        }
        let reopened = DashboardStore(databaseURL: url, now: { [unowned self] in clock })
        XCTAssertEqual((object(reopened.huntsJSON(limit: 5))["hunts"] as! [[String: Any]]).count, 1)
    }

    func testRouter() {
        let store = makeStore()
        XCTAssertEqual(DashboardRouter.respond(method: "GET", target: "/", store: store).contentType, "text/html; charset=utf-8")
        XCTAssertEqual(DashboardRouter.respond(method: "GET", target: "/api/state", store: store).status, 200)
        XCTAssertEqual(DashboardRouter.respond(method: "GET", target: "/api/history?hours=99999", store: store).status, 200)
        XCTAssertEqual(DashboardRouter.respond(method: "POST", target: "/api/state", store: store).status, 405)
        XCTAssertEqual(DashboardRouter.respond(method: "GET", target: "/../etc/passwd", store: store).status, 404)
        let head = String(decoding: DashboardRouter.respond(method: "GET", target: "/api/state", store: store).serialized(), as: UTF8.self)
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
    }
}
