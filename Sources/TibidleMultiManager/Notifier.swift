import AppKit
import TibidleCore
import UserNotifications

/// Posts a macOS notification the first time something in the dashboard's attention list appears
/// (mission ready, streak at risk, bag full, hunt ended badly, …) and keeps the count of items on the Dock icon.
/// Nothing leaves the Mac.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let defaultsKey = "notificationsEnabled"
    /// The same item is not notified again within this time: an item that blinks out for a moment (a reconnect) or a risk
    /// going back and forth around its threshold would otherwise ring each time. Day-long items wait longer.
    private static let cooldown: TimeInterval = 3600
    private static let dayLong: Set<String> = ["ready", "streak", "login"]
    private static let dayLongCooldown: TimeInterval = 12 * 3600

    private let store: DashboardStore
    private let work = DispatchQueue(label: "TibidleMultiManager.Notifier", qos: .utility)
    private var timer: Timer?
    private var seen: Set<String> = []
    private var notified: [String: Date] = [:]
    private var primed = false
    /// Right after the Mac wakes, every page looks silent until it reconnects: no notifications until then.
    private var quietUntil = Date.distantPast
    private static let wakeQuiet: TimeInterval = 90
    /// A click on a notification: the account it is about.
    var onOpen: ((Int) -> Void)?

    /// Notifications need a real app bundle; `swift run` has none.
    private var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    init(store: DashboardStore) {
        self.store = store
        super.init()
    }

    func start() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = self
        if enabled { requestAuthorization() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.quietUntil = Date().addingTimeInterval(Self.wakeQuiet)
        }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        // Common modes: keeps ticking while a menu is open or a window is being resized.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if value { requestAuthorization() }
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Builds the attention list away from the main thread (it reads the store), then posts on the main thread.
    private func tick() {
        work.async { [weak self] in
            guard let self else { return }
            let items = store.attention()
            DispatchQueue.main.async { self.handle(items) }
        }
    }

    private func handle(_ items: [AttentionItem]) {
        let urgent = items.filter { $0.level != "info" }.count
        NSApp.dockTile.badgeLabel = urgent > 0 ? "\(urgent)" : nil
        // Keeps what was seen before the sleep, so what is really new after the reconnect is still notified.
        guard Date() >= quietUntil else { return }
        defer { seen = Set(items.map(\.key)); primed = true }
        let now = Date()
        notified = notified.filter { now.timeIntervalSince($0.value) < Self.dayLongCooldown }
        // The first pass only records what already exists, so opening the app doesn't fire a burst.
        guard primed else { for item in items { notified[item.key] = now }; return }
        guard enabled else { return }
        for item in items where item.notify && !seen.contains(item.key) {
            let wait = Self.dayLong.contains(item.kind) ? Self.dayLongCooldown : Self.cooldown
            if let last = notified[item.key], now.timeIntervalSince(last) < wait { continue }
            notified[item.key] = now
            post(item)
        }
    }

    private func post(_ item: AttentionItem) {
        let content = UNMutableNotificationContent()
        content.title = "Tibidle"
        content.body = item.text
        content.sound = item.level == "bad" ? .default : nil
        content.userInfo = ["account": item.account]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.key, content: content, trigger: nil))
    }

    // A click on the notification brings the app forward on that account.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let account = response.notification.request.content.userInfo["account"] as? Int {
            DispatchQueue.main.async { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.onOpen?(account)
            }
        }
        completionHandler()
    }

    // Show the banner even while the manager is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
