import Foundation
import SQLite3

/// Live hunt state per account plus a local history (SQLite) for the dashboard.
/// Payloads stay as JSON dictionaries: the collector already whitelists the fields and
/// the dashboard page does the presentation, so a new game field never breaks decoding.
public final class DashboardStore {
    public static let sampleInterval: TimeInterval = 60
    public static let retention: TimeInterval = 30 * 24 * 3600
    public static let maxMessageBytes = 256 * 1024

    private let queue = DispatchQueue(label: "TibidleMultiManager.DashboardStore")
    private let now: () -> Date
    private var db: OpaquePointer?
    private var live: [[String: Any]]
    private var lastSample: [Int: Date] = [:]
    private var names: [String]
    private var catalog = HuntCatalog.empty

    public init(databaseURL: URL?, now: @escaping () -> Date = Date.init) {
        self.now = now
        live = Array(repeating: ["status": "offline"], count: accountCount)
        names = (0..<accountCount).map { "Conta \($0 + 1)" }
        if let databaseURL {
            try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if sqlite3_open(databaseURL.path, &db) != SQLITE_OK { db = nil }
        } else if sqlite3_open(":memory:", &db) != SQLITE_OK {
            db = nil
        }
        exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS samples (account INTEGER, ts REAL, hunt_id INTEGER, elapsed_ms INTEGER,
                xp TEXT, xp_per_hour INTEGER, loot_gold INTEGER, supplies_gold INTEGER, kills_total INTEGER);
            CREATE INDEX IF NOT EXISTS samples_ts ON samples(ts);
            -- hunt_id is the *map* id, so a run is identified by its own numbers, not by the map.
            CREATE TABLE IF NOT EXISTS runs (account INTEGER, ended_at REAL, signature TEXT, summary TEXT,
                UNIQUE(account, signature));
            """)
        migrateLegacyHunts()
        run("DELETE FROM samples WHERE ts < ?", [.double(self.now().timeIntervalSince1970 - Self.retention)])
    }

    deinit { sqlite3_close(db) }

    /// Earlier versions keyed hunts by (account, map), so repeating a map replaced the previous run.
    private func migrateLegacyHunts() {
        var legacy = false
        query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='hunts'", []) { _ in legacy = true }
        guard legacy else { return }
        exec("""
            INSERT OR IGNORE INTO runs (account, ended_at, signature, summary)
                SELECT account, ended_at, 'legacy-' || hunt_id, summary FROM hunts;
            DROP TABLE hunts;
            """)
    }

    public func setHuntCatalog(_ catalog: HuntCatalog) {
        queue.sync { self.catalog = catalog }
    }

    public func setAccountNames(_ names: [String]) {
        queue.sync { self.names = names }
    }

    // MARK: Ingest

    public func ingest(account: Int, json: String) {
        guard (0..<accountCount).contains(account), json.utf8.count <= Self.maxMessageBytes,
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let type = object["type"] as? String else { return }
        let data = object["data"] as? [String: Any] ?? [:]
        queue.sync { apply(account: account, type: type, data: data) }
    }

    private func apply(account: Int, type: String, data: [String: Any]) {
        let date = now()
        var entry = live[account]
        switch type {
        case "welcome":
            entry["status"] = "city"
            entry["account"] = data["account"]
            entry["roster"] = data["roster"]
            entry["analyzer"] = nil
            entry["huntId"] = nil
            setMissions(&entry, data["eventos"])
        case "eventos_state", "eventos_result":
            setMissions(&entry, data["eventos"])
        case "hunt_started":
            entry["status"] = "hunting"
            entry["huntId"] = data["huntId"]
            entry["state"] = data["state"]
            entry["training"] = data["training"]
            entry["analyzer"] = nil
            entry["offline"] = nil
            entry["huntStartedAt"] = date.timeIntervalSince1970 * 1000
        case "resume", "frame":
            entry["status"] = "hunting"
            if let huntId = data["huntId"] { entry["huntId"] = huntId }
            if let state = data["state"] { entry["state"] = state }
            if let training = data["training"] { entry["training"] = training }
            if let offline = data["offline"] { entry["offline"] = offline }
            if let progress = (data["eventosProgresso"] as? [String: Any])?["dia"] as? [String: Any] {
                var slots: [String: Double] = [:]
                for case let slot as [String: Any] in (progress["slots"] as? [Any]) ?? [] {
                    if let id = slot["taskId"] as? String, let shown = number(slot["exibido"]) { slots[id] = shown }
                }
                entry["missionsLive"] = ["serverDay": progress["serverDay"] as? String ?? "", "slots": slots] as [String: Any]
            }
            if let week = (data["eventosProgresso"] as? [String: Any])?["semana"] as? [String: Any],
               let kills = number(week["monstros"]) {
                entry["weekLive"] = kills
            }
            if let analyzer = data["analyzer"] as? [String: Any] {
                entry["analyzer"] = analyzer
                if type == "resume" || entry["huntStartedAt"] == nil, let elapsed = number(analyzer["elapsedMs"]) {
                    entry["huntStartedAt"] = date.timeIntervalSince1970 * 1000 - elapsed
                }
                sample(account: account, huntId: entry["huntId"], analyzer: analyzer, at: date)
            }
        case "ended":
            entry["status"] = "city"
            guard var summary = data["summary"] as? [String: Any] else { break }
            summary["endedAt"] = date.timeIntervalSince1970 * 1000
            summary["characters"] = characterNames(entry)
            entry["lastSummary"] = summary
            entry["analyzer"] = nil
            if let text = jsonString(summary) {
                let signature = ["huntId", "elapsedSec", "xp", "lootGold", "suppliesGold", "killsTotal", "balance"]
                    .map { "\(summary[$0] ?? "")" }.joined(separator: "|")
                run("INSERT OR IGNORE INTO runs (account, ended_at, signature, summary) VALUES (?, ?, ?, ?)",
                    [.int(account), .double(date.timeIntervalSince1970), .text(signature), .text(text)])
            }
        case "session_takeover", "session_replaced":
            entry["status"] = "replaced"
        case "_closed":
            entry["status"] = "offline"
        default:
            return
        }
        let nowMs = date.timeIntervalSince1970 * 1000
        if entry["status"] as? String != live[account]["status"] as? String || entry["statusSince"] == nil { entry["statusSince"] = nowMs }
        entry["updatedAt"] = nowMs
        live[account] = entry
    }

    private func setMissions(_ entry: inout [String: Any], _ eventos: Any?) {
        guard let eventos = eventos as? [String: Any], eventos["diarias"] != nil else { return }
        entry["missions"] = eventos
        entry["missionsLive"] = nil
        entry["weekLive"] = nil
    }

    private func sample(account: Int, huntId: Any?, analyzer: [String: Any], at date: Date) {
        if let last = lastSample[account], date.timeIntervalSince(last) < Self.sampleInterval { return }
        lastSample[account] = date
        run("""
            INSERT INTO samples (account, ts, hunt_id, elapsed_ms, xp, xp_per_hour, loot_gold, supplies_gold, kills_total)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.int(account), .double(date.timeIntervalSince1970), .int(Int(number(huntId) ?? 0)),
                  .int(Int(number(analyzer["elapsedMs"]) ?? 0)), .text("\(analyzer["xp"] ?? "0")"),
                  .int(Int(number(analyzer["xpPerHour"]) ?? 0)), .int(Int(number(analyzer["lootGold"]) ?? 0)),
                  .int(Int(number(analyzer["suppliesGold"]) ?? 0)), .int(Int(number(analyzer["killsTotal"]) ?? 0))])
    }

    private func characterNames(_ entry: [String: Any]) -> [String] {
        let state = entry["state"] as? [String: Any]
        let party = (state?["party"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        if !party.isEmpty { return party }
        return [(state?["character"] as? [String: Any])?["name"] as? String].compactMap { $0 }
    }

    // MARK: Queries (JSON for the dashboard API)

    public func stateJSON() -> Data {
        queue.sync {
            let accounts = buildAccounts()
            let nowMs = now().timeIntervalSince1970 * 1000
            return json(["generatedAt": nowMs, "accounts": accounts,
                         "attention": Attention.evaluate(accounts: accounts, now: nowMs).map(\.json)])
        }
    }

    /// Current attention items (used by the macOS notifier).
    public func attention() -> [AttentionItem] {
        queue.sync { Attention.evaluate(accounts: buildAccounts(), now: now().timeIntervalSince1970 * 1000) }
    }

    private func buildAccounts() -> [[String: Any]] {
        live.enumerated().map { index, entry -> [String: Any] in
            var out = entry
            out["index"] = index
            out["label"] = names[index]
            if let eventos = entry["missions"] as? [String: Any] {
                out["daily"] = MissionAdvisor.evaluate(
                    eventos: eventos, live: entry["missionsLive"] as? [String: Any],
                    hunting: entry["status"] as? String == "hunting", training: entry["training"] as? Bool == true,
                    currentHuntId: number(entry["huntId"]).map { Int($0) }, catalog: catalog,
                    analyzer: entry["analyzer"] as? [String: Any], weekLive: entry["weekLive"] as? Double,
                    now: now().timeIntervalSince1970 * 1000)
            } else if let id = number(entry["huntId"]), let hunt = catalog.hunt(id: Int(id)) {
                out["daily"] = ["missions": [], "currentHunt": ["id": hunt.id, "title": hunt.title]] as [String: Any]
            }
            out["missions"] = nil
            out["missionsLive"] = nil
            out["weekLive"] = nil
            if entry["status"] as? String == "hunting", let state = entry["state"] as? [String: Any] {
                out["supply"] = HuntAlerts.evaluate(state: state)
            }
            return out
        }
    }

    /// Per-account series of `[timestampMs, xpPerHour, lootPerHour, profitPerHour]`.
    public func historyJSON(hours: Double) -> Data {
        queue.sync {
            var series: [String: [[Double]]] = [:]
            let since = now().timeIntervalSince1970 - hours * 3600
            query("SELECT account, ts, elapsed_ms, xp_per_hour, loot_gold, supplies_gold FROM samples WHERE ts >= ? ORDER BY ts",
                  [.double(since)]) { row in
                let elapsedHours = max(Double(sqlite3_column_int64(row, 2)) / 3_600_000, 1.0 / 60)
                let loot = Double(sqlite3_column_int64(row, 4)), supplies = Double(sqlite3_column_int64(row, 5))
                series[String(sqlite3_column_int(row, 0)), default: []].append([
                    sqlite3_column_double(row, 1) * 1000, Double(sqlite3_column_int64(row, 3)),
                    (loot / elapsedHours).rounded(), ((loot - supplies) / elapsedHours).rounded(),
                ])
            }
            return json(["hours": hours, "series": series])
        }
    }

    public func huntsJSON(limit: Int) -> Data {
        queue.sync {
            var hunts: [[String: Any]] = []
            query("SELECT account, summary FROM runs ORDER BY ended_at DESC LIMIT ?", [.int(limit)]) { row in
                guard let text = sqlite3_column_text(row, 1),
                      var summary = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any]
                else { return }
                let account = Int(sqlite3_column_int(row, 0))
                summary["account"] = account
                summary["huntTitle"] = number(summary["huntId"]).flatMap { catalog.hunt(id: Int($0))?.title }
                summary["label"] = names.indices.contains(account) ? names[account] : "Conta \(account + 1)"
                hunts.append(summary)
            }
            return json(["hunts": hunts])
        }
    }

    // MARK: Helpers

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private func jsonString(_ object: Any) -> String? {
        (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private enum Value { case int(Int), double(Double), text(String) }

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    private func run(_ sql: String, _ values: [Value]) { query(sql, values) { _ in } }

    private func query(_ sql: String, _ values: [Value], row: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, value) in values.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(statement, index, Int64(v))
            case .double(let v): sqlite3_bind_double(statement, index, v)
            case .text(let v): sqlite3_bind_text(statement, index, v, -1, transient)
            }
        }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }
}

