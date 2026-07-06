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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        let limit = defaults.integer(forKey: "historyLimit")
        self.historyLimit = limit == 0 ? 500 : limit
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        let opacity = defaults.double(forKey: "panelOpacity")
        self.panelOpacity = opacity == 0 ? 0.85 : min(max(opacity, 0.3), 1.0)
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
