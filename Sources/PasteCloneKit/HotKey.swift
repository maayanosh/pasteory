import AppKit
import Carbon.HIToolbox
#if canImport(ClapCore)
import ClapCore
#endif

/// Global hotkey via legacy Carbon RegisterEventHotKey — works without any
/// privacy permissions, unlike NSEvent global monitors.
@MainActor
public final class HotKey: GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    public var handler: (() -> Void)?

    public func register(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    public init(keyCode: UInt32 = UInt32(kVK_ANSI_V),
                modifiers: UInt32 = UInt32(cmdKey | shiftKey)) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.handler?() }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler
        )
        let hotKeyID = EventHotKeyID(signature: OSType(0x50434C4E) /* 'PCLN' */, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
