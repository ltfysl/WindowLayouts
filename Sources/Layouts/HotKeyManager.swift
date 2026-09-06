import AppKit
import Carbon.HIToolbox

/// Global ⌥⌘⌃ + 1…9 hotkeys. Digit N restores the Nth layout in menu order.
final class HotKeyManager {
    var onDigit: ((Int) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    // Virtual key codes for the ANSI digits 1…9.
    private static let digitKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let modifiers = UInt32(cmdKey | optionKey | controlKey)

    private static weak var current: HotKeyManager?

    func install() {
        HotKeyManager.current = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }
            let digit = Int(hotKeyID.id)
            DispatchQueue.main.async {
                HotKeyManager.current?.onDigit?(digit)
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)

        for (index, keyCode) in Self.digitKeyCodes.enumerated() {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4C59344B) /* 'LY4K' */, id: UInt32(index + 1))
            RegisterEventHotKey(keyCode, Self.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
            hotKeyRefs.append(hotKeyRef)
        }
    }
}
