import JavaScriptCore
import SQLite3
import XCTest
@testable import TibidleCore

private let catalogJSON = """
{"spriteVer":1,"hunts":[
 {"id":10,"title":"Dragon Lair","island":"a","monsters":["Dragon","Dragon Hatchling"]},
 {"id":11,"title":"Dragon Lord Cave","island":"a","monsters":["Dragon","Dragon Lord"]},
 {"id":12,"title":"Rat Hole","island":"b","monsters":["Rat","Cave Rat"]},
 {"id":13,"title":"Mixed Ruins","island":"b","monsters":["Rat","Dragon Hatchling"]}]}
"""

private func eventos(progress: Int = 0, claimed: Bool = false, kind: String = "monster", targets: [String] = ["Dragon"],
                     title: String = "Caçada: Dragon Lair") -> [String: Any] {
    ["serverDay": "2026-10-18", "nextDailyResetAt": 1_900_000_000_000,
     "diarias": ["slots": [
        ["id": "t1", "title": title, "kind": kind, "quantity": 100, "progresso": progress, "resgatado": claimed,
         "targets": targets, "rewards": [["kind": "coins", "amount": 5]]],
        NSNull(),
     ]],
     "semanais": ["concluidas": 2, "necessarias": 5]]
}

final class HuntCatalogTests: XCTestCase {
    private let catalog = HuntCatalog(json: Data(catalogJSON.utf8))!

    func testParsesAndRejectsGarbage() {
        XCTAssertEqual(catalog.hunts.count, 4)
        XCTAssertEqual(catalog.hunt(id: 12)?.title, "Rat Hole")
        XCTAssertNil(HuntCatalog(json: Data("{}".utf8)))
        XCTAssertNil(HuntCatalog(json: Data("<html>".utf8)))
    }

    func testCandidatesPreferFullMatchesAndTitleHint() {
        let hint = catalog.candidates(targets: ["dragon"], missionTitle: "Caçada: Dragon Lord Cave")
        XCTAssertEqual(hint.map(\.hunt.id), [11, 10])
        XCTAssertTrue(hint.allSatisfy(\.full))
        let both = catalog.candidates(targets: ["Dragon", "Dragon Lord"], missionTitle: "x")
        XCTAssertEqual(both.map(\.hunt.id), [11])
        let partial = catalog.candidates(targets: ["Rat", "Dragon Hatchling"], missionTitle: "x")
        XCTAssertEqual(partial.map(\.hunt.id), [13])
        let none = catalog.candidates(targets: ["Rat", "Orc"], missionTitle: "x")
        XCTAssertEqual(none.map(\.hunt.id), [12, 13])
        XCTAssertFalse(none[0].full)
        XCTAssertTrue(catalog.candidates(targets: ["Unicorn"], missionTitle: "x").isEmpty)
    }
}

final class MissionAdvisorTests: XCTestCase {
    private let catalog = HuntCatalog(json: Data(catalogJSON.utf8))!

    private func state(_ e: [String: Any], hunting: Bool = true, huntId: Int? = 10, live: [String: Any]? = nil,
                       training: Bool = false) -> [String: Any] {
        let result = MissionAdvisor.evaluate(eventos: e, live: live, hunting: hunting, training: training,
                                             currentHuntId: huntId, catalog: catalog)
        return (result["missions"] as! [[String: Any]])[0]
    }

    func testStates() {
        XCTAssertEqual(state(eventos())["state"] as? String, "on_track")
        XCTAssertEqual(state(eventos(), huntId: 12)["state"] as? String, "off_track")
        XCTAssertEqual(state(eventos(), huntId: 1)["state"] as? String, "no_count")      // tower / elite / boss: not in the regular list
        XCTAssertEqual(state(eventos(), hunting: false)["state"] as? String, "pending")
        XCTAssertEqual(state(eventos(), training: true)["state"] as? String, "pending")
        XCTAssertEqual(state(eventos(progress: 100))["state"] as? String, "ready")
        XCTAssertEqual(state(eventos(progress: 100, claimed: true))["state"] as? String, "claimed")
        XCTAssertEqual(state(eventos(kind: "refinar"))["state"] as? String, "forge")
        XCTAssertEqual(state(eventos(kind: "elite", targets: ["Ferumbras"]))["state"] as? String, "elite")
    }

