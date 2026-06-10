import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey to toggle the HUD. Re-registerable at runtime.
final class HotKeyManager {
    static var shared: HotKeyManager?

    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
        HotKeyManager.shared = self
        installHandler()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                HotKeyManager.shared?.callback()
                return noErr
            },
            1, &eventType, nil, nil
        )
    }

    /// (Re)bind the global hotkey. keyCode is a Carbon virtual keycode,
    /// carbonModifiers a Carbon modifier mask (cmdKey/shiftKey/optionKey/controlKey).
    func register(keyCode: UInt32, carbonModifiers: UInt32) {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C484B31) /* 'LHK1' */, id: 1)
        RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    }
}
