import AppKit

/// Development host: shows the screensaver view in an ordinary window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var window: NSWindow?
    private(set) var appMenu: NSMenu?
    private(set) var rainView: MatrixRainView?

    /// Unit tests are hosted by this app; don't open a window under them.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        guard !Self.isRunningTests else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Matrix Rain"
        window.center()
        if let view = MatrixRainView(frame: window.contentLayoutRect, isPreview: false) {
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            view.startAnimation()
            rainView = view
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func showOptions(_ sender: Any?) {
        guard let window, let sheet = rainView?.configureSheet else { return }
        window.beginSheet(sheet)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let options = NSMenuItem(title: "Options…", action: #selector(showOptions(_:)), keyEquivalent: ",")
        options.target = self
        appMenu.addItem(options)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Matrix Rain Host",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
        self.appMenu = appMenu
    }
}
