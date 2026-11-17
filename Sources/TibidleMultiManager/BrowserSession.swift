import AppKit
import TibidleCore
import WebKit

/// One game page bound to a fixed, persistent website data store.
final class BrowserSession: NSObject {
    static let gameURL = URL(string: "https://play.tibidle.com/")!

    /// A page that keeps crashing is left alone after this many reloads in `crashWindow`.
    static let maxCrashReloads = 3
    static let crashWindow: TimeInterval = 600

    let account: Int
    let webView: WKWebView
    var onStatus: ((String) -> Void)?
    /// The page needs the player (an alert from the game): the window shows this account first.
    var onNeedsAttention: (() -> Void)?
    var displayName: () -> String = { "" }
    private var popups: [NSWindow] = []
    private let dashboard: DashboardStore
    private var crashes: [Date] = []

    init(account: Int, dashboard: DashboardStore) {
        self.account = account
        self.dashboard = dashboard
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: CollectorScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let handler = DashboardMessageHandler(account: account, store: dashboard)
        configuration.userContentController.add(handler, name: CollectorScript.handlerName)
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: ProfileIdentity.identifiers[account])
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Keep pages running at full speed when they are hidden behind another tab.
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        super.init()
        // Login popups share this configuration (WebKit requires it), script and handler included: only this page counts.
        handler.page = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func start() { webView.load(URLRequest(url: Self.gameURL)) }

    func reload() {
        if webView.url == nil { start() } else { webView.reload() }
    }

    /// Deletes every cookie and storage entry of this account's profile only, then reloads.
    func clearProfile(completion: @escaping () -> Void) {
        closePopups()
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            self?.start()
            completion()
        }
    }

    static let canMute: Bool = WKWebView.instancesRespond(to: NSSelectorFromString("_setPageMuted:"))

    /// WKWebView has no public mute API; this uses the long-standing WebKit SPI when present.
    func setMuted(_ muted: Bool) {
        let selector = NSSelectorFromString("_setPageMuted:")
        guard webView.responds(to: selector) else { return }
        typealias SetMuted = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(webView.method(for: selector), to: SetMuted.self)(webView, selector, muted ? 1 : 0)
    }

    func closePopups() { popups.forEach { $0.close() } }
}

extension BrowserSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView { onStatus?("Carregando…") }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView { onStatus?("Página carregada") }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportFailure(webView, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportFailure(webView, error)
    }

    private func reportFailure(_ webView: WKWebView, _ error: Error) {
        guard webView === self.webView, (error as NSError).code != NSURLErrorCancelled else { return }
        onStatus?("Falha de conexão (\(error.localizedDescription)) — use Recarregar")
    }

    /// The page's process died (out of memory, a WebKit crash): tell the dashboard and load it again, unless it keeps dying.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        dashboard.markCrashed(account: account)
        let now = Date()
        crashes = crashes.filter { now.timeIntervalSince($0) < Self.crashWindow } + [now]
        guard crashes.count <= Self.maxCrashReloads else {
            onStatus?("A página caiu \(crashes.count) vezes em 10 min — use Recarregar")
            return
        }
        onStatus?("Navegador interrompido — recarregando…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }
}

extension BrowserSession: WKUIDelegate {
    /// Login popups (Google, Discord…) share the account's data store through `configuration`.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        guard url == nil || url?.scheme == "https" || url?.absoluteString == "about:blank" else { return nil }
        let popupView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 780), configuration: configuration)
        popupView.navigationDelegate = self
        popupView.uiDelegate = self
        let window = NSWindow(contentRect: popupView.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = popupView
        window.title = "\(displayName()) — \(url?.host ?? "")"
        window.delegate = self
        if let parent = webView.window { window.setFrameOrigin(NSPoint(x: parent.frame.midX - 300, y: parent.frame.midY - 390)) }
        popups.append(window)
        let observation = popupView.observe(\.url) { [weak self, weak window] view, _ in
            if let host = view.url?.host { window?.title = "\(self?.displayName() ?? "") — \(host)" }
        }
        objc_setAssociatedObject(window, &observationKey, observation, .OBJC_ASSOCIATION_RETAIN)
        window.makeKeyAndOrderFront(nil)
        return popupView
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.first { $0.contentView === webView }?.close()
    }

    /// The game's alert/confirm/prompt as a sheet on the window of the page that asked, with its account selected first:
    /// a modal panel would stop the whole app (the other accounts' windows, the notifier) until someone clicked.
    private func present(_ alert: NSAlert, for webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if webView === self.webView { onNeedsAttention?() }
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = displayName()
        alert.informativeText = message
        present(alert, for: webView) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = displayName()
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")
        present(alert, for: webView) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = displayName()
        alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")
        present(alert, for: webView) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
}

private var observationKey = 0

/// Receives the collector's whitelisted hunt data. Kept separate from the session because
/// WKUserContentController retains its handlers.
private final class DashboardMessageHandler: NSObject, WKScriptMessageHandler {
    let account: Int
    let store: DashboardStore
    weak var page: WKWebView?

    init(account: Int, store: DashboardStore) {
        self.account = account
        self.store = store
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === page, message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == BrowserSession.gameURL.host,
              let json = message.body as? String else { return }
        store.ingest(account: account, json: json)
    }
}

extension BrowserSession: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        (window.contentView as? WKWebView)?.stopLoading()
        popups.removeAll { $0 === window }
    }
}
