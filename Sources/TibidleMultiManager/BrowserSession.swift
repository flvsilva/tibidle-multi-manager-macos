import AppKit
import TibidleCore
import WebKit

/// One game page bound to a fixed, persistent website data store.
final class BrowserSession: NSObject {
    static let gameURL = URL(string: "https://play.tibidle.com/")!

    let account: Int
    let webView: WKWebView
    var onStatus: ((String) -> Void)?
    var displayName: () -> String = { "" }
    private var popups: [NSWindow] = []

    init(account: Int) {
        self.account = account
        let configuration = WKWebViewConfiguration()
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
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func start() { webView.load(URLRequest(url: Self.gameURL)) }

    func reload() {
        if webView.url == nil { start() } else { webView.reload() }
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { onStatus?("Navegador interrompido — use Recarregar") }
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

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = displayName()
        alert.informativeText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = displayName()
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
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
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }
}

private var observationKey = 0

extension BrowserSession: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        (window.contentView as? WKWebView)?.stopLoading()
        popups.removeAll { $0 === window }
    }
}
