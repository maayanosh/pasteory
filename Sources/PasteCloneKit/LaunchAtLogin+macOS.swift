import Foundation
import ServiceManagement
#if canImport(ClapCore)
import ClapCore
#endif

/// macOS login-item control via ServiceManagement. Only works from inside a
/// real .app bundle; failures during dev are logged and ignored.
public struct MacLaunchAtLogin: LaunchAtLoginController {
    public init() {}
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("PasteClone: launch-at-login change failed: \(error)")
        }
    }
}
