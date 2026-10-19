import AppKit
import TibidleCore
import UserNotifications

/// Posts a macOS notification the first time something in the dashboard's attention list appears
/// (mission ready, streak at risk, bag full, hunt ended badly, …). Nothing leaves the Mac.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let defaultsKey = "notificationsEnabled"
    private let store: DashboardStore
    private var timer: Timer?
    private var seen: Set<String> = []
    private var primed = false

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
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if value { requestAuthorization() }
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func tick() {
        let items = store.attention()
        defer { seen = Set(items.map(\.key)); primed = true }
        // The first pass only records what already exists, so opening the app doesn't fire a burst.
        guard enabled, primed else { return }
        for item in items where item.notify && !seen.contains(item.key) { post(item) }
    }

    private func post(_ item: AttentionItem) {
        let content = UNMutableNotificationContent()
        content.title = "Tibidle"
        content.body = item.text
        content.sound = item.level == "bad" ? .default : nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.key, content: content, trigger: nil))
    }

    // Show the banner even while the manager is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
