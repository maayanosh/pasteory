import AppKit

/// Composition root: builds the whole object graph in dependency order with
/// `let`s, so the compiler — not initialization-order luck — proves that
/// everything is wired before use.
@MainActor
public final class AppComposition {
    public let settings: Settings
    public let store: Store
    public let monitor: ClipboardMonitor
    public let pasteService: PasteService
    public let appState: AppState
    public let panelController: PanelController
    public let settingsController: SettingsWindowController

    public init() {
        let settings = Settings()
        let store = Store()
        let monitor = ClipboardMonitor(store: store, settings: settings)
        let pasteService = PasteService(store: store, monitor: monitor)
        let appState = AppState(store: store, settings: settings, pasteService: pasteService)

        self.settings = settings
        self.store = store
        self.monitor = monitor
        self.pasteService = pasteService
        self.appState = appState
        self.panelController = PanelController(appState: appState, pasteService: pasteService)
        self.settingsController = SettingsWindowController(settings: settings, store: store)
    }
}
