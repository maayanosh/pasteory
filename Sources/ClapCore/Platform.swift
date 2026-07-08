import Foundation

/// Copies an item to the OS clipboard and pastes it into the previously
/// focused app. macOS impl: NSPasteboard write + focus restore + synthetic ⌘V.
@MainActor
public protocol Paster: AnyObject {
    func copy(_ item: ClipItem, plainText: Bool)
    func paste(_ item: ClipItem, plainText: Bool)
}

/// Watches the OS clipboard and emits captured items. macOS impl: NSPasteboard
/// change-count polling on a timer.
@MainActor
public protocol ClipboardSource: AnyObject {
    var onCapture: ((ClipItem) -> Void)? { get set }
    func start()
    func stop()
}

/// Registers the global show/hide chord. macOS impl: Carbon RegisterEventHotKey.
@MainActor
public protocol GlobalHotKey: AnyObject {
    func register(_ handler: @escaping () -> Void)
}

/// Registers/unregisters the app as a login item. macOS impl: ServiceManagement.
@MainActor
public protocol LaunchAtLoginController {
    func setEnabled(_ enabled: Bool)
}
