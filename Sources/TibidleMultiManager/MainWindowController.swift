import AppKit
import TibidleCore

extension ViewLayout {
    var title: String {
        switch self {
        case .single: return "Tela normal"
        case .featured: return "1 + 3"
        case .grid: return "4 telas"
        }
    }

    var symbol: String {
        switch self {
        case .single: return "▣"
        case .featured: return "◧"
        case .grid: return "▦"
        }
    }

    var help: String {
        switch self {
        case .single: return "Mostrar só a conta selecionada"
        case .featured: return "A primeira aba grande e as outras três ao lado • arraste uma aba para o começo para trocar a principal"
        case .grid: return "As quatro contas em grade 2 × 2"
        }
    }

    /// Menu items and buttons carry the case as their tag.
    var tag: Int { Self.allCases.firstIndex(of: self)! }
    init?(tag: Int) {
        guard Self.allCases.indices.contains(tag) else { return nil }
        self = Self.allCases[tag]
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    private let store: SettingsStore
    private let dashboard: DashboardStore
    private var settings: AppSettings
    private var sessions: [BrowserSession] = []
    private var tabs: [TabButton] = []
    private var panes: [PaneView] = []
    private var statuses = Array(repeating: "Preparando…", count: accountCount)
    private var selected = 0
    private var clickMonitor: Any?
    private var statusTimer: Timer?
    /// The dashboard's network access was switched in the menu (true: the network can open it).
    var onDashboardNetworkChange: ((Bool) -> Void)?
    var dashboardOnNetwork: Bool { settings.dashboardOnNetwork }

    private let tabStrip = NSStackView()
    private let host = BrowserHostView()
    private let nameField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "Preparando os quatro perfis…")
    private lazy var layoutButtons: [FlatButton] = ViewLayout.allCases.map { layout in
        let button = FlatButton(title: "\(layout.symbol)  \(layout.title)", target: self, action: #selector(setLayout(_:)))
        button.tag = layout.tag
        button.toolTip = layout.help
        button.padding.width = 10
        return button
    }
    private lazy var soundButton = FlatButton(title: "", target: self, action: #selector(toggleSound(_:)))
    private lazy var clearButton = FlatButton(title: "Limpar sessão", target: self, action: #selector(clearSession(_:)))
    private lazy var reloadButton = FlatButton(title: "↻  Recarregar", target: self, action: #selector(reloadSelected(_:)))

    private let dashboardLabel = NSTextField(labelWithString: "")

    init(store: SettingsStore, dashboard: DashboardStore) {
        self.store = store
        self.dashboard = dashboard
        settings = store.load()
        dashboard.setAccountNames(settings.accounts.map(\.name))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 940),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tibidle Multi-Manager"
        window.minSize = NSSize(width: 800, height: 560)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.window
        super.init(window: window)
        window.delegate = self
        buildInterface()
        if let screen = window.screen ?? NSScreen.main {
            // A saved frame bigger than the screen (or off it) comes back to the screen's visible area.
            let visible = screen.visibleFrame
            if !window.setFrameUsingName("MainWindow") || window.frame.width > visible.width || window.frame.height > visible.height
                || !visible.intersects(window.frame) {
                window.setFrame(visible, display: false)
            }
        }
        window.setFrameAutosaveName("MainWindow")

        for account in 0..<accountCount {
            let session = BrowserSession(account: account, dashboard: dashboard)
            session.displayName = { [unowned self] in settings.accounts[account].name }
            session.onStatus = { [weak self] text in self?.setStatus(account, text) }
            session.onNeedsAttention = { [weak self] in if self?.selected != account { self?.select(account) } }
            session.setMuted(settings.accounts[account].muted)
            panes[account].content.addSubview(session.webView)
            sessions.append(session)
        }
        applyTabOrder()
        applyColorSpace()
        select(settings.selectedTab)
        // The selected account loads first; the others follow a moment apart, not all at once.
        sessions[selected].start()
        for (step, account) in (0..<accountCount).filter({ $0 != selected }).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 * Double(step + 1)) { [weak self] in self?.sessions[account].start() }
        }
        let statusTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refreshStatusDots() }
        RunLoop.main.add(statusTimer, forMode: .common)
        self.statusTimer = statusTimer

        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.selectPane(under: event)
            return event
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Interface

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        for account in 0..<accountCount {
            let tab = TabButton(title: settings.accounts[account].name, target: self, action: #selector(tabClicked(_:)))
            tab.tag = account
            tab.siblings = tabStrip
            tab.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
            tab.onDrop = { [unowned self] target in moveTab(account, onto: target.tag) }
            tabs.append(tab)
            let header = FlatButton(title: settings.accounts[account].name, target: self, action: #selector(tabClicked(_:)))
            header.tag = account
            header.toolTip = "Selecionar esta conta para os controles de nome, som e recarregar"
            panes.append(PaneView(header: header))
        }
        tabStrip.orientation = .horizontal
        tabStrip.spacing = 6

        let layoutStrip = NSStackView(views: layoutButtons)
        layoutStrip.orientation = .horizontal
        layoutStrip.spacing = 4
        let topBar = bar(Theme.topBar, [tabStrip, NSView(), layoutStrip], height: 52)

        let nameLabel = NSTextField(labelWithString: "Nome da conta")
        nameLabel.textColor = Theme.mutedText
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(saveName(_:))
        nameField.textColor = Theme.fieldText
        nameField.backgroundColor = Theme.fieldBackground
        nameField.drawsBackground = true
        nameField.isBezeled = false
        nameField.focusRingType = .none
        nameField.font = .systemFont(ofSize: 13)
        nameField.wantsLayer = true
        nameField.layer?.borderColor = Theme.fieldBorder.cgColor
        nameField.layer?.borderWidth = 1
        nameField.layer?.cornerRadius = 3
        nameField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        clearButton.toolTip = "Sair desta conta apagando cookies e dados salvos somente deste perfil"
        reloadButton.toolTip = "Recarregar somente esta conta (⌘R)"
        soundButton.toolTip = BrowserSession.canMute ? "Ligar ou desligar o som desta conta" : "Esta versão do macOS não permite silenciar a página"
        let saveButton = FlatButton(title: "Salvar nome", target: self, action: #selector(saveName(_:)))
        let toolBar = bar(Theme.toolBar, [nameLabel, nameField, saveButton, NSView(), clearButton, soundButton, reloadButton], height: 50)
        toolBar.setCustomSpacing(10, after: nameLabel)

        statusLabel.textColor = Theme.mutedText
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let hint = NSTextField(labelWithString: "⌘1–4  alternar contas")
        hint.textColor = Theme.hintText
        dashboardLabel.textColor = Theme.hintText
        dashboardLabel.isSelectable = true
        let statusBar = bar(Theme.topBar, [statusLabel, NSView(), dashboardLabel, hint], height: 28)
        statusBar.setCustomSpacing(18, after: dashboardLabel)

        host.panes = panes
        let column = NSStackView(views: [topBar, divider(), toolBar, divider(), host, statusBar])
        column.orientation = .vertical
        column.spacing = 0
        column.alignment = .width
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            column.topAnchor.constraint(equalTo: contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        host.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func bar(_ color: NSColor, _ views: [NSView], height: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = color.cgColor
        stack.heightAnchor.constraint(equalToConstant: height).isActive = true
        views.filter { type(of: $0) == NSView.self }.forEach { $0.setContentHuggingPriority(.init(1), for: .horizontal) }
        return stack
    }

    private func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.divider.cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    // MARK: Selection and layout

    func select(_ account: Int) {
        selected = account
        settings.selectedTab = account
        host.panes = settings.tabOrder.map { panes[$0] }
        host.viewLayout = settings.layout
        host.selectedPosition = settings.tabOrder.firstIndex(of: account) ?? 0
        applyZoom()
        for i in 0..<accountCount {
            let isSelected = i == account
            for button in [tabs[i], panes[i].header] {
                button.fill = isSelected ? Theme.selectedBackground : Theme.tabBackground
                button.stroke = isSelected ? Theme.selectedBorder : Theme.tabBorder
            }
        }
        nameField.stringValue = settings.accounts[account].name
        if sessions.indices.contains(account) { window?.makeFirstResponder(sessions[account].webView) }
        refreshControls()
    }

    /// Selects the position in visual order (⌘1–4).
    func selectPosition(_ position: Int) {
        guard settings.tabOrder.indices.contains(position) else { return }
        select(settings.tabOrder[position])
    }

    private func selectPane(under event: NSEvent) {
        guard event.window === window, settings.layout != .single else { return }
        let point = host.convert(event.locationInWindow, from: nil)
        if let index = panes.firstIndex(where: { !$0.isHidden && $0.frame.contains(point) }), index != selected {
            select(index)
        }
    }

    /// Each page gets the zoom its account had at this pane size (a small 1 + 3 pane remembers its own).
    private func applyZoom() {
        guard sessions.count == accountCount else { return }
        for (position, account) in settings.tabOrder.enumerated() {
            let zoom = settings.accounts[account].zoom(for: PaneSize.of(position: position, in: settings.layout))
            if sessions[account].webView.pageZoom != zoom { sessions[account].webView.pageZoom = zoom }
        }
    }

    private func paneSize(of account: Int) -> PaneSize {
        PaneSize.of(position: settings.tabOrder.firstIndex(of: account) ?? 0, in: settings.layout)
    }

    private func setZoom(_ zoom: Double) {
        let value = min(max((zoom * 10).rounded() / 10, AccountSettings.zoomRange.lowerBound), AccountSettings.zoomRange.upperBound)
        settings.accounts[selected].zoom[paneSize(of: selected).rawValue] = value == 1 ? nil : value
        sessions[selected].webView.pageZoom = value
        save()
    }

    private func refreshStatusDots() {
        dashboard.statuses { [weak self] list in
            guard let self else { return }
            for (account, status) in list.enumerated() where account < accountCount {
                let color = Theme.statusColor(status)
                tabs[account].dot = color
                panes[account].header.dot = color
            }
        }
    }

    private func applyColorSpace() {
        window?.colorSpace = settings.srgbColors ? .sRGB : nil
    }

    private func applyTabOrder() {
        tabStrip.setViews(settings.tabOrder.map { tabs[$0] }, in: .leading)
        for (position, account) in settings.tabOrder.enumerated() {
            tabs[account].toolTip = "Arraste para reorganizar • ⌘\(position + 1)"
        }
    }

    private func moveTab(_ account: Int, onto target: Int) {
        TabOrder.move(&settings.tabOrder, account: account, onto: target)
        applyTabOrder()
        select(selected)
        save()
    }

    private func refreshControls() {
        for button in layoutButtons {
            let isCurrent = button.tag == settings.layout.tag
            button.fill = isCurrent ? Theme.selectedBackground : Theme.tabBackground
            button.stroke = isCurrent ? Theme.selectedBorder : Theme.tabBorder
        }
        statusLabel.stringValue = "\(settings.accounts[selected].name)  •  \(statuses[selected])"
        soundButton.title = settings.accounts[selected].muted ? "Som: desligado" : "Som: ligado"
        soundButton.isEnabled = BrowserSession.canMute
    }

    private func setStatus(_ account: Int, _ text: String) {
        statuses[account] = text
        if account == selected { refreshControls() }
    }

    // MARK: Actions

    @objc private func tabClicked(_ sender: NSButton) { select(sender.tag) }

    /// From a layout button or a Visualizar menu item; the tag says which layout.
    @objc func setLayout(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag ?? 0
        guard let layout = ViewLayout(tag: tag) else { return }
        apply(layout)
    }

    /// ⇧⌘G: Tela normal → 1 + 3 → 4 telas → Tela normal.
    @objc func nextLayout(_ sender: Any?) {
        apply(ViewLayout(tag: settings.layout.tag + 1) ?? ViewLayout.allCases[0])
    }

    private func apply(_ layout: ViewLayout) {
        guard layout != settings.layout else { return }
        settings.layout = layout
        select(selected)
        save()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(setLayout(_:)): menuItem.state = menuItem.tag == settings.layout.tag ? .on : .off
        case #selector(toggleSRGB(_:)): menuItem.state = settings.srgbColors ? .on : .off
        case #selector(toggleDashboardNetwork(_:)): menuItem.state = settings.dashboardOnNetwork ? .on : .off
        default: break
        }
        return true
    }

    /// Draws the pages in sRGB instead of the monitor's profile: on some monitors the GPU process spends most of its time
    /// converting colors. Takes effect at once; the colors may look slightly different on a wide-gamut screen.
    @objc func toggleSRGB(_ sender: Any?) {
        settings.srgbColors.toggle()
        applyColorSpace()
        save()
    }

    @objc func toggleDashboardNetwork(_ sender: Any?) {
        settings.dashboardOnNetwork.toggle()
        save()
        onDashboardNetworkChange?(settings.dashboardOnNetwork)
    }

    @objc func toggleSound(_ sender: Any?) {
        settings.accounts[selected].muted.toggle()
        sessions[selected].setMuted(settings.accounts[selected].muted)
        save()
        refreshControls()
    }

    @objc func reloadSelected(_ sender: Any?) { sessions[selected].reload() }

    @objc func clearSession(_ sender: Any?) {
        guard let window else { return }
        let account = selected
        let alert = NSAlert()
        alert.messageText = "Limpar a sessão de \(settings.accounts[account].name)?"
        alert.informativeText = "Apaga login, cookies e dados do site salvos somente neste perfil. As outras contas não são afetadas. Você precisará entrar de novo nesta aba."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Limpar sessão")
        alert.addButton(withTitle: "Cancelar")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            setStatus(account, "Limpando sessão…")
            sessions[account].clearProfile { [weak self] in self?.setStatus(account, "Sessão limpa — entre novamente") }
        }
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(sessions[selected].webView.pageZoom + 0.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(sessions[selected].webView.pageZoom - 0.1) }
    @objc func zoomReset(_ sender: Any?) { setZoom(1) }

    @objc private func saveName(_ sender: Any?) {
        let name = String(nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AppSettings.maxNameLength))
        guard !name.isEmpty else { nameField.stringValue = settings.accounts[selected].name; return }
        settings.accounts[selected].name = name
        nameField.stringValue = name
        tabs[selected].title = name
        panes[selected].header.title = name
        dashboard.setAccountNames(settings.accounts.map(\.name))
        save()
        refreshControls()
    }

    func showDashboardAddress(_ urls: [String]) {
        if settings.dashboardOnNetwork {
            dashboardLabel.stringValue = urls.first.map { "Dashboard: \($0)" } ?? ""
        } else {
            dashboardLabel.stringValue = urls.last.map { "Dashboard: \($0) (só neste Mac)" } ?? ""
        }
        dashboardLabel.toolTip = urls.joined(separator: "\n")
    }

    func controlTextDidChange(_ notification: Notification) {
        if nameField.stringValue.count > AppSettings.maxNameLength {
            nameField.stringValue = String(nameField.stringValue.prefix(AppSettings.maxNameLength))
        }
    }

    func save() {
        do { try store.save(settings) } catch {
            guard let window else { return }
            let alert = NSAlert()
            alert.messageText = "Não foi possível salvar os nomes e preferências."
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        save()
        statusTimer?.invalidate()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        sessions.forEach { $0.closePopups() }
    }
}
