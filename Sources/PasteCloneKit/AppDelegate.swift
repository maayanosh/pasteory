import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    var settings: Settings!
    var store: Store!
    var appState: AppState!
    var monitor: ClipboardMonitor!
    var pasteService: PasteService!
    var panelController: PanelController!
    var settingsController: SettingsWindowController!
    var hotKey: HotKey!
    var statusItem: NSStatusItem!

    public nonisolated override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        settings = Settings(loginController: MacLaunchAtLogin())
        store = Store()
        store.historyLimit = settings.historyLimit
        monitor = ClipboardMonitor(store: store, settings: settings)
        pasteService = PasteService(store: store, monitor: monitor)
        appState = AppState(store: store, settings: settings, paster: pasteService)
        panelController = PanelController(appState: appState, pasteService: pasteService)
        settingsController = SettingsWindowController(settings: settings, store: store)

        monitor.start()

        hotKey = HotKey() // ⇧⌘V
        hotKey.handler = { [weak self] in self?.panelController.toggle() }

        setupStatusItem()

        // First launch: reveal the panel once, so a fresh install isn't just
        // a silent new menu-bar icon. The empty state explains the hotkey.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasShownWelcome") {
            defaults.set(true, forKey: "hasShownWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.panelController.showPanel()
            }
        }

        // Debug hook so the panel can be shown without the global hotkey
        // (used by automated verification).
        if ProcessInfo.processInfo.environment["PASTECLONE_SHOW_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.panelController.showPanel()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clap"
        )

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Clap", action: #selector(openPanel), keyEquivalent: "v")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)

        let pauseItem = NSMenuItem(title: "Pause Capturing", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func openPanel() {
        panelController.showPanel()
    }

    @objc private func togglePause() {
        settings.isPaused.toggle()
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func clearHistory() {
        store.clearHistory()
    }
}

extension AppDelegate: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(togglePause) }?
            .title = settings.isPaused ? "Resume Capturing" : "Pause Capturing"
    }
}
