import Darwin
import XCTest
@testable import TibidleCore

final class ServerTests: XCTestCase {
    func testGzipIsReadableByGunzip() throws {
        XCTAssertEqual(Gzip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        let original = Data(String(repeating: #"{"xp":123456,"name":"Knight"},"#, count: 400).utf8)
        let packed = try XCTUnwrap(Gzip.compress(original))
        XCTAssertLessThan(packed.count, original.count / 5)
        let gunzip = Process()
        gunzip.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        gunzip.arguments = ["-c"]
        let input = Pipe(), output = Pipe()
        gunzip.standardInput = input
        gunzip.standardOutput = output
        try gunzip.run()
        input.fileHandleForWriting.write(packed)
        try input.fileHandleForWriting.close()
        let unpacked = output.fileHandleForReading.readDataToEndOfFile()
        gunzip.waitUntilExit()
        XCTAssertEqual(gunzip.terminationStatus, 0)
        XCTAssertEqual(unpacked, original)
    }

    func testResponsesCompressOnlyLargeText() {
        let big = HTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: Data(String(repeating: "a", count: 5000).utf8))
        let head = String(decoding: big.serialized(gzip: true, includeBody: false), as: UTF8.self)
        XCTAssertTrue(head.contains("Content-Encoding: gzip"))
        XCTAssertTrue(head.hasSuffix("\r\n\r\n"), "HEAD carries no body")
        XCTAssertFalse(String(decoding: big.serialized(gzip: false), as: UTF8.self).contains("Content-Encoding"))
        let small = HTTPResponse(status: 200, contentType: "application/json", body: Data("{}".utf8))
        XCTAssertFalse(String(decoding: small.serialized(gzip: true), as: UTF8.self).contains("Content-Encoding"))
        let icon = HTTPResponse(status: 200, contentType: "image/png", body: Data(count: 5000))
        XCTAssertFalse(String(decoding: icon.serialized(gzip: true), as: UTF8.self).contains("Content-Encoding"))
    }

    func testReadsRefuseForeignHostNames() {
        let store = DashboardStore(databaseURL: nil)
        func status(_ host: String?) -> Int {
            DashboardRouter.respond(HTTPRequest(method: "GET", target: "/api/ranking", headers: host.map { ["host": $0] } ?? [:]), store: store).status
        }
        for allowed in [nil, "localhost:8787", "127.0.0.1:8787", "192.168.0.10:8787", "[::1]:8787", "MacBook-Air.local:8787", "macbook:8787"] {
            XCTAssertEqual(status(allowed), 200, allowed ?? "no host")
        }
        // A site that rebinds its own name to this Mac still sends that name.
        for foreign in ["evil.example.com", "attacker.com:8787", "1.2.3.4.evil.io"] { XCTAssertEqual(status(foreign), 403, foreign) }
    }

    func testRoutesForOneHuntTheManifestAndTheIcon() throws {
        let store = DashboardStore(databaseURL: nil)
        XCTAssertEqual(DashboardRouter.respond(method: "GET", target: "/api/hunt?id=1", store: store).status, 404)
        store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":3,"elapsedSec":600,"balance":5}}}"#)
        let found = DashboardRouter.respond(method: "GET", target: "/api/hunt?id=1", store: store)
        XCTAssertEqual(found.status, 200)
        let hunt = try XCTUnwrap((try JSONSerialization.jsonObject(with: found.body) as? [String: Any])?["hunt"] as? [String: Any])
        XCTAssertEqual(hunt["id"] as? Int, 1)
        let manifest = DashboardRouter.respond(method: "GET", target: "/manifest.webmanifest", store: store)
        XCTAssertEqual(manifest.status, 200)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: manifest.body) as? [String: Any])
        DashboardRouter.appIcon = nil
        XCTAssertEqual(DashboardRouter.respond(method: "GET", target: "/apple-touch-icon.png", store: store).status, 404)
    }

    /// A negative Content-Length once crashed the app (a backwards slice); now it is a 400 and the server keeps serving.
    func testNegativeContentLengthIsRefusedAndTheServerStaysUp() throws {
        let server = DashboardServer(store: DashboardStore(databaseURL: nil))
        let ready = expectation(description: "listening")
        var port: UInt16 = 0
        server.onReady = { port = $0; ready.fulfill() }
        server.start(port: UInt16.random(in: 47_000...48_000))
        wait(for: [ready], timeout: 5)
        defer { server.stop() }
        let bad = try XCTUnwrap(rawRequest(port: port, "GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: -1\r\n\r\n"))
        XCTAssertTrue(bad.hasPrefix("HTTP/1.1 400"), bad)
        let good = try XCTUnwrap(rawRequest(port: port, "GET /api/ranking HTTP/1.1\r\nHost: localhost\r\n\r\n"))
        XCTAssertTrue(good.hasPrefix("HTTP/1.1 200"), good)
    }

