import AppKit

/// The menu bar, in the game's language; it is made again when the language changes. The game's commands carry
/// their `GameCommand` in the tag; the single keys of the game are not menu shortcuts, the view reads them.
@MainActor
enum MainMenu {
    static func install(_ language: Language, delegate: AppDelegate) {
        func tr(_ id: Str) -> String { id.text(language) }
        let bar = NSMenu()

        func submenu(_ title: String) -> NSMenu {
            let menu = NSMenu(title: title)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            bar.addItem(item)
            return menu
        }
        func item(_ title: String, _ action: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                  target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }
        func command(_ menu: NSMenu, _ title: String, _ command: GameCommand, key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
            let entry = item(title, #selector(AppDelegate.performCommand(_:)), key: key, modifiers: modifiers, target: delegate)
            entry.tag = command.rawValue
            menu.addItem(entry)
        }

        let app = submenu(tr(.title))
        app.addItem(item(tr(.menuAbout), #selector(AppDelegate.showAboutWindow(_:)), target: delegate))
        app.addItem(.separator())
        app.addItem(item(tr(.menuHide), #selector(NSApplication.hide(_:)), key: "h"))
        app.addItem(item(tr(.menuHideOthers), #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        app.addItem(item(tr(.menuShowAll), #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item(tr(.menuQuit), #selector(NSApplication.terminate(_:)), key: "q"))

        let game = submenu(tr(.menuGame))
        command(game, tr(.menuNewGame), .newGame, key: "n")
        game.addItem(.separator())
        command(game, tr(.menuUndo), .undo, key: "z")
        command(game, tr(.menuRedo), .redo, key: "z", modifiers: [.command, .shift])
        game.addItem(.separator())
        command(game, tr(.menuPass), .pass)
        command(game, tr(.menuResign) + "…", .resign)
        game.addItem(.separator())
        command(game, tr(.menuHint), .hint)
        command(game, tr(.menuEstimate), .estimate)
        command(game, tr(.menuAccept), .accept)
        game.addItem(.separator())
        command(game, tr(.menuCopy), .copyGame, key: "c")
        command(game, tr(.menuPaste), .pasteGame, key: "v")

        let view = submenu(tr(.menuView))
        command(view, tr(.menuFlip), .flip)
        command(view, tr(.menuTopView), .topView)
        command(view, tr(.menuResetView), .resetView)
        view.addItem(.separator())
        command(view, tr(.menuPanel), .panel)
        command(view, tr(.menuTheme), .nextTheme)
        view.addItem(.separator())
        // The window's own action, so that AppKit does not add an item of its own; the delegate takes it, to keep the title.
        view.addItem(item(tr(.menuFullScreen), #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control], target: delegate))

        let window = submenu(tr(.menuWindow))
        window.addItem(item(tr(.menuMinimize), #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        window.addItem(item(tr(.menuZoom), #selector(NSWindow.performZoom(_:))))

        let help = submenu(tr(.menuHelp))
        command(help, tr(.menuGameHelp), .help, key: "?")

        NSApp.mainMenu = bar
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
    }
}
