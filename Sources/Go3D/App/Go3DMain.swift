import AppKit

/// The entry point: an application with no nib, its menus and window made in code.
@main
@MainActor
enum Go3DMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