    private func rawRequest(port: UInt16, _ request: String) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return nil }
        _ = request.withCString { send(fd, $0, strlen($0), 0) }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            response.append(buffer, count: count)
        }
        return String(decoding: response, as: UTF8.self)
    }
}

final class StoreLifecycleTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private func makeStore() -> DashboardStore { DashboardStore(databaseURL: nil, now: { [unowned self] in clock }) }
    private func object(_ data: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: data) as! [String: Any] }
    private func account(_ store: DashboardStore, _ index: Int = 0) -> [String: Any] {
        (object(store.stateJSON())["accounts"] as! [[String: Any]])[index]
    }
    private func resume(_ store: DashboardStore, huntId: Int = 7, elapsedMs: Double) {
        store.ingest(account: 0, json: #"{"type":"resume","data":{"huntId":\#(huntId),"analyzer":{"elapsedMs":\#(elapsedMs)},"state":{"party":[{"name":"Zolp","hp":100,"maxHp":100}]}}}"#)
    }

    func testReconnectingToTheSameHuntKeepsItsStart() {
        let store = makeStore()
        resume(store, elapsedMs: 600_000)
        let started = account(store)["huntStartedAt"] as? Double
        // The socket drops and comes back 30 s later: same hunt, a little further along.
        clock += 30
        store.ingest(account: 0, json: #"{"type":"_closed","data":{}}"#)
        store.ingest(account: 0, json: #"{"type":"welcome","data":{}}"#)
        resume(store, elapsedMs: 630_000)
        XCTAssertEqual(account(store)["huntStartedAt"] as? Double, started, "the ignored advice of this hunt stays ignored")
        // Another hunt on the same map starts over.
        clock += 3600
        store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":7,"elapsedSec":4000}}}"#)
        resume(store, elapsedMs: 5000)
        XCTAssertNotEqual(account(store)["huntStartedAt"] as? Double, started)
    }

    func testQuietAndCrashedPagesAreShown() {
        let store = makeStore()
        resume(store, elapsedMs: 60_000)
        XCTAssertEqual(account(store)["status"] as? String, "hunting")
        clock += DashboardStore.staleAfter + 1
        XCTAssertEqual(account(store)["status"] as? String, "stale")
        XCTAssertTrue(store.attention().contains { $0.kind == "stale" && $0.level == "warn" })
        clock += 5 * 60
        XCTAssertTrue(store.attention().contains { $0.kind == "stale" && $0.level == "bad" && $0.notify })
        store.markCrashed(account: 0)
        XCTAssertEqual(account(store)["status"] as? String, "crashed")
        XCTAssertTrue(store.attention().contains { $0.kind == "crashed" })
        let seen = expectation(description: "statuses")
        store.statuses { list in XCTAssertEqual(list.first, "crashed"); seen.fulfill() }
        wait(for: [seen], timeout: 2)
    }

    func testDailyTotalsSplitAHuntAcrossMidnight() {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: clock).addingTimeInterval(86400)
        clock = midnight.addingTimeInterval(3600)   // ended at 01:00, after 4 h: 3 h yesterday, 1 h today
        let store = makeStore()
        store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":3,"elapsedSec":14400,"xp":4000,"balance":800,"killsTotal":400,"deaths":1}}}"#)
        let days = object(store.dailyJSON(days: 3))["days"] as! [[String: Any]]
        XCTAssertEqual(days.count, 2)
        let today = days[0]["total"] as! [String: Any], yesterday = days[1]["total"] as! [String: Any]
        XCTAssertEqual(today["xp"] as? Int, 1000)
        XCTAssertEqual(yesterday["xp"] as? Int, 3000)
        XCTAssertEqual(yesterday["balance"] as? Int, 600)
        // The end and its death count on the day it ended.
        XCTAssertEqual(today["runs"] as? Int, 1)
        XCTAssertEqual(today["deaths"] as? Int, 1)
        XCTAssertEqual(yesterday["runs"] as? Int, 0)
    }

    func testLongHistoryIsBucketed() {
        let store = makeStore()
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":3}}"#)
        for minute in 0..<(3 * 24 * 60) {
            clock += 60
            store.ingest(account: 0, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":\#((minute + 1) * 60_000),"xpPerHour":1000,"lootGold":\#(minute * 10),"suppliesGold":0}}}"#)
        }
        let week = (object(store.historyJSON(hours: 168))["series"] as! [String: [[Any]]])["0"]!
        // A week in ~600 buckets is 16.8 min each: 3 days of samples fill about 258 of them.
        XCTAssertTrue((250...262).contains(week.count), "\(week.count)")
        XCTAssertEqual(week.last?[1] as? Double, 1000)
        let day = (object(store.historyJSON(hours: 2))["series"] as! [String: [[Any]]])["0"]!
        XCTAssertEqual(day.count, 121, "up to 24 h every sample comes as is (both ends of the 2 h included)")
    }

    func testHuntListsFilterPageAndVersion() {
        let store = makeStore()
        let before = object(store.stateJSON())["runsVersion"] as? Int
        for (index, (account, map, seconds)) in [(0, 3, 600), (1, 3, 3600), (0, 4, 3600), (0, 3, 7200)].enumerated() {
            clock += 60
            store.ingest(account: account, json: #"{"type":"ended","data":{"summary":{"huntId":\#(map),"elapsedSec":\#(seconds),"xp":\#(index),"members":[{"name":"Zolp","gear":{"armor":{"name":"plate"}}}]}}}"#)
        }
        XCTAssertNotEqual(object(store.stateJSON())["runsVersion"] as? Int, before, "the page refetches the lists when it changes")
        let filtered = object(store.huntsJSON(limit: 1, offset: 0, filter: .init(account: 0, huntId: 3, minMinutes: 30), lean: false))
        XCTAssertEqual(filtered["total"] as? Int, 1)
        let first = (filtered["hunts"] as! [[String: Any]])[0]
        XCTAssertEqual(first["elapsedSec"] as? Int, 7200)
        XCTAssertNil(((first["members"] as? [[String: Any]])?[0])?["gear"])
        let page = object(store.huntsJSON(limit: 2, offset: 2, filter: .init(), lean: true))
        XCTAssertEqual(page["total"] as? Int, 4)
        let lean = (page["hunts"] as! [[String: Any]])
        XCTAssertEqual(lean.count, 2)
        XCTAssertNil(lean[0]["members"], "the lean list keeps only what the level chart reads")
        XCTAssertNotNil(lean[0]["elapsedSec"])
    }

    func testShortHuntsCountInTheMapsDeaths() {
        let store = makeStore()
        for (seconds, deaths) in [(120, 1), (3600, 0), (90, 1)] {
            clock += 60
            store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":5,"elapsedSec":\#(seconds),"deaths":\#(deaths),"level":{"start":100,"end":100}}}}"#)
        }
        store.flush()
        let history = store.deathHistory(["huntId": 5, "state": ["character": ["level": 100]]])
        XCTAssertEqual(history.deaths, 2, "the deaths that end a hunt in its first minutes count")
        XCTAssertEqual(history.hours, (120 + 3600 + 90) / 3600.0, accuracy: 1e-9)
    }

    func testFramesWithoutGearKeepTheKnownGear() {
        let previous: [String: Any] = ["party": [["name": "Zolp", "gear": ["armor": ["name": "plate"]]], ["name": "Mage"]]]
        let next = DashboardStore.keepingGear(["party": [["name": "Zolp", "hp": 10], ["name": "Mage", "gear": ["ring": ["name": "might"]]]]],
                                              previous: previous) as! [String: Any]
        let party = next["party"] as! [[String: Any]]
        XCTAssertEqual(((party[0]["gear"] as? [String: Any])?["armor"] as? [String: Any])?["name"] as? String, "plate")
        XCTAssertEqual(((party[1]["gear"] as? [String: Any])?["ring"] as? [String: Any])?["name"] as? String, "might")
    }
}

final class SettingsZoomTests: XCTestCase {
    func testZoomIsKeptPerPaneSizeAndRepaired() throws {
        let json = #"{"accounts":[{"name":"A","zoom":{"side":0.7,"main":9,"bogus":2}}],"layout":"featured"}"#
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        settings.normalize()
        XCTAssertEqual(settings.accounts[0].zoom(for: .side), 0.7)
        XCTAssertEqual(settings.accounts[0].zoom(for: .main), AccountSettings.zoomRange.upperBound)
        XCTAssertEqual(settings.accounts[0].zoom(for: .full), 1)
        XCTAssertNil(settings.accounts[0].zoom["bogus"])
        XCTAssertTrue(settings.dashboardOnNetwork)
        XCTAssertFalse(settings.srgbColors)
        XCTAssertEqual(PaneSize.of(position: 0, in: .featured), .main)
        XCTAssertEqual(PaneSize.of(position: 2, in: .featured), .side)
        XCTAssertEqual(PaneSize.of(position: 2, in: .grid), .quarter)
        XCTAssertEqual(PaneSize.of(position: 3, in: .single), .full)
    }
}