    func testLiveProgressOnlyCountsForTheSameDay() {
        let live: [String: Any] = ["serverDay": "2026-10-18", "slots": ["t1": 64.0]]
        XCTAssertEqual(state(eventos(progress: 10), live: live)["progress"] as? Int, 64)
        XCTAssertEqual(state(eventos(progress: 70), live: live)["progress"] as? Int, 70)
        let stale: [String: Any] = ["serverDay": "2026-10-17", "slots": ["t1": 90.0]]
        XCTAssertEqual(state(eventos(progress: 10), live: stale)["progress"] as? Int, 10)
    }

    func testExtras() {
        let result = MissionAdvisor.evaluate(eventos: eventos(), live: nil, hunting: true, training: false,
                                             currentHuntId: 10, catalog: catalog)
        XCTAssertEqual((result["currentHunt"] as? [String: Any])?["title"] as? String, "Dragon Lair")
        XCTAssertEqual(result["dailyResetAt"] as? Double, 1_900_000_000_000)
        XCTAssertEqual((result["weekly"] as? [String: Int])?["done"], 2)
        var seconds = eventos(); seconds["nextDailyResetAt"] = 1_900_000_000
        XCTAssertEqual(MissionAdvisor.evaluate(eventos: seconds, live: nil, hunting: false, training: false,
                                               currentHuntId: nil, catalog: catalog)["dailyResetAt"] as? Double, 1_900_000_000_000)
    }
}

