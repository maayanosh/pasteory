import Foundation
import Observation

@Observable
@MainActor
public final class Settings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginController: LaunchAtLoginController?

    public var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "isPaused") } }
    public var excludedBundleIDs: [String] { didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }
    public var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            loginController?.setEnabled(launchAtLogin)
        }
    }
    /// Panel background opacity, 0.3...1.0.
    public var panelOpacity: Double { didSet { defaults.set(panelOpacity, forKey: "panelOpacity") } }

    public init(defaults: UserDefaults = .standard, loginController: LaunchAtLoginController? = nil) {
        self.defaults = defaults
        self.loginController = loginController
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        let limit = defaults.integer(forKey: "historyLimit")
        self.historyLimit = limit == 0 ? 500 : limit
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        let opacity = defaults.double(forKey: "panelOpacity")
        self.panelOpacity = opacity == 0 ? 0.85 : min(max(opacity, 0.3), 1.0)
    }
}
