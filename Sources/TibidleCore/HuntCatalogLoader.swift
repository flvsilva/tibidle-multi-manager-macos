import Foundation

/// Keeps the dashboard's hunt catalog fresh: the cached copy loads at once (works offline),
/// then the game's public list is refreshed at most every `maxAge`. The request carries no
/// cookies or credentials.
public final class HuntCatalogLoader {
    public static let maxAge: TimeInterval = 12 * 3600
    public static let maxBytes = 4 * 1024 * 1024

    private let cacheURL: URL
    private let store: DashboardStore
    private let session: URLSession
    private let queue = DispatchQueue(label: "TibidleMultiManager.HuntCatalogLoader")
    private var timer: DispatchSourceTimer?
    /// Failed downloads in a row: without a cached copy the next try comes sooner than the hourly check (1, 2, 4… min).
    private var failures = 0

    public init(cacheURL: URL, store: DashboardStore, session: URLSession? = nil) {
        self.cacheURL = cacheURL
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
            if let data = try? Data(contentsOf: cacheURL), let catalog = HuntCatalog(json: data) {
                store.setHuntCatalog(catalog)
            }
            refreshIfStale()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 3600, repeating: 3600)
            timer.setEventHandler { [weak self] in self?.refreshIfStale() }
            timer.resume()
            self.timer = timer
        }
    }

    private func refreshIfStale() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate]) as? Date
        if let modified, Date().timeIntervalSince(modified) < Self.maxAge { return }
        var request = URLRequest(url: HuntCatalog.url)
        request.setValue("TibidleMultiManager", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            guard let data, data.count <= Self.maxBytes, (response as? HTTPURLResponse)?.statusCode == 200,
                  let catalog = HuntCatalog(json: data) else {
                self.queue.async {
                    self.failures += 1
                    // With a cached copy the hourly timer is enough; with none, the dashboard has no map names yet.
                    guard modified == nil else { return }
                    let wait = min(60 * pow(2, Double(self.failures - 1)), 3600)
                    self.queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.refreshIfStale() }
                }
                return
            }
            self.queue.async { self.failures = 0 }
            store.setHuntCatalog(catalog)
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }.resume()
    }

    public func stop() { queue.async { [self] in timer?.cancel(); timer = nil } }
}
