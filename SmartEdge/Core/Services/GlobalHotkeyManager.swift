import AppKit
import Carbon.HIToolbox

/// Thin wrapper around Carbon's `RegisterEventHotKey` so we can detect a key
/// combo even when SmartEdge isn't the frontmost app. Carbon is deprecated but
/// still the only public API on macOS for *consuming* system-wide hot keys
/// without Accessibility permission. `NSEvent.addGlobalMonitorForEvents` is
/// observe-only and cannot suppress the event for other apps.
@MainActor
final class GlobalHotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var registeredID: UInt32 = 0
    private static var nextID: UInt32 = 1

    /// Called on the main thread when the registered combo fires.
    var onTrigger: (() -> Void)?

    /// Registers a Carbon hot key for the given virtual key + modifier mask.
    /// `modifiers` is a Carbon mask (e.g. `cmdKey | shiftKey`), not NSEvent flags.
    /// Calling twice replaces the previous registration.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        let id = GlobalHotkeyManager.nextID
        GlobalHotkeyManager.nextID &+= 1
        registeredID = id

        let hotKeyID = EventHotKeyID(signature: OSType(0x534D_4544 /* "SMED" */), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref = ref else {
            return false
        }
        hotKeyRef = ref
        installHandlerIfNeeded()
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Carbon event handler

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
            guard let eventRef = eventRef, let userData = userData else {
                return OSStatus(eventNotHandledErr)
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            DispatchQueue.main.async {
                guard hotKeyID.id == manager.registeredID else { return }
                manager.onTrigger?()
            }

            return noErr
        }

        var handlerRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
        eventHandlerRef = handlerRef
    }
}

// MARK: - Carbon key codes (convenience)

extension GlobalHotkeyManager {
    /// Virtual key code for the "V" key.
    static let keyCodeV: UInt32 = UInt32(kVK_ANSI_V)
    /// Virtual key code for the "N" key.
    static let keyCodeN: UInt32 = UInt32(kVK_ANSI_N)
    /// Carbon modifier mask: command + shift.
    static let modifiersCmdShift: UInt32 = UInt32(cmdKey | shiftKey)
    /// Carbon modifier mask: control + option.
    static let modifiersCtrlOption: UInt32 = UInt32(controlKey | optionKey)
}
