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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        let limit = defaults.integer(forKey: "historyLimit")
        self.historyLimit = limit == 0 ? 500 : limit
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
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
