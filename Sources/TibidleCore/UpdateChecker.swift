import Foundation

/// Tells the dashboard when a newer release is published on GitHub: reads the latest release once a day,
/// with no cookies or credentials, and never downloads or installs anything.
public final class UpdateChecker {
    public static let url = URL(string: "https://api.github.com/repos/flvsilva/tibidle-multi-manager-macos/releases/latest")!
    public static let interval: TimeInterval = 24 * 3600
    public static let maxBytes = 512 * 1024

    private let current: String
    private let store: DashboardStore
    private let session: URLSession
    private let queue = DispatchQueue(label: "TibidleMultiManager.UpdateChecker")
    private var timer: DispatchSourceTimer?

    public init(current: String, store: DashboardStore, session: URLSession? = nil) {
        self.current = current
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
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 30, repeating: Self.interval)
            timer.setEventHandler { [weak self] in self?.check() }
            timer.resume()
            self.timer = timer
        }
    }

    public func stop() { queue.async { [self] in timer?.cancel(); timer = nil } }

    private func check() {
        var request = URLRequest(url: Self.url)
        request.setValue("TibidleMultiManager", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self, let data, data.count <= Self.maxBytes, (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = Self.release(from: data) else { return }
            store.setUpdate(Self.isNewer(release.version, than: current) ? release : nil)
        }.resume()
    }

    /// The version and page of a GitHub "latest release" response; only github.com pages are kept.
    static func release(from data: Data) -> (version: String, url: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String, let page = object["html_url"] as? String,
              page.hasPrefix("https://github.com/") else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty, version.count <= 20, version.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return (version, page)
    }

    static func isNewer(_ version: String, than current: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }, b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
