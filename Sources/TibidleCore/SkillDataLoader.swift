import Foundation

/// Fetches the game's public spell list and, on demand, the elemental resistances of the monsters being
/// hunted (`/bestiary/creature?name=`). No cookies or credentials; everything is cached on disk.
public final class SkillDataLoader {
    public static let spellsMaxAge: TimeInterval = 24 * 3600
    public static let maxBytes = 2 * 1024 * 1024
    static let selectMaxBytes = 4 * 1024 * 1024
    static let perTick = 4

    private let spellsURL: URL
    private let creaturesURL: URL
    private let selectURL: URL
    private let store: DashboardStore
    private let session: URLSession
    private let queue = DispatchQueue(label: "TibidleMultiManager.SkillDataLoader")
    private var timer: DispatchSourceTimer?
    private var catalog = CreatureCatalog()
    private var failed: [String: Date] = [:]
    private var inFlight = Set<String>()
    /// The spell list and the hunts list: when a download fails, the next try waits longer each time (5 min up to 6 h)
    /// instead of every tick, and only one request per list is out at a time. Touched on `queue` only.
    private var listInFlight = Set<String>()
    private var listFailures: [String: Int] = [:]
    private var listNextTry: [String: Date] = [:]

    public init(directory: URL, store: DashboardStore, session: URLSession? = nil) {
        spellsURL = directory.appendingPathComponent("spells-catalog.json")
        creaturesURL = directory.appendingPathComponent("creatures-cache.json")
        selectURL = directory.appendingPathComponent("hunts-select-cache.json")
        self.store = store
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: configuration)
        }
    }

    public func start() {
        queue.async { [self] in
            if let data = try? Data(contentsOf: spellsURL), let spells = SpellCatalog(json: data) { store.setSpellCatalog(spells) }
            if let data = try? Data(contentsOf: creaturesURL),
               let saved = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] {
                for (name, elements) in saved { catalog.add(name: name, elements: elements) }
                store.setCreatures(catalog)
            }
            if let data = try? Data(contentsOf: selectURL), let hunts = HuntBestiaryCatalog(json: data) { apply(hunts) }
            refreshSpellsIfStale()
            refreshSelectIfStale()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 10)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    public func stop() { queue.async { [self] in timer?.cancel(); timer = nil } }

    private func get(_ url: URL, limit: Int = SkillDataLoader.maxBytes, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("TibidleMultiManager", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, _ in
            guard let data, data.count <= limit, (response as? HTTPURLResponse)?.statusCode == 200 else { return completion(nil) }
            completion(data)
        }.resume()
    }

    /// Whether a list may be downloaded now (on `queue`); marks it in flight when it may.
    private func mayFetch(_ list: String) -> Bool {
        guard !listInFlight.contains(list), Date() >= listNextTry[list] ?? .distantPast else { return false }
        listInFlight.insert(list)
        return true
    }

    /// Records how a list download went (on `queue`).
    private func finished(_ list: String, ok: Bool) {
        listInFlight.remove(list)
        if ok {
            listFailures[list] = nil
            listNextTry[list] = nil
        } else {
            let failures = (listFailures[list] ?? 0) + 1
            listFailures[list] = failures
            listNextTry[list] = Date().addingTimeInterval(min(300 * pow(2, Double(failures - 1)), 6 * 3600))
        }
    }

    private func refreshSpellsIfStale() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: spellsURL.path)[.modificationDate]) as? Date
        if let modified, Date().timeIntervalSince(modified) < Self.spellsMaxAge { return }
        guard mayFetch("spells") else { return }
        get(SpellCatalog.url) { [weak self] data in
            guard let self else { return }
            guard let data, let spells = SpellCatalog(json: data) else { queue.async { self.finished("spells", ok: false) }; return }
            store.setSpellCatalog(spells)
            try? FileManager.default.createDirectory(at: spellsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: spellsURL, options: .atomic)
            queue.async { self.finished("spells", ok: true) }
        }
    }

    private func apply(_ hunts: HuntBestiaryCatalog) {
        store.setBestiaries(hunts)
        for (name, map) in hunts.creatures.resistance where !catalog.knows(name) { catalog.resistance[name] = map }
        // The maps' monster lists are the only source of health, which weighs each monster's share of the damage.
        for (name, health) in hunts.creatures.health { catalog.health[name] = health }
        store.setCreatures(catalog)
    }

    private func refreshSelectIfStale() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: selectURL.path)[.modificationDate]) as? Date
        if let modified, Date().timeIntervalSince(modified) < Self.spellsMaxAge { return }
        guard mayFetch("select") else { return }
        get(HuntBestiaryCatalog.url, limit: Self.selectMaxBytes) { [weak self] data in
            guard let self else { return }
            guard let data, let hunts = HuntBestiaryCatalog(json: data) else { queue.async { self.finished("select", ok: false) }; return }
            self.queue.async {
                self.finished("select", ok: true)
                self.apply(hunts)
                try? FileManager.default.createDirectory(at: self.selectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: self.selectURL, options: .atomic)
            }
        }
    }

    private func tick() {
        refreshSpellsIfStale()
        refreshSelectIfStale()
        let now = Date()
        failed = failed.filter { now.timeIntervalSince($0.value) < 3600 }
        let wanted = store.missingCreatures().filter { failed[$0] == nil && !inFlight.contains($0) }.prefix(Self.perTick)
        for name in wanted {
            var components = URLComponents(string: "https://play.tibidle.com/bestiary/creature")!
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            guard let url = components.url else { continue }
            inFlight.insert(name)
            get(url) { [weak self] data in
                guard let self else { return }
                self.queue.async {
                    self.inFlight.remove(name)
                    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let elements = object["elements"] as? [[String: Any]] else {
                        self.failed[name] = Date()
                        return
                    }
                    self.catalog.add(name: name, elements: elements)
                    self.store.setCreatures(self.catalog)
                    self.persist()
                }
            }
        }
    }

    private func persist() {
        var saved: [String: [[String: Any]]] = [:]
        for (name, map) in catalog.resistance {
            saved[name] = map.map { ["type": $0.key, "percent": $0.value] }
        }
        try? FileManager.default.createDirectory(at: creaturesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: saved) { try? data.write(to: creaturesURL, options: .atomic) }
    }
}
