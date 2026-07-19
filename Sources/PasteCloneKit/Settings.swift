import Foundation
import Combine
import ServiceManagement

@MainActor
public final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published public var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: "isPaused") }
    }
    @Published public var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") }
    }
    @Published public var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: "historyLimit") }
    }
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin()
        }
    }
    /// Panel background opacity, 0.3...1.0. Lower values let the windows
    /// behind the panel show through.
    @Published public var panelOpacity: Double {
        didSet { defaults.set(panelOpacity, forKey: "panelOpacity") }
    }
    /// When true, pressing Enter on a selected card also synthesizes ⌘V into
    /// the previous app instead of only copying to the clipboard.
    @Published public var pasteOnEnter: Bool {
        didSet { defaults.set(pasteOnEnter, forKey: "pasteOnEnter") }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        // object(forKey:) distinguishes "never saved" from a stored value,
        // so the defaults below don't rely on 0-sentinels.
        self.historyLimit = defaults.object(forKey: "historyLimit") == nil
            ? 500 : defaults.integer(forKey: "historyLimit")  // Int.max = Forever
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.panelOpacity = defaults.object(forKey: "panelOpacity") == nil
            ? 0.85 : min(max(defaults.double(forKey: "panelOpacity"), 0.3), 1.0)
        self.pasteOnEnter = defaults.bool(forKey: "pasteOnEnter")
    }

    private func applyLaunchAtLogin() {
        // Only works from inside a real .app bundle; ignore failures during dev.
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("PasteClone: launch-at-login change failed: \(error)")
        }
    }
}
