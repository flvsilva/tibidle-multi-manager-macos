import AppKit
import TibidleCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        let controller = MainWindowController(store: SettingsStore(root: SettingsStore.defaultRoot))
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { controller?.save() }

    @objc private func selectPosition(_ sender: NSMenuItem) { controller?.selectPosition(sender.tag) }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        let appName = "Tibidle Multi-Manager"

        let app = submenu(main, appName)
        app.addItem(withTitle: "Sobre o \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Ocultar \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(item("Ocultar outros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(withTitle: "Mostrar todos", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Encerrar \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Needed so ⌘C/⌘V/⌘A work inside the game's login forms.
        let edit = submenu(main, "Editar")
        edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(item("Refazer", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecionar tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let view = submenu(main, "Visualizar")
        view.addItem(item("Alternar 1 / 4 telas", #selector(MainWindowController.toggleLayout(_:)), "g", [.command, .shift]))
        view.addItem(.separator())
        view.addItem(withTitle: "Aumentar zoom", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+")
        view.addItem(withTitle: "Diminuir zoom", action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Tamanho real", action: #selector(MainWindowController.zoomReset(_:)), keyEquivalent: "0")
        view.addItem(.separator())
        view.addItem(item("Tela cheia", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let accounts = submenu(main, "Contas")
        for position in 0..<accountCount {
            let entry = NSMenuItem(title: "Posição \(position + 1)", action: #selector(selectPosition(_:)), keyEquivalent: "\(position + 1)")
            entry.target = self
            entry.tag = position
            accounts.addItem(entry)
        }
        accounts.addItem(.separator())
        accounts.addItem(withTitle: "Recarregar conta", action: #selector(MainWindowController.reloadSelected(_:)), keyEquivalent: "r")
        accounts.addItem(withTitle: "Limpar sessão da conta…", action: #selector(MainWindowController.clearSession(_:)), keyEquivalent: "")
        accounts.addItem(item("Ligar/desligar som", #selector(MainWindowController.toggleSound(_:)), "m", [.command, .shift]))

        let window = submenu(main, "Janela")
        window.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window
        return main
    }

    private func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers
        return entry
    }
}
