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
            CREATE TABLE IF NOT EXISTS hunts (account INTEGER, hunt_id INTEGER, ended_at REAL, summary TEXT,
                UNIQUE(account, hunt_id));
            """)
        run("DELETE FROM samples WHERE ts < ?", [.double(self.now().timeIntervalSince1970 - Self.retention)])
    }

    deinit { sqlite3_close(db) }

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
            if let huntId = number(summary["huntId"]), let text = jsonString(summary) {
                run("INSERT OR REPLACE INTO hunts (account, hunt_id, ended_at, summary) VALUES (?, ?, ?, ?)",
                    [.int(account), .int(Int(huntId)), .double(date.timeIntervalSince1970), .text(text)])
            }
        case "session_takeover", "session_replaced":
            entry["status"] = "replaced"
        case "_closed":
            entry["status"] = "offline"
        default:
            return
        }
        entry["updatedAt"] = date.timeIntervalSince1970 * 1000
        live[account] = entry
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
            let accounts = live.enumerated().map { index, entry -> [String: Any] in
                var out = entry
                out["index"] = index
                out["label"] = names[index]
                return out
            }
            return json(["generatedAt": now().timeIntervalSince1970 * 1000, "accounts": accounts])
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
            query("SELECT account, summary FROM hunts ORDER BY ended_at DESC LIMIT ?", [.int(limit)]) { row in
                guard let text = sqlite3_column_text(row, 1),
                      var summary = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any]
                else { return }
                let account = Int(sqlite3_column_int(row, 0))
                summary["account"] = account
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