final class MissionStoreTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private func makeStore() -> DashboardStore {
        let store = DashboardStore(databaseURL: nil, now: { [unowned self] in clock })
        store.setHuntCatalog(HuntCatalog(json: Data(catalogJSON.utf8))!)
        return store
    }
    private func account(_ store: DashboardStore, _ i: Int) -> [String: Any] {
        let root = try! JSONSerialization.jsonObject(with: store.stateJSON()) as! [String: Any]
        return (root["accounts"] as! [[String: Any]])[i]
    }
    private func hunts(_ store: DashboardStore) -> [[String: Any]] {
        (try! JSONSerialization.jsonObject(with: store.huntsJSON(limit: 50)) as! [String: Any])["hunts"] as! [[String: Any]]
    }

    func testMissionFlowFromGameMessages() {
        let store = makeStore()
        let slots = #"{"id":"t1","title":"Caçada: Dragon Lair","kind":"monster","quantity":100,"progresso":10,"resgatado":false,"targets":["Dragon"],"rewards":[]}"#
        store.ingest(account: 0, json: #"{"type":"welcome","data":{"eventos":{"serverDay":"2026-10-18","nextDailyResetAt":1900000000000,"diarias":{"slots":[\#(slots),null]}}}}"#)
        var daily = account(store, 0)["daily"] as! [String: Any]
        XCTAssertEqual((daily["missions"] as! [[String: Any]])[0]["state"] as? String, "pending")

        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":12,"state":{}}}"#)
        daily = account(store, 0)["daily"] as! [String: Any]
        XCTAssertEqual((daily["missions"] as! [[String: Any]])[0]["state"] as? String, "off_track")
        XCTAssertEqual(((daily["missions"] as! [[String: Any]])[0]["candidates"] as! [[String: Any]])[0]["title"] as? String, "Dragon Lair")

        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":10,"state":{}}}"#)
        store.ingest(account: 0, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":1},"eventosProgresso":{"dia":{"serverDay":"2026-10-18","slots":[{"taskId":"t1","exibido":55}]}}}}"#)
        let mission = ((account(store, 0)["daily"] as! [String: Any])["missions"] as! [[String: Any]])[0]
        XCTAssertEqual(mission["state"] as? String, "on_track")
        XCTAssertEqual(mission["progress"] as? Int, 55)

        // An authoritative update replaces the live estimate.
        store.ingest(account: 0, json: #"{"type":"eventos_state","data":{"eventos":{"serverDay":"2026-10-18","diarias":{"slots":[{"id":"t1","title":"x","kind":"monster","quantity":100,"progresso":100,"resgatado":false,"targets":["Dragon"]},null]}}}}"#)
        XCTAssertEqual((((account(store, 0)["daily"] as! [String: Any])["missions"]) as! [[String: Any]])[0]["state"] as? String, "ready")
        XCTAssertNil(account(store, 0)["missions"], "raw missions must not leak into the API")
    }

    func testRepeatingTheSameMapKeepsEveryRun() {
        let store = makeStore()
        for run in 1...3 {
            clock += 3600
            store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":10,"reason":"stop","elapsedSec":3600,"xp":"\#(run * 100)","lootGold":5,"suppliesGold":1,"killsTotal":\#(run),"balance":4}}}"#)
        }
        store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":10,"reason":"stop","elapsedSec":3600,"xp":"300","lootGold":5,"suppliesGold":1,"killsTotal":3,"balance":4}}}"#) // duplicate delivery
        let all = hunts(store)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first?["huntTitle"] as? String, "Dragon Lair")
    }

    func testMigratesTheOldHuntsTable() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("d.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, """
            CREATE TABLE hunts (account INTEGER, hunt_id INTEGER, ended_at REAL, summary TEXT, UNIQUE(account, hunt_id));
            INSERT INTO hunts VALUES (1, 45, 1799990000, '{"huntId":45,"reason":"stop","balance":7}');
            INSERT INTO hunts VALUES (2, 176, 1799990100, '{"huntId":176,"reason":"death","balance":-3}');
            """, nil, nil, nil)
        sqlite3_close(db)

        let store = DashboardStore(databaseURL: url, now: { [unowned self] in clock })
        XCTAssertEqual(hunts(store).count, 2)
        let reopened = DashboardStore(databaseURL: url, now: { [unowned self] in clock })
        XCTAssertEqual(hunts(reopened).count, 2, "migration must be idempotent")
        var check: OpaquePointer?
        sqlite3_open(url.path, &check)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(check, "SELECT count(*) FROM sqlite_master WHERE name='hunts'", -1, &statement, nil)
        sqlite3_step(statement)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
        sqlite3_finalize(statement); sqlite3_close(check)
    }
}

final class MissionCollectorTests: XCTestCase {
    func testOnlyDailyMissionFieldsPass() {
        let context = JSContext()!
        context.exceptionHandler = { _, e in XCTFail("JS error: \(e?.toString() ?? "")") }
        context.evaluateScript("""
            var window = globalThis, posts = [];
            var location = { hostname: 'play.tibidle.com', href: 'https://play.tibidle.com/' };
            var webkit = { messageHandlers: { \(CollectorScript.handlerName): { postMessage: (m) => posts.push(m) } } };
            class URL { constructor(u) { this.hostname = /^wss?:\\/\\/([^\\/:]+)/.exec(u)[1]; } }
            class FakeSocket { constructor(u) { this.l = {}; }
              addEventListener(t, f) { (this.l[t] = this.l[t] || []).push(f); }
              receive(d) { (this.l.message || []).forEach((f) => f({ data: d })); } }
            window.WebSocket = FakeSocket;
            """)
        context.evaluateScript(CollectorScript.source)
        context.evaluateScript("""
            var ws = new WebSocket('wss://play.tibidle.com/ws');
            var task = { id: 't1', title: 'Caçada: Dragon', kind: 'monster', quantity: 50, targets: ['Dragon'], progresso: 3,
              resgatado: false, rewards: [{ kind: 'item', itemId: 99, name: 'Gem', amount: 2 }, { kind: 'coins', amount: 5 }] };
            var ev = { serverDay: '2026-10-18', serverWeek: 'W', nextDailyResetAt: 1, nextWeeklyResetAt: 2,
              login: { janela: { dias: [1, 2] }, custoPerdido: 7 }, sequencia: { diaAtual: 3, fechados: 2, terminaEm: 4, custoRecuperar: 20, inicio: 'X',
                dias: [{ day: 1, estado: 'resgatado', premio: { itemId: 5 } }, { day: 2, estado: 'recuperar', data: 'D' }] },
              diarias: { slots: [task, null], custoReroll: 99 }, semanais: { tarefas: [{ id: 'monstros', progresso: 7, meta: 50, extra2: 1 }], concluidas: 1, necessarias: 5 },
              resgataveis: { total: 3 } };
            var st = { keyBagUsed: 2, keyBagMax: 5, keyBag: { 'Secret Key': 2 }, keyClock: { item: 'Secret Key', tierMs: 5, everyMs: 9, count: 1 },
              cap: { used: 1, total: 2 } };
            ws.receive(JSON.stringify({ type: 'welcome', data: { worldToken: 'SECRET', eventos: ev } }));
            ws.receive(JSON.stringify({ type: 'eventos_result', data: { requestId: 'r1', state: ev } }));
            ws.receive(JSON.stringify({ type: 'frame', data: { analyzer: {}, state: st, events: [],
              eventosProgresso: { dia: { serverDay: '2026-10-18', slots: [{ taskId: 't1', exibido: 9, extra: 1 }] }, semana: { serverWeek: 'W', monstros: 4 } } } }));
            """)
        let raw = context.evaluateScript("posts")!.toArray() as! [String]
        let messages = raw.map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        XCTAssertEqual(messages.map { $0["type"] as? String }, ["welcome", "eventos_result", "frame"])
        let joined = raw.joined()
        for forbidden in ["SECRET", "custoReroll", "custoPerdido", "login", "resgataveis", "itemId", "nextWeeklyResetAt", "serverWeek", "extra", "requestId", "premio", "Secret", "keyBag\"", "inicio"] {
            XCTAssertFalse(joined.contains(forbidden), "\(forbidden) leaked")
        }
        let welcome = (messages[0]["data"] as! [String: Any])["eventos"] as! [String: Any]
        let slot = ((welcome["diarias"] as! [String: Any])["slots"] as! [Any])[0] as! [String: Any]
        XCTAssertEqual(slot["targets"] as? [String], ["Dragon"])
        XCTAssertEqual(slot["progresso"] as? Int, 3)
        XCTAssertEqual(((welcome["semanais"] as! [String: Any])["concluidas"]) as? Int, 1)
        let frame = messages[2]["data"] as! [String: Any]
        let live = ((frame["eventosProgresso"] as! [String: Any])["dia"] as! [String: Any])["slots"] as! [[String: Any]]
        XCTAssertEqual(live[0]["exibido"] as? Int, 9)
        let streak = welcome["sequencia"] as! [String: Any]
        XCTAssertEqual(streak["diaAtual"] as? Int, 3)
        XCTAssertEqual((streak["dias"] as! [[String: Any]])[1]["estado"] as? String, "recuperar")
        let goal = ((welcome["semanais"] as! [String: Any])["tarefas"] as! [[String: Any]])[0]
        XCTAssertEqual(goal["meta"] as? Int, 50)
        let state = frame["state"] as! [String: Any]
        XCTAssertEqual(state["keyBagMax"] as? Int, 5)
        XCTAssertEqual((state["keyClock"] as! [String: Any])["everyMs"] as? Int, 9)
        XCTAssertEqual(((frame["eventosProgresso"] as! [String: Any])["semana"] as! [String: Any])["monstros"] as? Int, 4)
    }
}


final class MissionInsightsTests: XCTestCase {
    private let catalog = HuntCatalog(json: Data(catalogJSON.utf8))!
    private let now = 1_800_000_000_000.0

    private func evaluate(_ e: [String: Any], huntId: Int? = 10, analyzer: [String: Any]? = nil, weekLive: Double? = nil) -> [String: Any] {
        MissionAdvisor.evaluate(eventos: e, live: nil, hunting: true, training: false, currentHuntId: huntId,
                                catalog: catalog, analyzer: analyzer, weekLive: weekLive, now: now)
    }

    private func mission(_ r: [String: Any]) -> [String: Any] { (r["missions"] as! [[String: Any]])[0] }

    func testForecastSaysWhetherTheMissionEndsBeforeTheReset() {
        var e = eventos(progress: 20)
        // 120 Dragons in 1h → 120/h; 80 left → 40 min.
        let analyzer: [String: Any] = ["elapsedMs": 3_600_000, "kills": ["Dragon": 100, "Dragon Hatchling": 50]]
        e["nextDailyResetAt"] = now + 3_600_000
        var eta = mission(evaluate(e, analyzer: analyzer))["eta"] as! [String: Any]
        XCTAssertEqual(eta["perHour"] as? Int, 100)
        XCTAssertEqual(eta["etaMs"] as? Int, 2_880_000)
        XCTAssertEqual(eta["fits"] as? Bool, true)
        e["nextDailyResetAt"] = now + 1_800_000
        eta = mission(evaluate(e, analyzer: analyzer))["eta"] as! [String: Any]
        XCTAssertEqual(eta["fits"] as? Bool, false)
        XCTAssertNil(mission(evaluate(e, analyzer: ["elapsedMs": 30_000, "kills": ["Dragon": 3]]))["eta"])
        XCTAssertNil(mission(evaluate(eventos(progress: 100), analyzer: analyzer))["eta"])
    }

    func testHuntsOutsideTheCatalogDoNotCount() {
        XCTAssertEqual(mission(evaluate(eventos(), huntId: 1))["state"] as? String, "no_count")
        XCTAssertEqual(mission(evaluate(eventos(), huntId: nil))["state"] as? String, "unknown")
    }

    func testStreakWarnsWhenTheDayIsStillOpenNearTheReset() {
        var e = eventos(progress: 5)
        e["sequencia"] = ["diaAtual": 3, "fechados": 2, "custoRecuperar": 20,
                          "dias": [["day": 1, "estado": "resgatado"], ["day": 2, "estado": "recuperar"], ["day": 3, "estado": "hoje"]]]
        e["nextDailyResetAt"] = now + 3_600_000
        let streak = evaluate(e)["streak"] as! [String: Any]
        XCTAssertEqual(streak["day"] as? Int, 3)
        XCTAssertEqual(streak["toRecover"] as? Int, 1)
        XCTAssertEqual(streak["atRisk"] as? Bool, true)
        e["nextDailyResetAt"] = now + 10 * 3_600_000
        XCTAssertEqual((evaluate(e)["streak"] as! [String: Any])["atRisk"] as? Bool, false)
        e = eventos(progress: 100, claimed: true)
        e["sequencia"] = ["diaAtual": 1, "fechados": 0, "dias": []]
        XCTAssertNil((evaluate(e)["streak"] as! [String: Any])["atRisk"])
    }

    func testWeeklyGoalsUseTheLiveMonsterCount() {
        var e = eventos()
        e["semanais"] = ["concluidas": 1, "necessarias": 5,
                         "tarefas": [["id": "monstros", "progresso": 10, "meta": 50], ["id": "elites", "progresso": 3, "meta": 30]]]
        let goals = evaluate(e, weekLive: 18)["weeklyGoals"] as! [[String: Any]]
        XCTAssertEqual(goals[0]["progress"] as? Int, 18)
        XCTAssertEqual(goals[1]["progress"] as? Int, 3)
        XCTAssertEqual(goals[1]["goal"] as? Int, 30)
    }

    func testSupplyAlerts() {
        let ok = HuntAlerts.evaluate(state: ["cap": ["used": 50, "total": 100], "keyBagUsed": 1, "keyBagMax": 5,
                                             "keyClock": ["tierMs": 70, "everyMs": 100]])
        XCTAssertTrue((ok["alerts"] as! [Any]).isEmpty)
        XCTAssertEqual((ok["keys"] as! [String: Any])["nextKeyMs"] as? Int, 30)
        let hot = HuntAlerts.evaluate(state: ["cap": ["used": 95, "total": 100], "keyBagUsed": 5, "keyBagMax": 5])
        let levels = (hot["alerts"] as! [[String: String]]).map { $0["level"] }
        XCTAssertEqual(levels, ["warn", "bad"])
        let full = HuntAlerts.evaluate(state: ["cap": ["used": 100, "total": 100]])
        XCTAssertEqual((full["alerts"] as! [[String: String]]).first?["level"], "bad")
    }
}

final class InsightsTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private func makeStore() -> DashboardStore {
        let store = DashboardStore(databaseURL: nil, now: { self.clock })
        store.setHuntCatalog(HuntCatalog(json: Data(catalogJSON.utf8))!)
        store.setAccountNames(["Um", "Dois", "Três", "Quatro"])
        return store
    }
    private func object(_ data: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: data) as! [String: Any] }

    private func end(_ store: DashboardStore, account: Int = 0, map: Int, seconds: Int, xp: Int, balance: Int, deaths: Int = 0, reason: String = "stop") {
        clock += 60
        store.ingest(account: account, json: #"{"type":"ended","data":{"summary":{"huntId":\#(map),"reason":"\#(reason)","elapsedSec":\#(seconds),"xp":"\#(xp)","lootGold":1,"suppliesGold":1,"killsTotal":\#(seconds / 10),"balance":\#(balance),"deaths":\#(deaths)}}}"#)
    }

    func testRankingAggregatesRunsPerMapAndIgnoresShortOnes() {
        let store = makeStore()
        end(store, map: 10, seconds: 3600, xp: 1000, balance: 500)
        end(store, map: 10, seconds: 3600, xp: 3000, balance: 1500, deaths: 1)
        end(store, account: 1, map: 10, seconds: 3600, xp: 500, balance: 100)
        end(store, map: 11, seconds: 7200, xp: 2000, balance: 4000)
        end(store, map: 12, seconds: 120, xp: 99999, balance: 99999)   // too short to rank
        let rows = object(store.rankingJSON())["rows"] as! [[String: Any]]
        let all = rows.filter { $0["account"] is NSNull }
        XCTAssertEqual(all.map { $0["huntId"] as? Int }, [11, 10])
        let dragon = all.first { $0["huntId"] as? Int == 10 }!
        XCTAssertEqual(dragon["runs"] as? Int, 3)
        XCTAssertEqual(dragon["xpPerHour"] as? Int, 1500)         // 4500 xp in 3 h
        XCTAssertEqual(dragon["profitPerHour"] as? Int, 700)      // 2100 in 3 h
        XCTAssertEqual(dragon["deaths"] as? Int, 1)
        XCTAssertEqual(dragon["title"] as? String, "Dragon Lair")
        XCTAssertFalse(rows.contains { $0["huntId"] as? Int == 12 })
        XCTAssertEqual(rows.filter { $0["account"] as? Int == 1 }.count, 1)
    }

    func testDailyTotalsUseRunsAndSampledTime() {
        let store = makeStore()
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":10}}"#)
        for _ in 0..<10 {
            clock += 60
            store.ingest(account: 0, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":60000,"xp":"1","xpPerHour":1,"lootGold":0,"suppliesGold":0,"killsTotal":1}}}"#)
        }
        end(store, map: 10, seconds: 600, xp: 500, balance: 70, deaths: 1)
        let days = object(store.dailyJSON(days: 3))["days"] as! [[String: Any]]
        XCTAssertEqual(days.count, 1)
        let total = days[0]["total"] as! [String: Any]
        XCTAssertEqual(total["xp"] as? Int, 500)
        XCTAssertEqual(total["balance"] as? Int, 70)
        XCTAssertEqual(total["deaths"] as? Int, 1)
        XCTAssertEqual(total["huntedSeconds"] as? Int, 600)
        XCTAssertNotNil((days[0]["accounts"] as! [String: Any])["0"])
    }

    func testAttentionListsWhatNeedsAction() {
        let store = makeStore()
        store.ingest(account: 0, json: #"{"type":"welcome","data":{"eventos":{"serverDay":"d","nextDailyResetAt":\#(Int(clock.timeIntervalSince1970 * 1000) + 3_600_000),"diarias":{"slots":[{"id":"t1","title":"Caçada","kind":"monster","quantity":10,"progresso":10,"resgatado":false,"targets":["Dragon"]},null]}}}}"#)
        store.ingest(account: 1, json: #"{"type":"hunt_started","data":{"huntId":10,"state":{"cap":{"used":100,"total":100}}}}"#)
        end(store, account: 2, map: 10, seconds: 900, xp: 1, balance: -5, deaths: 1, reason: "death")
        store.ingest(account: 3, json: #"{"type":"welcome","data":{}}"#)
        clock += 20 * 60
        let kinds = Set(store.attention().map { "\($0.kind)|\($0.account)" })
        XCTAssertTrue(kinds.contains("ready|0"))
        XCTAssertTrue(kinds.contains("streak|0") == false, "no streak data, so no streak warning")
        XCTAssertTrue(kinds.contains("cap|1"))
        XCTAssertTrue(kinds.contains("ended|2"))
        XCTAssertTrue(kinds.contains("idle|3"))
        let items = store.attention()
        XCTAssertEqual(items.first?.level, "bad")
        XCTAssertTrue(items.filter { $0.kind == "idle" }.allSatisfy { !$0.notify })
        XCTAssertEqual(Set(items.map(\.key)).count, items.count, "keys must be unique")
        XCTAssertEqual((object(store.stateJSON())["attention"] as! [[String: Any]]).count, items.count)
        clock += 2 * 3600
        XCTAssertFalse(store.attention().contains { $0.kind == "ended" }, "old endings stop being news")
    }

    func testCSVEscapesAndNeutralisesFormulas() {
        XCTAssertEqual(DashboardStore.csvCell("a,b"), "\"a,b\"")
        XCTAssertEqual(DashboardStore.csvCell("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(DashboardStore.csvCell("=HYPERLINK(\"x\")"), "\"'=HYPERLINK(\"\"x\"\")\"")
        XCTAssertEqual(DashboardStore.csvCell("-50000"), "-50000")
        XCTAssertEqual(DashboardStore.csvCell(["Ann", "Bob"]), "Ann; Bob")
        let store = makeStore()
        end(store, map: 10, seconds: 3600, xp: 10, balance: -3)
        let text = String(data: store.huntsCSV(), encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("fim,conta,hunt,"))
        XCTAssertTrue(text.contains("Um,Dragon Lair,10"))
    }

    func testRouterServesTheNewEndpoints() {
        let store = makeStore()
        for path in ["/api/ranking", "/api/daily?days=7", "/api/hunts.csv", "/api/history.csv?hours=2"] {
            XCTAssertEqual(DashboardRouter.respond(method: "GET", target: path, store: store).status, 200, path)
        }
        let csv = DashboardRouter.respond(method: "GET", target: "/api/hunts.csv", store: store).serialized()
        XCTAssertTrue(String(decoding: csv, as: UTF8.self).contains("Content-Disposition: attachment"))
    }
}
