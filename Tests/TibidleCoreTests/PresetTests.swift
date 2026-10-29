import XCTest
@testable import TibidleCore

final class PresetTests: XCTestCase {
    let config: [String: Any] = [
        "skills": ["Ultimate Ice Strike", "Ice Strike", NSNull()],
        "minCreatures": ["Ice Strike": 2, "Ultimate Ice Strike": 1],
        "heals": [["name": "Exura Vita", "percent": 60], NSNull()],
        "manaPotion": ["name": "Great Mana Potion", "percent": 30],
        "supports": ["Utamo Vita", NSNull()],
        "ammo": "Arrow",
    ]

    func preset() -> BattlePreset { BattlePreset(vocation: "DRUID", huntId: 10, huntTitle: "Dragon Lair", config: config) }

    func testRoundTripKeepsEverything() {
        let text = preset().encoded()
        XCTAssertTrue(text.hasPrefix("tbp1."))
        guard case .success(let decoded) = BattlePreset.decode(text) else { return XCTFail("decode failed") }
        XCTAssertEqual(decoded, preset())
        XCTAssertEqual(decoded.huntTitle, "Dragon Lair")
        XCTAssertEqual((decoded.config["minCreatures"] as? [String: Int])?["Ice Strike"], 2)
    }

    func testDetectsTamperingTruncationAndGarbage() {
        let text = preset().encoded()
        var parts = text.split(separator: ".").map(String.init)
        var body = Array(parts[1]); body[5] = body[5] == "A" ? "B" : "A"; parts[1] = String(body)
        XCTAssertEqual(BattlePreset.decode(parts.joined(separator: ".")), .failure(.checksum))
        XCTAssertEqual(BattlePreset.decode(String(text.dropLast(12))), .failure(.format))
        XCTAssertEqual(BattlePreset.decode("hello"), .failure(.format))
        XCTAssertEqual(BattlePreset.decode("tbp9.abc.00000000"), .failure(.version))
        XCTAssertEqual(BattlePreset.decode(String(repeating: "a", count: 30_000)), .failure(.tooLarge))
        XCTAssertNotNil(try? BattlePreset.decode("  \n" + text + " \n").get(), "whitespace around a pasted text is fine")
    }

    func testImportedContentIsSanitised() {
        let hostile: [String: Any] = [
            "skills": (0..<40).map { "Skill \($0)" } + [String(repeating: "x", count: 500)],
            "minCreatures": ["A": 99, "B": -4, "C": "many", "D": true],
            "heals": [["name": "Heal", "percent": 900], ["percent": 50], "junk"],
            "evil": "<script>alert(1)</script>", "who": 1000,
        ]
        let cleaned = BattlePreset.normalize(hostile)
        XCTAssertEqual((cleaned["skills"] as? [Any])?.count, 12)
        XCTAssertNil(cleaned["evil"])
        let minimum = cleaned["minCreatures"] as! [String: Int]
        XCTAssertEqual(minimum["A"], 8); XCTAssertEqual(minimum["B"], 1); XCTAssertNil(minimum["C"])
        XCTAssertEqual(((cleaned["heals"] as! [Any])[0] as! [String: Any])["percent"] as? Int, 100)
        XCTAssertTrue((cleaned["heals"] as! [Any])[1] is NSNull)
        XCTAssertEqual(cleaned["who"] as? Int, 99)
    }

    func testStepsAndDifferencesReadLikeInstructions() {
        let steps = preset().steps()
        XCTAssertEqual(steps.first, "Ataque 1: Ultimate Ice Strike — usar com 1 criatura ou mais")
        XCTAssertTrue(steps.contains("Ataque 2: Ice Strike — usar com 2 criaturas ou mais"))
        XCTAssertTrue(steps.contains("Cura 1: Exura Vita abaixo de 60% de vida"))
        XCTAssertTrue(steps.contains("Poção de mana: Great Mana Potion abaixo de 30% de mana"))
        let current: [String: Any] = ["skills": ["Ice Strike", "Flame Strike"], "minCreatures": ["Ice Strike": 4], "heals": [], "supports": []]
        let diff = preset().differences(from: current)
        XCTAssertTrue(diff.contains("Adiciona a skill Ultimate Ice Strike"))
        XCTAssertTrue(diff.contains("Remove a skill Flame Strike"))
        XCTAssertTrue(diff.contains("Ice Strike: mínimo de criaturas de 4 para 2"))
        XCTAssertTrue(diff.contains("Curas: de nenhuma para Exura Vita abaixo de 60%"))
        XCTAssertTrue(diff.contains("Poção de mana: de nenhuma para Great Mana Potion abaixo de 30% de mana"))
        XCTAssertTrue(diff.contains("Suportes: de nenhuma para Utamo Vita"))
        var later = config
        later["heals"] = [["name": "Exura Vita", "percent": 85]]
        later["manaPotion"] = ["name": "Strong Mana Potion", "percent": 50]
        XCTAssertEqual(BattlePreset(vocation: "DRUID", huntId: 10, huntTitle: "", config: later).differences(from: config), [
            "Exura Vita: cura abaixo de 85% de vida (era 60%)",
            "Poção de mana: de Great Mana Potion abaixo de 30% de mana para Strong Mana Potion abaixo de 50% de mana",
        ])
        XCTAssertEqual(preset().differences(from: config), [], "identical configs differ in nothing")
    }

