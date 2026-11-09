import AppKit
import Metal

/// Starts the game: the window with its Metal view, and the menus; the game and the window's frame are kept when it
/// quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, GameHost {
    private var window: NSWindow?
    private var controller: GameController?
    private var aboutWindow: AboutWindow?

    private var language: Language { controller?.language ?? Settings.load().language }

    // MARK: The application

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        MainMenu.install(language, delegate: self)
        do {
            try start()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = Str.startFailed.text(language)
            alert.informativeText = String(describing: error)
            _ = alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func start() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError("This Mac has no Metal device.") }
        let window = makeWindow()
        let view = GameView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size), device: device)
        let controller = try GameController(view: view, device: device)
        controller.host = self
        view.controller = controller
        window.contentView = view
        window.makeFirstResponder(view)
        self.window = window
        self.controller = controller
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// A dark window, 1500 × 920 points or most of a smaller screen, where it was the last time if it was.
    private func makeWindow() -> NSWindow {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1500, (screen.width * 0.92).rounded()), height: min(920, (screen.height * 0.92).rounded()))
        let frame = NSRect(x: (screen.midX - size.width / 2).rounded(), y: (screen.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = Str.title.text(language)
        window.contentMinSize = NSSize(width: 900, height: 680)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.016, green: 0.017, blue: 0.022, alpha: 1)
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.acceptsMouseMovedEvents = true
        _ = window.setFrameAutosaveName("Go3D.MainWindow")
        return window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.save()
        controller?.stopWorkers()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: The window

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        controller?.save()
        aboutWindow?.close()
    }

    /// A press is not left hanging when another window or application takes the mouse.
    func windowDidResignKey(_ notification: Notification) {
        controller?.cancelPointer()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        controller?.requestFrame()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        controller?.requestFrame()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        controller?.requestFrame()
    }

    // MARK: The game's requests

    var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func showAbout() {
        let about = aboutWindow ?? AboutWindow.make()
        aboutWindow = about
        about.show(language, over: window)
    }

    func languageChanged() {
        MainMenu.install(language, delegate: self)
        window?.title = Str.title.text(language)
        aboutWindow?.update(language)
    }

    // MARK: The menus

    @objc func performCommand(_ sender: NSMenuItem) {
        guard let command = GameCommand(rawValue: sender.tag) else { return }
        controller?.perform(command)
    }

    @objc func showAboutWindow(_ sender: Any?) {
        showAbout()
    }

    @objc func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        switch action {
        case #selector(performCommand(_:)):
            guard let controller, let command = GameCommand(rawValue: menuItem.tag) else { return false }
            menuItem.state = controller.isChecked(command) ? .on : .off
            return controller.canPerform(command)
        case #selector(toggleFullScreen(_:)):
            menuItem.state = isFullScreen ? .on : .off
            return window != nil
        default:
            return true
        }
    }
}
