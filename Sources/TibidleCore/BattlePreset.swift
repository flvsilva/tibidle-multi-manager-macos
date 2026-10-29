import Foundation

/// A shareable snapshot of one vocation's battle configuration (skills order, creature thresholds,
/// heals, potions, supports). Text form: `tbp1.<base64url(deflate(json))>.<crc32>`.
public struct BattlePreset: Equatable {
    public static let prefix = "tbp1"
    static let maxText = 24 * 1024
    static let maxJSON = 64 * 1024

    public var vocation: String       // KNIGHT, PALADIN, SORCERER, DRUID, MONK
    public var huntId: Int?
    public var huntTitle: String
    public var config: [String: Any]

    public init(vocation: String, huntId: Int?, huntTitle: String, config: [String: Any]) {
        self.vocation = vocation
        self.huntId = huntId
        self.huntTitle = huntTitle
        self.config = Self.normalize(config)
    }

    public static func == (a: BattlePreset, b: BattlePreset) -> Bool {
        a.vocation == b.vocation && a.huntId == b.huntId && a.huntTitle == b.huntTitle
            && NSDictionary(dictionary: a.config).isEqual(to: b.config)
    }

    // MARK: Config normalisation (also the import safety net: unknown keys and odd types are dropped)

    static func text(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(64))
    }

    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    public static func normalize(_ raw: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out["skills"] = Array((raw["skills"] as? [Any] ?? []).prefix(12)).map { Self.text($0).map { $0 as Any } ?? NSNull() }
        var minimum: [String: Any] = [:]
        for (key, value) in (raw["minCreatures"] as? [String: Any] ?? [:]).prefix(16) {
            if let name = text(key), let n = number(value) { minimum[name] = max(1, min(8, Int(n))) }
        }
        out["minCreatures"] = minimum
        out["heals"] = Array((raw["heals"] as? [Any] ?? []).prefix(8)).map { item -> Any in
            guard let h = item as? [String: Any], let name = text(h["name"]) else { return NSNull() }
            var entry: [String: Any] = ["name": name]
            if let p = number(h["percent"]) { entry["percent"] = max(0, min(100, Int(p))) }
            return entry
        }
        if let potion = raw["manaPotion"] as? [String: Any] {
            var entry: [String: Any] = [:]
            if let name = text(potion["name"]) { entry["name"] = name }
            if let p = number(potion["percent"]) { entry["percent"] = max(0, min(100, Int(p))) }
            out["manaPotion"] = entry
        }
        out["supports"] = Array((raw["supports"] as? [Any] ?? []).prefix(8)).map { Self.text($0).map { $0 as Any } ?? NSNull() }
        if let ammo = text(raw["ammo"]) { out["ammo"] = ammo }
        if let who = number(raw["who"]) { out["who"] = Int(max(1, min(99, who))) }
        return out
    }

    // MARK: Text form

    public func encoded() -> String {
        var payload: [String: Any] = ["v": 1, "voc": vocation, "cfg": config, "title": huntTitle]
        if let huntId { payload["hunt"] = huntId }
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        let packed = (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
        let body = Self.base64url(packed)
        return "\(Self.prefix).\(body).\(Self.crc32hex(Data(body.utf8)))"
    }

    public enum DecodeError: Error, Equatable {
        case format, checksum, version, tooLarge, content
        public var message: String {
            switch self {
            case .format: return "Texto de preset inválido."
            case .checksum: return "O texto está incompleto ou foi alterado (checksum não confere)."
            case .version: return "Versão de preset não suportada."
            case .tooLarge: return "O preset é grande demais."
            case .content: return "O preset não tem uma configuração válida."
            }
        }
    }

    public static func decode(_ string: String) -> Result<BattlePreset, DecodeError> {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.utf8.count <= maxText else { return .failure(.tooLarge) }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == prefix, let packed = data(fromBase64url: parts[1]) else {
            return .failure(parts.first == prefix ? .format : (parts.first?.hasPrefix("tbp") == true ? .version : .format))
        }
        guard crc32hex(Data(parts[1].utf8)) == parts[2].lowercased() else { return .failure(.checksum) }
        guard let json = (try? (packed as NSData).decompressed(using: .zlib) as Data), json.count <= maxJSON,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return .failure(.format) }
        guard (object["v"] as? Int) == 1 else { return .failure(.version) }
        guard let vocation = (object["voc"] as? String)?.uppercased(), ["KNIGHT", "PALADIN", "SORCERER", "DRUID", "MONK"].contains(vocation),
              let config = object["cfg"] as? [String: Any] else { return .failure(.content) }
        let normalized = normalize(config)
        guard !(normalized["skills"] as? [Any] ?? []).compactMap({ $0 as? String }).isEmpty else { return .failure(.content) }
        return .success(BattlePreset(vocation: vocation, huntId: (object["hunt"] as? NSNumber)?.intValue,
                                     huntTitle: Self.text(object["title"]) ?? "", config: normalized))
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(fromBase64url text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    static func crc32hex(_ data: Data) -> String {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return String(format: "%08x", ~crc)
    }

    // MARK: Default name and manual-apply checklist

    public static func defaultName(huntTitle: String, vocation: String) -> String {
        let title = huntTitle.isEmpty ? "Sem hunt" : huntTitle
        return "\(title) · \(vocationLabel(vocation))"
    }

    public static func vocationLabel(_ vocation: String) -> String {
        ["KNIGHT": "Knight", "PALADIN": "Paladin", "SORCERER": "Sorcerer", "DRUID": "Druid", "MONK": "Monk"][vocation.uppercased()] ?? vocation
    }

    /// Human-readable steps to reproduce the preset by hand in the game's battle screen.
    public func steps() -> [String] {
        var lines: [String] = []
        let minimum = config["minCreatures"] as? [String: Any] ?? [:]
        let skills = (config["skills"] as? [Any] ?? []).compactMap { $0 as? String }
        for (index, name) in skills.enumerated() {
            let need = (minimum[name] as? Int) ?? 1
            lines.append("Ataque \(index + 1): \(name) — usar com \(need) criatura\(need == 1 ? "" : "s") ou mais")
        }
        for (index, item) in (config["heals"] as? [Any] ?? []).enumerated() {
            guard let heal = item as? [String: Any], let name = heal["name"] as? String else { continue }
            let percent = (heal["percent"] as? Int).map { " abaixo de \($0)% de vida" } ?? ""
            lines.append("Cura \(index + 1): \(name)\(percent)")
        }
        if let potion = config["manaPotion"] as? [String: Any], let name = potion["name"] as? String {
            lines.append("Poção de mana: \(name)\((potion["percent"] as? Int).map { " abaixo de \($0)% de mana" } ?? "")")
        }
        for (index, item) in (config["supports"] as? [Any] ?? []).enumerated() {
            if let name = item as? String { lines.append("Suporte \(index + 1): \(name)") }
        }
        if let ammo = config["ammo"] as? String { lines.append("Munição: \(ammo)") }
        return lines
    }

    /// What differs from another configuration of the same vocation, in plain words.
    public func differences(from current: [String: Any]) -> [String] {
        let other = BattlePreset.normalize(current)
        var out: [String] = []
        let mine = (config["skills"] as? [Any] ?? []).compactMap { $0 as? String }
        let theirs = (other["skills"] as? [Any] ?? []).compactMap { $0 as? String }
        for name in mine where !theirs.contains(name) { out.append("Adiciona a skill \(name)") }
        for name in theirs where !mine.contains(name) { out.append("Remove a skill \(name)") }
        let common = mine.filter(theirs.contains)
        if common != theirs.filter(mine.contains) { out.append("Muda a ordem de prioridade das skills") }
        let a = config["minCreatures"] as? [String: Any] ?? [:], b = other["minCreatures"] as? [String: Any] ?? [:]
        for name in common where ((a[name] as? Int) ?? 1) != ((b[name] as? Int) ?? 1) {
            out.append("\(name): mínimo de criaturas de \((b[name] as? Int) ?? 1) para \((a[name] as? Int) ?? 1)")
        }
        out += Self.healDifferences(from: Self.heals(other), to: Self.heals(config))
        let potion = Self.potion(config), previous = Self.potion(other)
        if potion != previous { out.append("Poção de mana: de \(previous ?? "nenhuma") para \(potion ?? "nenhuma")") }
        let supports = (config["supports"] as? [Any] ?? []).compactMap { $0 as? String }
        let before = (other["supports"] as? [Any] ?? []).compactMap { $0 as? String }
        if supports != before { out.append("Suportes: de \(Self.list(before)) para \(Self.list(supports))") }
        return out
    }

    private static func heals(_ config: [String: Any]) -> [(name: String, percent: Int?)] {
        (config["heals"] as? [Any] ?? []).compactMap { item in
            (item as? [String: Any]).flatMap { h in (h["name"] as? String).map { ($0, h["percent"] as? Int) } }
        }
    }

    private static func healText(_ heal: (name: String, percent: Int?)) -> String {
        heal.name + (heal.percent.map { " abaixo de \($0)%" } ?? "")
    }

    /// Same heals in the same order: one line per changed threshold; otherwise the whole list before and after.
    private static func healDifferences(from before: [(name: String, percent: Int?)], to after: [(name: String, percent: Int?)]) -> [String] {
        if before.map(\.name) == after.map(\.name) {
            return zip(before, after).compactMap { old, new in
                old.percent == new.percent ? nil
                    : "\(new.name): cura abaixo de \(new.percent.map { "\($0)%" } ?? "?") de vida (era \(old.percent.map { "\($0)%" } ?? "?"))"
            }
        }
        return ["Curas: de \(list(before.map(healText))) para \(list(after.map(healText)))"]
    }

    private static func potion(_ config: [String: Any]) -> String? {
        guard let potion = config["manaPotion"] as? [String: Any], let name = potion["name"] as? String else { return nil }
        return name + ((potion["percent"] as? Int).map { " abaixo de \($0)% de mana" } ?? "")
    }

    private static func list(_ items: [String]) -> String { items.isEmpty ? "nenhuma" : items.joined(separator: ", ") }
}
