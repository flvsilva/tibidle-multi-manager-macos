import AppKit
import TibidleCore

final class MainWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let store: SettingsStore
    private var settings: AppSettings
    private var sessions: [BrowserSession] = []
    private var tabs: [TabButton] = []
    private var panes: [PaneView] = []
    private var statuses = Array(repeating: "Preparando…", count: accountCount)
    private var selected = 0
    private var clickMonitor: Any?

    private let tabStrip = NSStackView()
    private let host = BrowserHostView()
    private let nameField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "Preparando os quatro perfis…")
    private lazy var layoutButton = FlatButton(title: "", target: self, action: #selector(toggleLayout(_:)))
    private lazy var soundButton = FlatButton(title: "", target: self, action: #selector(toggleSound(_:)))
    private lazy var clearButton = FlatButton(title: "Limpar sessão", target: self, action: #selector(clearSession(_:)))
    private lazy var reloadButton = FlatButton(title: "↻  Recarregar", target: self, action: #selector(reloadSelected(_:)))

    init(store: SettingsStore) {
        self.store = store
        settings = store.load()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 940),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tibidle Multi-Manager"
        window.minSize = NSSize(width: 800, height: 560)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.window
        super.init(window: window)
        window.delegate = self
        buildInterface()
        if !window.setFrameUsingName("MainWindow"), let screen = window.screen ?? NSScreen.main {
            window.setFrame(screen.visibleFrame, display: false)
        }
        window.setFrameAutosaveName("MainWindow")

        for account in 0..<accountCount {
            let session = BrowserSession(account: account)
            session.displayName = { [unowned self] in settings.accounts[account].name }
            session.onStatus = { [weak self] text in self?.setStatus(account, text) }
            session.setMuted(settings.accounts[account].muted)
            panes[account].content.addSubview(session.webView)
            sessions.append(session)
        }
        applyTabOrder()
        select(settings.selectedTab)
        // The selected account loads first, then the others.
        ([selected] + (0..<accountCount).filter { $0 != selected }).forEach { sessions[$0].start() }

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

        layoutButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        layoutButton.toolTip = "Alternar entre uma conta e quatro contas em grade"
        let topBar = bar(Theme.topBar, [tabStrip, NSView(), layoutButton], height: 52)

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
        let statusBar = bar(Theme.topBar, [statusLabel, NSView(), hint], height: 28)

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
        host.grid = settings.gridView
        host.selectedPosition = settings.tabOrder.firstIndex(of: account) ?? 0
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
        guard event.window === window, settings.gridView else { return }
        let point = host.convert(event.locationInWindow, from: nil)
        if let index = panes.firstIndex(where: { !$0.isHidden && $0.frame.contains(point) }), index != selected {
            select(index)
        }
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
        layoutButton.title = settings.gridView ? "▣  Tela normal" : "▦  4 telas"
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

    @objc func toggleLayout(_ sender: Any?) {
        settings.gridView.toggle()
        select(selected)
        save()
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

    @objc func zoomIn(_ sender: Any?) { sessions[selected].webView.pageZoom = min(sessions[selected].webView.pageZoom + 0.1, 3) }
    @objc func zoomOut(_ sender: Any?) { sessions[selected].webView.pageZoom = max(sessions[selected].webView.pageZoom - 0.1, 0.3) }
    @objc func zoomReset(_ sender: Any?) { sessions[selected].webView.pageZoom = 1 }

    @objc private func saveName(_ sender: Any?) {
        let name = String(nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AppSettings.maxNameLength))
        guard !name.isEmpty else { nameField.stringValue = settings.accounts[selected].name; return }
        settings.accounts[selected].name = name
        nameField.stringValue = name
        tabs[selected].title = name
        panes[selected].header.title = name
        save()
        refreshControls()
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
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        sessions.forEach { $0.closePopups() }
    }
}
