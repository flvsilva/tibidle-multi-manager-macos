import Foundation

/// Something that needs the player's attention, derived from the dashboard state.
public struct AttentionItem: Equatable {
    public let key: String        // stable while the condition lasts: used to notify only once
    public let account: Int
    public let kind: String
    public let level: String      // "bad" | "warn" | "info"
    public let text: String
    public let notify: Bool

    var json: [String: Any] {
        ["key": key, "account": account, "kind": kind, "level": level, "text": text, "notify": notify]
    }
}

public enum Attention {
    static let endedWindow: Double = 60 * 60 * 1000
    static let idleAfter: Double = 15 * 60 * 1000
    /// Below this share of normal damage a spell is the wrong element for the hunt.
    static let weakElement = 0.5
    /// A member averaging less mana than this spends the hunt unable to cast (or drinking potions).
    static let starvedMana = 0.10
    static let elements = ["COMBAT_PHYSICALDAMAGE": "físico", "COMBAT_FIREDAMAGE": "fogo", "COMBAT_ENERGYDAMAGE": "energia",
                           "COMBAT_EARTHDAMAGE": "terra", "COMBAT_ICEDAMAGE": "gelo", "COMBAT_HOLYDAMAGE": "sagrado", "COMBAT_DEATHDAMAGE": "morte"]
    static let badReasons: [String: (String, String)] = [
        "death": ("bad", "morreu"), "no_gold": ("warn", "ficou sem gold"), "cap_full": ("warn", "terminou por mochila cheia"),
        "prey_resync_failed": ("warn", "falhou no prey"), "expired": ("info", "teve o tempo esgotado"),
    ]

    /// - Parameter accounts: the per-account dictionaries produced by `DashboardStore.stateJSON`.
    public static func evaluate(accounts: [[String: Any]], now: Double) -> [AttentionItem] {
        var items: [AttentionItem] = []
        for entry in accounts {
            let i = entry["index"] as? Int ?? 0
            let label = entry["label"] as? String ?? "Conta \(i + 1)"
            let status = entry["status"] as? String ?? "offline"
            let daily = entry["daily"] as? [String: Any]

            for case let mission as [String: Any] in (daily?["missions"] as? [Any]) ?? [] where mission["state"] as? String == "ready" {
                let id = mission["id"] as? String ?? ""
                items.append(AttentionItem(key: "ready|\(i)|\(id)", account: i, kind: "ready", level: "info",
                                           text: "\(label): missão \"\(mission["title"] as? String ?? "")\" concluída — resgate no jogo.", notify: true))
            }
            if let streak = daily?["streak"] as? [String: Any], streak["atRisk"] as? Bool == true {
                let open = streak["open"] as? Int ?? 0
                items.append(AttentionItem(key: "streak|\(i)|\(Int(number(daily?["dailyResetAt"])))", account: i, kind: "streak", level: "warn",
                                           text: "\(label): \(open) missão(ões) diária(s) sem resgatar e o dia fecha em breve — a sequência semanal corre risco.", notify: true))
            }
            if let claimable = daily?["loginClaimable"] as? Int, claimable > 0 {
                items.append(AttentionItem(key: "login|\(i)|\(Int(number(daily?["dailyResetAt"])))", account: i, kind: "login", level: "info",
                                           text: "\(label): recompensa do calendário de login disponível — resgate no jogo.", notify: true))
            }
            if let invasion = entry["invasion"] as? [String: Any], invasion["finished"] as? Bool != true,
               let next = invasion["next"] as? [String: Any], let start = next["startAt"] as? Double {
                let minutes = Int(ceil((start - now) / 60000))
                let name = invasion["name"] as? String ?? "Invasão"
                if invasion["joined"] as? Bool != true, next["live"] as? Bool != true {
                    items.append(AttentionItem(key: "invasion-join|\(i)|\(Int(start))", account: i, kind: "invasion", level: "warn",
                                               text: "\(label): \(name) — inscrição aberta e você ainda não entrou (próxima janela \(clock(start))).", notify: true))
                } else if invasion["joined"] as? Bool == true, minutes <= 15, minutes >= 0, next["live"] as? Bool != true {
                    items.append(AttentionItem(key: "invasion-soon|\(i)|\(Int(start))", account: i, kind: "invasion", level: "info",
                                               text: "\(label): \(name) começa em \(max(minutes, 1)) min.", notify: true))
                }
            }
            for alert in (entry["supply"] as? [String: Any])?["alerts"] as? [[String: String]] ?? [] {
                guard let kind = alert["kind"], let text = alert["text"] else { continue }
                items.append(AttentionItem(key: "\(kind)|\(i)|\(alert["level"] ?? "")", account: i, kind: kind,
                                           level: alert["level"] ?? "warn", text: "\(label): \(text)", notify: alert["level"] == "bad"))
            }
            if status == "hunting", let insights = entry["insights"] as? [String: Any], let drop = insights["drop"] as? Double,
               drop >= HuntInsights.dropWarning, let reference = insights["reference"] as? [String: Any],
               let changes = insights["changes"] as? [[String: Any]], !changes.isEmpty {
                let who = changes.compactMap { $0["label"] as? String }.joined(separator: ", ")
                items.append(AttentionItem(key: "setup-drop|\(i)|\(reference["id"] ?? "")", account: i, kind: "setup", level: "warn",
                                           text: "\(label): lucro/h \(Int((drop * 100).rounded()))% abaixo da sua melhor hunt recente aqui " +
                                                 "(\(money(reference["profitPerHour"]))/h, \(day(number(reference["endedAt"])))), com outro setup (\(who)).",
                                           notify: true))
            }
            if status == "hunting" { items += skillItems(entry, account: i, label: label) }
            if status != "hunting", let summary = entry["lastSummary"] as? [String: Any],
               let reason = summary["reason"] as? String, let (level, what) = badReasons[reason] {
                let endedAt = number(summary["endedAt"])
                if now - endedAt <= endedWindow {
                    items.append(AttentionItem(key: "ended|\(i)|\(Int(endedAt))", account: i, kind: "ended", level: level,
                                               text: "\(label): a hunt \(what) e a conta está parada.", notify: level != "info"))
                }
            }
            if status == "city", now - number(entry["statusSince"]) >= idleAfter, number(entry["statusSince"]) > 0 {
                let minutes = Int((now - number(entry["statusSince"])) / 60000)
                items.append(AttentionItem(key: "idle|\(i)|\(Int(number(entry["statusSince"])))", account: i, kind: "idle", level: "info",
                                           text: "\(label): parada na cidade há \(minutes) min.", notify: false))
            }
            if status == "replaced" {
                items.append(AttentionItem(key: "replaced|\(i)|\(Int(number(entry["statusSince"])))", account: i, kind: "replaced", level: "warn",
                                           text: "\(label): a sessão foi aberta em outro lugar.", notify: true))
            }
        }
        let order = ["bad": 0, "warn": 1, "info": 2]
        return items.sorted { (order[$0.level] ?? 3, $0.account) < (order[$1.level] ?? 3, $1.account) }
    }

