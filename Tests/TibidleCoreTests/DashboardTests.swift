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
        XCTAssertEqual(hunts[0]["label"] as? String, "B")
        let after = (object(store.stateJSON())["accounts"] as! [[String: Any]])[1]
        XCTAssertEqual(after["status"] as? String, "city")
        XCTAssertNotNil(after["lastSummary"])

        store.ingest(account: 1, json: #"{"type":"_closed","data":{}}"#)
        XCTAssertEqual((object(store.stateJSON())["accounts"] as! [[String: Any]])[1]["status"] as? String, "offline")
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