// MARK: Insights (ranking, daily totals) and CSV export

extension DashboardStore {
    /// Runs shorter than this say little about a map's yield.
    static let minRankedSeconds = 300.0

    private func allRuns(limit: Int = 5000) -> [(account: Int, endedAt: Double, summary: [String: Any])] {
        var runs: [(Int, Double, [String: Any])] = []
        query("SELECT account, ended_at, summary FROM runs ORDER BY ended_at DESC LIMIT ?", [.int(limit)]) { row in
            guard let text = sqlite3_column_text(row, 2),
                  let summary = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any]
            else { return }
            runs.append((Int(sqlite3_column_int(row, 0)), sqlite3_column_double(row, 1), summary))
        }
        return runs
    }

    /// Yield per map, overall (`account: null`) and per account, from finished hunts.
    public func rankingJSON() -> Data {
        queue.sync {
            struct Total { var runs = 0, seconds = 0.0, xp = 0.0, balance = 0.0, kills = 0.0, deaths = 0.0 }
            var totals: [String: (account: Int?, huntId: Int, total: Total)] = [:]
            for run in allRuns() {
                let seconds = number(run.summary["elapsedSec"]) ?? 0
                guard seconds >= Self.minRankedSeconds, let huntId = number(run.summary["huntId"]).map({ Int($0) }) else { continue }
                for account in [run.account, -1] {
                    let key = "\(account)|\(huntId)"
                    var item = totals[key] ?? (account >= 0 ? account : nil, huntId, Total())
                    item.total.runs += 1
                    item.total.seconds += seconds
                    item.total.xp += number(run.summary["xp"]) ?? 0
                    item.total.balance += number(run.summary["balance"]) ?? 0
                    item.total.kills += number(run.summary["killsTotal"]) ?? 0
                    item.total.deaths += number(run.summary["deaths"]) ?? 0
                    totals[key] = item
                }
            }
            let rows = totals.values.map { item -> [String: Any] in
                let hours = item.total.seconds / 3600
                var row: [String: Any] = [
                    "huntId": item.huntId, "runs": item.total.runs, "hours": (hours * 100).rounded() / 100,
                    "xpPerHour": Int((item.total.xp / hours).rounded()), "profitPerHour": Int((item.total.balance / hours).rounded()),
                    "killsPerHour": Int((item.total.kills / hours).rounded()), "deaths": Int(item.total.deaths),
                    "title": catalog.hunt(id: item.huntId)?.title ?? (item.huntId == 1 ? "Tower" : "#\(item.huntId)"),
                ]
                row["account"] = item.account ?? NSNull()
                return row
            }.sorted { ($0["profitPerHour"] as? Int ?? 0) > ($1["profitPerHour"] as? Int ?? 0) }
            return json(["minMinutes": Int(Self.minRankedSeconds / 60), "rows": rows])
        }
    }

    /// Totals per local calendar day and account; hunted time comes from the per-minute samples.
    public func dailyJSON(days: Int) -> Data {
        queue.sync {
            let calendar = Calendar.current
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            let start = calendar.startOfDay(for: now().addingTimeInterval(-Double(days - 1) * 86400))
            func day(_ ts: Double) -> String { formatter.string(from: Date(timeIntervalSince1970: ts)) }

            struct Cell { var xp = 0.0, balance = 0.0, kills = 0.0, runs = 0, deaths = 0.0, huntedSeconds = 0.0 }
            var cells: [String: [Int: Cell]] = [:]
            for run in allRuns() where run.endedAt >= start.timeIntervalSince1970 {
                let key = day(run.endedAt)
                var cell = cells[key, default: [:]][run.account] ?? Cell()
                cell.xp += number(run.summary["xp"]) ?? 0
                cell.balance += number(run.summary["balance"]) ?? 0
                cell.kills += number(run.summary["killsTotal"]) ?? 0
                cell.deaths += number(run.summary["deaths"]) ?? 0
                cell.runs += 1
                cells[key, default: [:]][run.account] = cell
            }
            var previous: (account: Int, ts: Double)?
            query("SELECT account, ts FROM samples WHERE ts >= ? ORDER BY account, ts", [.double(start.timeIntervalSince1970)]) { row in
                let account = Int(sqlite3_column_int(row, 0)), ts = sqlite3_column_double(row, 1)
                let gap = previous.flatMap { $0.account == account ? ts - $0.ts : nil } ?? Self.sampleInterval
                let key = day(ts)
                var cell = cells[key, default: [:]][account] ?? Cell()
                cell.huntedSeconds += gap <= 3 * Self.sampleInterval ? gap : Self.sampleInterval
                cells[key, default: [:]][account] = cell
                previous = (account, ts)
            }
            let rows = cells.keys.sorted(by: >).map { key -> [String: Any] in
                let accounts = cells[key] ?? [:]
                var perAccount: [String: Any] = [:]
                for (account, cell) in accounts {
                    perAccount[String(account)] = ["xp": Int(cell.xp), "balance": Int(cell.balance), "kills": Int(cell.kills), "runs": cell.runs,
                                                   "deaths": Int(cell.deaths), "huntedSeconds": Int(cell.huntedSeconds)]
                }
                let sum = accounts.values.reduce(Cell()) { Cell(xp: $0.xp + $1.xp, balance: $0.balance + $1.balance, kills: $0.kills + $1.kills,
                                                                runs: $0.runs + $1.runs, deaths: $0.deaths + $1.deaths, huntedSeconds: $0.huntedSeconds + $1.huntedSeconds) }
                return ["date": key, "accounts": perAccount,
                        "total": ["xp": Int(sum.xp), "balance": Int(sum.balance), "kills": Int(sum.kills), "runs": sum.runs,
                                  "deaths": Int(sum.deaths), "huntedSeconds": Int(sum.huntedSeconds)]]
            }
            return json(["days": rows])
        }
    }

    // MARK: CSV

    static func csvCell(_ value: Any?) -> String {
        var text: String
        switch value {
        case nil, is NSNull: text = ""
        case let list as [String]: text = list.joined(separator: "; ")
        case let n as NSNumber: text = n.stringValue
        default: text = "\(value!)"
        }
        // Spreadsheets run cells that start with these characters as formulas.
        if let first = text.first, "=+-@\t\r".contains(first), Double(text) == nil { text = "'" + text }
        return text.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
    }

    private func csv(_ header: [String], _ rows: [[Any?]]) -> Data {
        let lines = [header.joined(separator: ",")] + rows.map { $0.map(Self.csvCell).joined(separator: ",") }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    public func huntsCSV() -> Data {
        queue.sync {
            let iso = ISO8601DateFormatter()
            let rows = allRuns().map { run -> [Any?] in
                let s = run.summary
                let level = s["level"] as? [String: Any]
                return [iso.string(from: Date(timeIntervalSince1970: run.endedAt)),
                        names.indices.contains(run.account) ? names[run.account] : "Conta \(run.account + 1)",
                        number(s["huntId"]).flatMap { catalog.hunt(id: Int($0))?.title }, s["huntId"], s["characters"],
                        s["elapsedSec"], s["reason"], level?["start"], level?["end"], s["xp"], s["xpPerHour"], s["lootGold"], s["suppliesGold"],
                        s["balance"], s["killsTotal"], s["deaths"], s["deathCause"]]
            }
            return csv(["fim", "conta", "hunt", "hunt_id", "personagens", "duracao_s", "motivo", "level_ini", "level_fim", "xp", "xp_h",
                        "loot", "supplies", "balance", "kills", "mortes", "causa_morte"], rows)
        }
    }

    public func historyCSV(hours: Double) -> Data {
        queue.sync {
            var rows: [[Any?]] = []
            let iso = ISO8601DateFormatter()
            query("SELECT account, ts, hunt_id, elapsed_ms, xp, xp_per_hour, loot_gold, supplies_gold, kills_total FROM samples WHERE ts >= ? ORDER BY ts",
                  [.double(now().timeIntervalSince1970 - hours * 3600)]) { row in
                let account = Int(sqlite3_column_int(row, 0))
                rows.append([iso.string(from: Date(timeIntervalSince1970: sqlite3_column_double(row, 1))),
                             names.indices.contains(account) ? names[account] : "Conta \(account + 1)", sqlite3_column_int64(row, 2),
                             sqlite3_column_int64(row, 3), sqlite3_column_text(row, 4).map { String(cString: $0) }, sqlite3_column_int64(row, 5),
                             sqlite3_column_int64(row, 6), sqlite3_column_int64(row, 7), sqlite3_column_int64(row, 8)])
            }
            return csv(["horario", "conta", "hunt_id", "tempo_ms", "xp", "xp_h", "loot", "supplies", "kills"], rows)
        }
    }
}