    /// From the skill analysis: spells the monsters resist that still fire, and members out of mana.
    static func skillItems(_ entry: [String: Any], account i: Int, label: String) -> [AttentionItem] {
        var items: [AttentionItem] = []
        let members = (entry["skills"] as? [String: Any])?["members"] as? [[String: Any]] ?? []
        let sameName = Set(members.compactMap { $0["name"] as? String }).count <= 1
        for member in members {
            let vocation = BattlePreset.vocationLabel(member["vocation"] as? String ?? "")
            let who = sameName ? vocation : "\(member["name"] as? String ?? "") (\(vocation))"
            for skill in member["skills"] as? [[String: Any]] ?? [] {
                let multiplier = number(skill["multiplier"])
                guard multiplier < weakElement, number(skill["dps"]) > 0, let name = skill["name"] as? String else { continue }
                let element = elements[skill["element"] as? String ?? ""].map { " (\($0))" } ?? ""
                items.append(AttentionItem(key: "element|\(i)|\(vocation)|\(name)", account: i, kind: "element", level: "warn",
                                           text: "\(label) · \(who): \(name)\(element) causa só \(Int((multiplier * 100).rounded()))% do dano nos monstros desta hunt " +
                                                 "— troque por uma de outro elemento.",
                                           notify: false))
            }
            if let average = member["manaAverage"] as? Double, average < starvedMana, number(member["manaPerMinute"]) > 0 {
                items.append(AttentionItem(key: "mana|\(i)|\(vocation)", account: i, kind: "mana", level: "warn",
                                           text: "\(label) · \(who) passa a hunt com \(Int((average * 100).rounded()))% de mana em média — tire a skill mais cara " +
                                                 "ou suba o mínimo de criaturas dela.",
                                           notify: false))
            }
        }
        return items
    }

    private static func clock(_ ms: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    private static func day(_ ms: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    static func money(_ value: Any?) -> String {
        let n = number(value)
        if abs(n) >= 1_000_000 { return String(format: "%.1fkk", n / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if abs(n) >= 1000 { return "\(Int((n / 1000).rounded()))k" }
        return "\(Int(n.rounded()))"
    }

    private static func number(_ value: Any?) -> Double {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }
}