    func testDefaultNameUsesTheHuntTitle() {
        XCTAssertEqual(BattlePreset.defaultName(huntTitle: "Dragon Lair", vocation: "DRUID"), "Dragon Lair · Druid")
        XCTAssertEqual(BattlePreset.defaultName(huntTitle: "", vocation: "KNIGHT"), "Sem hunt · Knight")
    }

    // MARK: Store and router

    func makeStore() -> DashboardStore {
        let store = DashboardStore(databaseURL: nil)
        store.setHuntCatalog(HuntCatalog(json: Data(#"{"hunts":[{"id":10,"title":"Dragon Lair","island":"Edron","monsters":["Dragon"]}]}"#.utf8))!)
        let battle = #"{"DRUID":{"skills":["Ice Strike","Flame Strike"],"minCreatures":{"Ice Strike":2},"heals":[{"name":"Exura","percent":50}],"manaPotion":{"name":"Mana Potion","percent":20},"supports":[]}}"#
        store.ingest(account: 0, json: #"{"type":"welcome","data":{"battleConfigs":\#(battle),"roster":[{"name":"Mossy","vocation":"Elder Druid","level":120}]}}"#)
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":10,"state":{"party":[{"name":"Mossy","vocation":"Elder Druid","level":120}]}}}"#)
        return store
    }

    func json(_ data: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: data) as! [String: Any] }

    func testSavingNamesThePresetAfterTheHuntAndKeepsVersions() {
        let store = makeStore()
        guard case .success = store.savePreset(account: 0, vocation: "Elder Druid", name: nil) else { return XCTFail("save failed") }
        XCTAssertEqual(store.savePreset(account: 0, vocation: "DRUID", name: nil), .failure(.message("Este preset já está salvo como \"Dragon Lair · Druid\".")))
        // Same name with a different config gets a numbered suffix.
        store.ingest(account: 0, json: #"{"type":"resume","data":{"huntId":10,"battleConfigs":{"DRUID":{"skills":["Flame Strike"],"minCreatures":{}}},"state":{}}}"#)
        guard case .success = store.savePreset(account: 0, vocation: "DRUID", name: "  ") else { return XCTFail("second save failed") }
        let names = (json(store.presetsJSON(canWrite: true))["presets"] as! [[String: Any]]).map { $0["name"] as! String }
        XCTAssertEqual(Set(names), ["Dragon Lair · Druid", "Dragon Lair · Druid (2)"])
    }

    func testLibraryRenameDeleteAndImport() {
        let store = makeStore()
        guard case .success(let id) = store.savePreset(account: 0, vocation: "DRUID", name: "Meu preset") else { return XCTFail() }
        let listed = (json(store.presetsJSON(canWrite: true))["presets"] as! [[String: Any]])[0]
        XCTAssertEqual(listed["huntTitle"] as? String, "Dragon Lair")
        let text = listed["text"] as! String
        XCTAssertEqual(store.importPreset(text: text, name: nil), .failure(.message("Este preset já está salvo como \"Meu preset\".")))
        guard case .success = store.renamePreset(id: id, name: "Renomeado") else { return XCTFail("rename failed") }
        XCTAssertEqual((json(store.presetsJSON(canWrite: true))["presets"] as! [[String: Any]])[0]["name"] as? String, "Renomeado")
        store.deletePreset(id: id)
        XCTAssertTrue((json(store.presetsJSON(canWrite: true))["presets"] as! [Any]).isEmpty)
        guard case .success = store.importPreset(text: text, name: nil) else { return XCTFail("import after delete failed") }
        XCTAssertEqual(store.importPreset(text: "tbp1.zzz.00000000", name: nil), .failure(.message(BattlePreset.DecodeError.checksum.message)))
        let account = (json(store.presetsJSON(canWrite: true))["accounts"] as! [[String: Any]])[0]
        XCTAssertEqual(((account["vocations"] as! [[String: Any]])[0])["name"] as? String, "Dragon Lair · Druid")
    }

    func testWritesAreLocalOnlyAndNeedTheHeaderAndHost() {
        let store = makeStore()
        func post(_ path: String, local: Bool = true, headers: [String: String] = ["host": "localhost:8787", "x-tibidle": "1", "content-type": "application/json"],
                  body: String = #"{"account":0,"vocation":"DRUID"}"#) -> Int {
            DashboardRouter.respond(HTTPRequest(method: "POST", target: path, headers: headers, body: Data(body.utf8), isLocal: local), store: store).status
        }
        XCTAssertEqual(post("/api/presets/save"), 200)
        XCTAssertEqual(post("/api/presets/save", local: false), 403, "LAN clients cannot write")
        XCTAssertEqual(post("/api/presets/save", headers: ["host": "localhost", "content-type": "application/json"]), 403, "needs the custom header")
        XCTAssertEqual(post("/api/presets/save", headers: ["host": "evil.example", "x-tibidle": "1", "content-type": "application/json"]), 403, "DNS rebinding")
        XCTAssertEqual(post("/api/presets/save", headers: ["host": "localhost", "x-tibidle": "1", "content-type": "text/plain"]), 403)
        XCTAssertEqual(post("/api/state"), 405, "nothing else is writable")
        XCTAssertEqual(post("/api/presets/save", body: "not json"), 400)
        let big = String(repeating: "a", count: DashboardRouter.maxBody + 1)
        XCTAssertEqual(post("/api/presets/import", body: #"{"text":"\#(big)"}"#), 400)
        let lan = json(DashboardRouter.respond(HTTPRequest(method: "GET", target: "/api/presets", isLocal: false), store: store).body)
        XCTAssertEqual(lan["canWrite"] as? Bool, false)
    }

    func testSavesTheSetupOfAFinishedHunt() {
        let store = makeStore()
        store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":10,"elapsedSec":3600,"balance":1}}}"#)
        let id = (json(store.huntsJSON(limit: 1))["hunts"] as! [[String: Any]])[0]["id"] as! Int
        guard case .success = store.savePresetFromHunt(id: id, vocation: "Elder Druid", name: nil) else { return XCTFail("save failed") }
        let saved = (json(store.presetsJSON(canWrite: true))["presets"] as! [[String: Any]])[0]
        XCTAssertEqual(saved["name"] as? String, "Dragon Lair · Druid")
        XCTAssertTrue((saved["steps"] as! [String]).contains("Ataque 1: Ice Strike — usar com 2 criaturas ou mais"))
        XCTAssertEqual(store.savePresetFromHunt(id: id, vocation: "KNIGHT", name: nil), .failure(.message("Esta hunt não guardou o setup do Knight.")))
        XCTAssertEqual(store.savePresetFromHunt(id: 999, vocation: "DRUID", name: nil), .failure(.message("Hunt não encontrada.")))
    }

    func testComparisonShowsDifferencesStepsAndWarnings() {
        let store = makeStore()
        store.setSpellCatalog(SpellCatalog(json: Data(SkillTests.spellsJSON.utf8))!)
        let other = BattlePreset(vocation: "DRUID", huntId: 10, huntTitle: "Dragon Lair",
                                 config: ["skills": ["Ice Strike", "Hell's Core"], "minCreatures": ["Ice Strike": 3]])
        guard case .success(let id) = store.importPreset(text: other.encoded(), name: "Outro") else { return XCTFail() }
        let result = json(store.presetComparison(id: id, account: 0))
        XCTAssertTrue((result["differences"] as! [String]).contains("Adiciona a skill Hell's Core"))
        XCTAssertTrue((result["warnings"] as! [String]).contains { $0.contains("Hell's Core") }, "a sorcerer-only spell warns for a druid")
        XCTAssertFalse((result["steps"] as! [String]).isEmpty)
        XCTAssertEqual(json(store.presetComparison(id: 9999, account: 0))["error"] as? String, "Preset não encontrado.")
    }
}
