import AppKit
#if canImport(PasteCloneKit)
import PasteCloneKit // present when built as separate SwiftPM targets
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
