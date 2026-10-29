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
    private var spells = SpellCatalog.empty
    private var creatures = CreatureCatalog()
    private var calibration = SkillAdvisor.Calibration.none
    private var bestiaries = HuntBestiaryCatalog.empty
    /// Modeled damage accumulated during the current hunt, per assumed crowd size, plus the seconds covered.
    private var modeled: [Int: (damage: [Int: Double], seconds: Double, valid: Bool, last: Date?)] = [:]
    static let crowdSizes = [1, 2, 3, 4, 6, 8]
    /// Finished hunts, newest first, parsed once and dropped whenever a hunt is recorded.
    var runCache: [(account: Int, endedAt: Double, summary: [String: Any])]?
    /// Average mana per party member during the current hunt (reset when a hunt starts or resumes).
    private var mana: [Int: ManaTracker] = [:]

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
            -- Modeled vs real damage per hunt, used to calibrate the skill advisor.
            CREATE TABLE IF NOT EXISTS presets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, vocation TEXT, hunt_id INTEGER,
                hunt_title TEXT, text TEXT, created_at REAL);
            CREATE TABLE IF NOT EXISTS calibration (account INTEGER, ended_at REAL, predicted TEXT, actual REAL);
            """)
        migrateLegacyHunts()
        reloadCalibration()
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

    public func setSpellCatalog(_ spells: SpellCatalog) { queue.sync { self.spells = spells } }
    public func setBestiaries(_ catalog: HuntBestiaryCatalog) { queue.sync { bestiaries = catalog } }
    public func setCreatures(_ creatures: CreatureCatalog) { queue.sync { self.creatures = creatures } }

    /// Monsters killed on screen whose resistances are still unknown (the loader fetches them).
    public func missingCreatures() -> [String] {
        queue.sync {
            var names = Set<String>()
            for entry in live where entry["status"] as? String == "hunting" {
                for key in ((entry["analyzer"] as? [String: Any])?["kills"] as? [String: Any])?.keys.map({ $0 }) ?? [] where !creatures.knows(key) {
                    names.insert(key)
                }
            }
            return names.sorted()
        }
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
            entry["invasion"] = data["invasao"]
            if let battle = data["battleConfigs"] { entry["battle"] = battle }
            entry["huntBestiary"] = data["huntBestiary"]
            entry["bestiarySnap"] = 0.0
        case "invasion_update":
            if let invasion = data["invasao"] as? [String: Any] { entry["invasion"] = invasion }
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
            modeled[account] = ([:], 0, true, nil)
            mana[account] = ManaTracker()
            entry["bestiarySnap"] = 0.0
        case "resume", "frame":
            if type == "resume", let battle = data["battleConfigs"] { entry["battle"] = battle }
            if type == "resume", let counters = data["huntBestiary"] {
                // The counter already holds the kills made so far in this hunt: count only what comes after.
                entry["huntBestiary"] = counters
                entry["bestiarySnap"] = number((data["analyzer"] as? [String: Any])?["killsTotal"]) ?? 0
            }
            if type == "resume" { modeled[account] = nil; mana[account] = ManaTracker() }
            if let party = (data["state"] as? [String: Any])?["party"] as? [[String: Any]] { mana[account, default: ManaTracker()].add(party: party) }
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
            if let party = (entry["state"] as? [String: Any])?["party"] as? [[String: Any]], !party.isEmpty {
                // Who spent the supplies (the last frame before the end holds the hunt's totals per member).
                summary["members"] = party.map { member -> [String: Any] in
                    ["name": member["name"] as? String ?? "", "vocation": member["vocation"] as? String ?? "",
                     "level": number(member["level"]) ?? 0, "suppliesGold": number(member["suppliesGold"]) ?? 0]
                }
            }
            // The battle setup this hunt ran with, so two hunts can later be compared ("what changed?").
            let setup = presetVocations(entry).reduce(into: [String: Any]()) { $0[$1.vocation] = BattlePreset.normalize($1.config) }
            if !setup.isEmpty { summary["setup"] = setup }
            entry["lastSummary"] = summary
            recordCalibration(account: account, summary: summary, at: date)
            // Until the next welcome refreshes the server's counters, fold the finished hunt in locally.
            if let id = number(summary["huntId"]), var counters = entry["huntBestiary"] as? [String: Any],
               let kills = number(summary["killsTotal"]) {
                let fresh = max(0, kills - (number(entry["bestiarySnap"]) ?? 0))
                counters[String(Int(id))] = (number(counters[String(Int(id))]) ?? 0) + fresh
                entry["huntBestiary"] = counters
            }
            entry["analyzer"] = nil
            if let text = jsonString(summary) {
                let signature = ["huntId", "elapsedSec", "xp", "lootGold", "suppliesGold", "killsTotal", "balance"]
                    .map { "\(summary[$0] ?? "")" }.joined(separator: "|")
                run("INSERT OR IGNORE INTO runs (account, ended_at, signature, summary) VALUES (?, ?, ?, ?)",
                    [.int(account), .double(date.timeIntervalSince1970), .text(signature), .text(text)])
                runCache = nil
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
        accumulateModel(account: account, analyzer: analyzer, at: date)
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
            if entry["status"] as? String == "hunting", entry["training"] as? Bool != true,
               let skills = skillAnalysis(entry) {
                out["skills"] = ManaBudget.apply(skills, averages: mana[index]?.averages() ?? [:])
            }
            out["battle"] = nil
            if entry["status"] as? String == "hunting", entry["training"] as? Bool != true, let bestiary = bestiaryProgress(entry) {
                out["bestiary"] = bestiary
            }
            out["huntBestiary"] = nil
            out["bestiarySnap"] = nil
            out["invasion"] = InvasionAdvisor.evaluate(entry["invasion"] as? [String: Any], now: now().timeIntervalSince1970 * 1000)
            out["missions"] = nil
            out["missionsLive"] = nil
            out["weekLive"] = nil
            if entry["status"] as? String == "hunting", let state = entry["state"] as? [String: Any] {
                out["supply"] = HuntAlerts.evaluate(state: state)
            }
            if entry["status"] as? String == "hunting", entry["training"] as? Bool != true, let benchmark = levelBenchmark(entry) {
                out["benchmark"] = benchmark
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
            query("SELECT account, summary, rowid FROM runs ORDER BY ended_at DESC LIMIT ?", [.int(limit)]) { row in
                guard let text = sqlite3_column_text(row, 1),
                      var summary = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any]
                else { return }
                let account = Int(sqlite3_column_int(row, 0))
                summary["id"] = Int(sqlite3_column_int64(row, 2))
                summary["hasSetup"] = summary["setup"] != nil
                summary["setup"] = nil
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

    private func allRuns() -> [(account: Int, endedAt: Double, summary: [String: Any])] {
        if let runCache { return runCache }
        var runs: [(Int, Double, [String: Any])] = []
        query("SELECT account, ended_at, summary FROM runs ORDER BY ended_at DESC LIMIT 5000", []) { row in
            guard let text = sqlite3_column_text(row, 2),
                  let summary = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any]
            else { return }
            runs.append((Int(sqlite3_column_int(row, 0)), sqlite3_column_double(row, 1), summary))
        }
        runCache = runs
        return runs
    }

    /// How finished hunts on this map went near the current level (±`benchmarkLevels`), per account.
    /// Separates "it is just the level" from "it is the setup".
    static let benchmarkLevels = 2.0
    static let minBenchmarkSeconds = 1800.0

    func levelBenchmark(_ entry: [String: Any]) -> [String: Any]? {
        let state = entry["state"] as? [String: Any]
        guard let huntId = number(entry["huntId"]).map({ Int($0) }),
              let level = number((state?["character"] as? [String: Any])?["level"]) ?? number((entry["account"] as? [String: Any])?["level"])
        else { return nil }
        return levelBenchmark(huntId: huntId, level: level)
    }

    /// Also used by the development server to compute the block from a copy of the real database.
    public func benchmark(huntId: Int, level: Double) -> [String: Any]? {
        queue.sync { levelBenchmark(huntId: huntId, level: level) }
    }

    private func levelBenchmark(huntId: Int, level: Double) -> [String: Any]? {
        struct Total { var runs = 0, seconds = 0.0, balance = 0.0, loot = 0.0, supplies = 0.0, kills = 0.0, taken = 0.0, low = Double.infinity, high = 0.0 }
        var totals: [Int: Total] = [:]
        for run in allRuns() {
            let s = run.summary
            guard number(s["huntId"]).map({ Int($0) }) == huntId, let seconds = number(s["elapsedSec"]), seconds >= Self.minBenchmarkSeconds,
                  let range = s["level"] as? [String: Any], let end = number(range["end"]) else { continue }
            let start = number(range["start"]) ?? end
            guard abs((start + end) / 2 - level) <= Self.benchmarkLevels else { continue }
            var total = totals[run.account] ?? Total()
            total.runs += 1
            total.seconds += seconds
            total.balance += number(s["balance"]) ?? 0
            total.loot += number(s["lootGold"]) ?? 0
            total.supplies += number(s["suppliesGold"]) ?? 0
            total.kills += number(s["killsTotal"]) ?? 0
            total.taken += number(s["damageTaken"]) ?? 0
            total.low = min(total.low, start)
            total.high = max(total.high, end)
            totals[run.account] = total
        }
        guard !totals.isEmpty else { return nil }
        let rows = totals.sorted { $0.key < $1.key }.map { account, total -> [String: Any] in
            let hours = total.seconds / 3600
            return ["account": account, "label": names.indices.contains(account) ? names[account] : "Conta \(account + 1)",
                    "runs": total.runs, "hours": (hours * 10).rounded() / 10,
                    "levels": total.low == total.high ? "\(Int(total.low))" : "\(Int(total.low))–\(Int(total.high))",
                    "profitPerHour": Int((total.balance / hours).rounded()), "lootPerHour": Int((total.loot / hours).rounded()),
                    "suppliesPerHour": Int((total.supplies / hours).rounded()), "killsPerHour": Int((total.kills / hours).rounded()),
                    "damageTakenPerHour": Int((total.taken / hours).rounded())]
        }
        return ["level": Int(level), "range": Int(Self.benchmarkLevels), "minMinutes": Int(Self.minBenchmarkSeconds / 60), "rows": rows]
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


// MARK: Skill advisor integration

extension DashboardStore {
    static let calibrationWindow = 60

    /// Party members as the model sees them; nil entries without a usable spell kit are skipped.
    func skillMembers(_ entry: [String: Any]) -> [SkillAdvisor.Member] {
        guard let party = (entry["state"] as? [String: Any])?["party"] as? [[String: Any]] else { return [] }
        let battle = entry["battle"] as? [String: Any]
        return party.compactMap { member -> SkillAdvisor.Member? in
            guard let name = member["name"] as? String, let vocation = member["vocation"] as? String else { return nil }
            let base = SkillAdvisor.baseVocation(vocation)
            let config = battle?.first { $0.key.lowercased() == base }?.value as? [String: Any]
            let configured = (config?["skills"] as? [Any])?.compactMap { $0 as? String } ?? []
            let equipped = ((member["kit"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
            let kit = (configured.isEmpty ? equipped : configured).filter { spells.spell(named: $0) != nil }
            guard !kit.isEmpty else { return nil }
            let levels = member["skillLevels"] as? [String: Any] ?? [:]
            var minCreatures: [String: Int] = [:]
            for (key, value) in config?["minCreatures"] as? [String: Any] ?? [:] { minCreatures[key] = Int(number(value) ?? 1) }
            return SkillAdvisor.Member(
                name: name, vocation: vocation, level: Int(number(member["level"]) ?? 1),
                melee: number(levels["melee"]) ?? 10, distance: number(levels["distance"]) ?? 10, magic: number(levels["magic"]) ?? 0,
                attack: number(member["weaponAttack"]), kit: kit, minCreatures: minCreatures)
        }
    }

    func skillAnalysis(_ entry: [String: Any]) -> [String: Any]? {
        guard !spells.spells.isEmpty else { return nil }
        let members = skillMembers(entry)
        let kills = ((entry["analyzer"] as? [String: Any])?["kills"] as? [String: Any])?.compactMapValues { number($0) } ?? [:]
        guard !members.isEmpty, kills.values.reduce(0, +) >= 20 else { return nil }
        return SkillAdvisor.analyze(members: members, spells: spells, creatures: creatures, kills: kills, calibration: calibration)
    }

    func accumulateModel(account: Int, analyzer: [String: Any], at date: Date) {
        guard var state = modeled[account], state.valid else { return }
        let entry = live[account]
        let kills = (analyzer["kills"] as? [String: Any])?.compactMapValues { number($0) } ?? [:]
        let members = skillMembers(entry)
        defer { state.last = date; modeled[account] = state }
        guard let last = state.last, !members.isEmpty, !kills.isEmpty else { return }
        let dt = min(date.timeIntervalSince(last), 120)
        let perCrowd = SkillAdvisor.modeledDPS(members: members, spells: spells, creatures: creatures, kills: kills, crowds: Self.crowdSizes)
        for (crowd, dps) in perCrowd { state.damage[crowd, default: 0] += dps * dt }
        state.seconds += dt
    }

    func recordCalibration(account: Int, summary: [String: Any], at date: Date) {
        defer { modeled[account] = nil }
        guard let state = modeled[account], state.valid, state.seconds >= 300,
              let elapsed = number(summary["elapsedSec"]), elapsed > 0, state.seconds >= elapsed * 0.7,
              let actual = number(summary["damageDealt"]), actual > 0 else { return }
        let predicted = state.damage.mapValues { $0 / state.seconds }
        guard let text = jsonString(Dictionary(uniqueKeysWithValues: predicted.map { (String($0.key), $0.value) })) else { return }
        run("INSERT INTO calibration (account, ended_at, predicted, actual) VALUES (?, ?, ?, ?)",
            [.int(account), .double(date.timeIntervalSince1970), .text(text), .double(actual / elapsed)])
        reloadCalibration()
    }

    func calibrationSamples() -> Int { queue.sync { calibration.samples } }

    func reloadCalibration() {
        var runs: [(predicted: [Int: Double], actual: Double)] = []
        query("SELECT predicted, actual FROM calibration ORDER BY ended_at DESC LIMIT \(Self.calibrationWindow)", []) { row in
            guard let text = sqlite3_column_text(row, 0),
                  let object = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Double] else { return }
            runs.append((Dictionary(uniqueKeysWithValues: object.compactMap { key, value in Int(key).map { ($0, value) } }),
                         sqlite3_column_double(row, 1)))
        }
        calibration = SkillAdvisor.calibrate(runs)
    }
}


extension DashboardStore {
    func bestiaryProgress(_ entry: [String: Any]) -> [String: Any]? {
        guard let huntId = number(entry["huntId"]).map({ Int($0) }), let info = bestiaries.entries[huntId],
              let counters = entry["huntBestiary"] as? [String: Any] else { return nil }
        let analyzer = entry["analyzer"] as? [String: Any]
        return BestiaryAdvisor.evaluate(info, counted: number(counters[String(huntId)]) ?? 0,
                                        session: max(0, (number(analyzer?["killsTotal"]) ?? 0) - (number(entry["bestiarySnap"]) ?? 0)),
                                        elapsedMs: number(analyzer?["elapsedMs"]) ?? 0, huntKills: number(analyzer?["killsTotal"]))
    }
}


// MARK: Battle presets (local library)

extension DashboardStore {
    public enum PresetError: Error, Equatable { case message(String) }

    private func presetRows() -> [(id: Int, name: String, createdAt: Double, preset: BattlePreset, text: String)] {
        var rows: [(Int, String, Double, BattlePreset, String)] = []
        query("SELECT id, name, created_at, text FROM presets ORDER BY created_at DESC, id DESC", []) { row in
            guard let raw = sqlite3_column_text(row, 3), let name = sqlite3_column_text(row, 1) else { return }
            let text = String(cString: raw)
            if case .success(let preset) = BattlePreset.decode(text) {
                rows.append((Int(sqlite3_column_int64(row, 0)), String(cString: name), sqlite3_column_double(row, 2), preset, text))
            }
        }
        return rows
    }

    /// Vocations of an account (party while hunting, roster otherwise) that have a battle config on record.
    private func presetVocations(_ entry: [String: Any]) -> [(vocation: String, character: String, config: [String: Any])] {
        let battle = entry["battle"] as? [String: Any] ?? [:]
        let party = ((entry["state"] as? [String: Any])?["party"] as? [[String: Any]]) ?? (entry["roster"] as? [[String: Any]]) ?? []
        var seen = Set<String>()
        return party.compactMap { member in
            guard let vocation = member["vocation"] as? String else { return nil }
            let base = SkillAdvisor.baseVocation(vocation).uppercased()
            guard seen.insert(base).inserted, let config = battle.first(where: { $0.key.uppercased() == base })?.value as? [String: Any]
            else { return nil }
            return (base, member["name"] as? String ?? BattlePreset.vocationLabel(base), config)
        }
    }

    private func huntTitle(_ entry: [String: Any]) -> (id: Int?, title: String) {
        guard entry["status"] as? String == "hunting", let id = number(entry["huntId"]).map({ Int($0) }) else { return (nil, "") }
        return (id, catalog.hunt(id: id)?.title ?? "Hunt #\(id)")
    }

    private func uniqueName(_ wanted: String) -> String {
        let existing = Set(presetRows().map(\.name))
        guard existing.contains(wanted) else { return wanted }
        var n = 2
        while existing.contains("\(wanted) (\(n))") { n += 1 }
        return "\(wanted) (\(n))"
    }

    private func cleanName(_ name: String?) -> String? {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
    }

    public func presetsJSON(canWrite: Bool) -> Data {
        queue.sync {
            let library = presetRows().map { row -> [String: Any] in
                ["id": row.id, "name": row.name, "vocation": row.preset.vocation, "huntId": row.preset.huntId as Any,
                 "huntTitle": row.preset.huntTitle, "createdAt": row.createdAt * 1000, "text": row.text, "steps": row.preset.steps()]
            }
            let accounts = live.enumerated().map { index, entry -> [String: Any] in
                let hunt = huntTitle(entry)
                return ["index": index, "label": names[index], "huntTitle": hunt.title,
                        "vocations": presetVocations(entry).map { ["vocation": $0.vocation, "character": $0.character,
                                                                   "name": BattlePreset.defaultName(huntTitle: hunt.title, vocation: $0.vocation)] }]
            }
            return json(["canWrite": canWrite, "presets": library, "accounts": accounts])
        }
    }

    public func savePreset(account: Int, vocation: String, name: String?) -> Result<Int, PresetError> {
        queue.sync {
            guard (0..<accountCount).contains(account) else { return .failure(.message("Conta inválida.")) }
            let entry = live[account]
            let base = SkillAdvisor.baseVocation(vocation).uppercased()
            guard let found = presetVocations(entry).first(where: { $0.vocation == base }) else {
                return .failure(.message("Ainda não há configuração de batalha desta conta. Recarregue o jogo para o app lê-la."))
            }
            let hunt = huntTitle(entry)
            let preset = BattlePreset(vocation: base, huntId: hunt.id, huntTitle: hunt.title, config: found.config)
            guard !(preset.config["skills"] as? [Any] ?? []).compactMap({ $0 as? String }).isEmpty else {
                return .failure(.message("A configuração de batalha está sem skills de ataque."))
            }
            return insertPreset(preset, name: cleanName(name) ?? BattlePreset.defaultName(huntTitle: hunt.title, vocation: base))
        }
    }

    public func importPreset(text: String, name: String?) -> Result<Int, PresetError> {
        queue.sync {
            switch BattlePreset.decode(text) {
            case .failure(let error): return .failure(.message(error.message))
            case .success(let preset):
                return insertPreset(preset, name: cleanName(name) ?? BattlePreset.defaultName(huntTitle: preset.huntTitle, vocation: preset.vocation))
            }
        }
    }

    private func insertPreset(_ preset: BattlePreset, name: String) -> Result<Int, PresetError> {
        let text = preset.encoded()
        if let duplicate = presetRows().first(where: { $0.text == text }) {
            return .failure(.message("Este preset já está salvo como \"\(duplicate.name)\"."))
        }
        run("INSERT INTO presets (name, vocation, hunt_id, hunt_title, text, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            [.text(uniqueName(name)), .text(preset.vocation), .int(preset.huntId ?? 0), .text(preset.huntTitle), .text(text),
             .double(now().timeIntervalSince1970)])
        var id = 0
        query("SELECT last_insert_rowid()", []) { id = Int(sqlite3_column_int64($0, 0)) }
        return .success(id)
    }

    public func renamePreset(id: Int, name: String) -> Result<Void, PresetError> {
        queue.sync {
            guard let clean = cleanName(name) else { return .failure(.message("Informe um nome.")) }
            run("UPDATE presets SET name = ? WHERE id = ?", [.text(clean), .int(id)])
            return .success(())
        }
    }

    public func deletePreset(id: Int) { queue.sync { run("DELETE FROM presets WHERE id = ?", [.int(id)]) } }

    /// The battle setup a finished hunt ran with, per vocation, and what changed since another hunt (`compare`).
    public func huntSetup(id: Int, compare: Int?) -> Data {
        queue.sync {
            func setup(_ rowid: Int) -> [String: [String: Any]]? {
                var found: [String: [String: Any]]?
                query("SELECT summary FROM runs WHERE rowid = ?", [.int(rowid)]) { row in
                    guard let text = sqlite3_column_text(row, 0),
                          let summary = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any]
                    else { return }
                    found = (summary["setup"] as? [String: Any])?.compactMapValues { $0 as? [String: Any] }
                }
                return found
            }
            guard let mine = setup(id) else { return json(["error": "Esta hunt foi gravada antes do app guardar o setup."]) }
            let other = compare.flatMap(setup)
            let vocations = ["KNIGHT", "PALADIN", "SORCERER", "DRUID", "MONK"].filter { mine[$0] != nil || other?[$0] != nil }
            let rows = vocations.map { vocation -> [String: Any] in
                var row: [String: Any] = ["vocation": vocation, "label": BattlePreset.vocationLabel(vocation)]
                let preset = mine[vocation].map { BattlePreset(vocation: vocation, huntId: nil, huntTitle: "", config: $0) }
                row["steps"] = preset?.steps() ?? []
                if let other {
                    if let preset, let before = other[vocation] { row["differences"] = preset.differences(from: before) }
                    else { row["differences"] = [preset == nil ? "Não estava nesta hunt" : "Não estava na outra hunt"] }
                }
                return row
            }
            return json(["vocations": rows, "compared": other != nil])
        }
    }

    /// Differences from the account's current configuration, validation and the modeled damage of both.
    public func presetComparison(id: Int, account: Int) -> Data {
        queue.sync {
            guard let row = presetRows().first(where: { $0.id == id }), (0..<accountCount).contains(account) else {
                return json(["error": "Preset não encontrado."])
            }
            let entry = live[account]
            let preset = row.preset
            var result: [String: Any] = ["steps": preset.steps()]
            let current = presetVocations(entry).first { $0.vocation == preset.vocation }
            if let current { result["differences"] = preset.differences(from: current.config) }
            else { result["notice"] = "Esta conta não tem um personagem \(BattlePreset.vocationLabel(preset.vocation)) para comparar." }

            let members = skillMembers(entry).filter { SkillAdvisor.baseVocation($0.vocation).uppercased() == preset.vocation }
            let skills = (preset.config["skills"] as? [Any] ?? []).compactMap { $0 as? String }
            var warnings: [String] = []
            for name in skills {
                if let spell = spells.spell(named: name) {
                    if let member = members.first, !spells.castable(spell, vocation: member.vocation, level: member.level) {
                        warnings.append("\(name) exige level \(spell.level) ou é de outra vocação (\(member.name) é level \(member.level)).")
                    }
                } else if !spells.spells.isEmpty {
                    warnings.append("\(name) não está no catálogo de magias de dano (pode ser runa ou suporte).")
                }
            }
            result["warnings"] = warnings
            let kills = ((entry["analyzer"] as? [String: Any])?["kills"] as? [String: Any])?.compactMapValues { number($0) } ?? [:]
            if let member = members.first, kills.values.reduce(0, +) >= 20 {
                let context = SkillAdvisor.Context(spells: spells, creatures: creatures, kills: kills, crowd: calibration.crowd)
                var minimum: [String: Int] = [:]
                for (key, value) in preset.config["minCreatures"] as? [String: Any] ?? [:] { minimum[key] = (value as? Int) ?? 1 }
                let candidate = SkillAdvisor.Member(name: member.name, vocation: member.vocation, level: member.level, melee: member.melee,
                                                    distance: member.distance, magic: member.magic, attack: member.attack,
                                                    kit: skills.filter { spells.spell(named: $0) != nil }, minCreatures: minimum)
                let now = SkillAdvisor.simulate(kit: member.kit, member: member, context: context).damagePerSecond
                let then = SkillAdvisor.simulate(kit: candidate.kit, member: candidate, context: context).damagePerSecond
                result["damage"] = ["current": now * calibration.factor, "preset": then * calibration.factor, "character": member.name]
            }
            return json(result)
        }
    }
}
