import Foundation
import Carbon
import Combine
import AppKit

enum VolumeKeyDirection {
    case up
    case down
    case mute
}

enum BrightnessKeyDirection {
    case up
    case down
}

/// Keyboard backlight (illumination) key press. `toggle` is a single press
/// of the OFF↔previous-level toggle, available on recent Mac keyboards.
enum KeyboardBacklightKeyDirection {
    case up
    case down
    case toggle
}

protocol HUDInterceptionProtocol {
    var delegate: HUDInterceptionDelegate? { get set }

    func startInterception() async throws
    func stopInterception() async
    func isInterceptionActive() async -> Bool
}

/// @MainActor because every concrete delegate forwarding inside
/// `HUDInterceptionService` is already wrapped in `Task { @MainActor ... }`
/// — codifying the isolation at the protocol level lets adopters be
/// `@MainActor` classes (SystemHUDService) without resorting to per-method
/// nonisolated escape hatches.
@MainActor
protocol HUDInterceptionDelegate: AnyObject {
    func hudInterceptionDidStart()
    func hudInterceptionDidStop()
    func hudInterceptionDidFail(with error: Error)
    func didInterceptVolumeKey(direction: VolumeKeyDirection)
    func didInterceptBrightnessKey(direction: BrightnessKeyDirection)
    func didInterceptKeyboardBacklightKey(direction: KeyboardBacklightKeyDirection)
}

final class HUDInterceptionService: HUDInterceptionProtocol {

    // MARK: - Properties

    weak var delegate: HUDInterceptionDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isIntercepting = false

    private static let systemDefinedEventTypeRaw: UInt32 = 14
    private static let auxiliarySubtype: Int16 = 8

    // Hardware keyboard keyCodes for the F-row keys. macOS reports these
    // when the user holds `fn` and presses Fn-row keys (or when "Use F1,
    // F2, etc. keys as standard function keys" is enabled in System
    // Settings → Keyboard). Without `fn`, the same physical keys arrive
    // through the NX_KEYTYPE aux-key path handled by `dispatchAuxKey`.
    //
    // Reference: kVK_* constants in <Carbon/HIToolbox/Events.h>.
    // The previous values (0x48, 0x49, 0x4A, 0x90, 0x91) were
    // NX_KEYTYPE_* constants accidentally pasted into the keyCode slot —
    // that's why fn+F-row was a no-op (no match) and why aux-key dispatch
    // (which IS NX_KEYTYPE-based) ended up firing the wrong action.
    private let f1KeyCode: Int64 = 0x7A  // 122 — user requests as Brightness DOWN
    private let f2KeyCode: Int64 = 0x78  // 120 — user requests as Brightness UP
    private let f10KeyCode: Int64 = 0x6D // 109 — user requests as Mute
    private let f11KeyCode: Int64 = 0x67 // 103 — user requests as Volume DOWN
    private let f12KeyCode: Int64 = 0x6F // 111 — user requests as Volume UP
    // Keep keyboard-backlight illumination on F5/F6 — the standard Mac
    // layout. Same fn-vs-no-fn duality as above.
    private let f5KeyCode: Int64 = 0x60  // 96  — Illumination DOWN
    private let f6KeyCode: Int64 = 0x61  // 97  — Illumination UP

    // MARK: - HUDInterceptionProtocol Implementation

    func startInterception() async throws {
        guard !isIntercepting else { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
                      | (1 << Int(HUDInterceptionService.systemDefinedEventTypeRaw))

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<HUDInterceptionService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            // `passUnretained` is safe here ONLY because
            // `HUDInterceptionService` is process-lifetime: it's a
            // `lazy var` on `ServiceContainer.shared` (singleton), so
            // there's no realistic path for `self` to be deallocated
            // while a pending CGEvent dispatch is still in flight. If
            // the service ever gets re-instantiated mid-run (e.g. for
            // unit tests that tear it down), switch this to
            // `passRetained` and `release()` in `stopInterception()`.
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw SmartEdgeError.systemAccess(.permissionDenied("Failed to create event tap - accessibility permission required"))
        }

        self.eventTap = eventTap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            self.eventTap = nil
            throw SmartEdgeError.systemAccess(.operationFailed("Failed to create run loop source"))
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

        CGEvent.tapEnable(tap: eventTap, enable: true)

        isIntercepting = true

        await MainActor.run {
            delegate?.hudInterceptionDidStart()
        }
    }

    func stopInterception() async {
        guard isIntercepting else { return }

        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        isIntercepting = false

        await MainActor.run {
            delegate?.hudInterceptionDidStop()
        }
    }

    func isInterceptionActive() async -> Bool {
        return isIntercepting
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // CGEvent disables our tap if the callback exceeds the system
        // timeout (~1s) — happens routinely when the user pauses in a
        // debugger or the main thread stalls. The tap stays installed but
        // dead, and every subsequent key falls through to the system HUD
        // with no logging. Re-arm the tap inline so we self-recover.
        // `tapDisabledByUserInput` fires if the user explicitly toggles
        // the input source — same recovery path.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDownEvent(event: event)
        default:
            if type.rawValue == HUDInterceptionService.systemDefinedEventTypeRaw {
                return handleSystemDefinedEvent(event: event)
            }
            return Unmanaged.passRetained(event)
        }
    }

    private func handleKeyDownEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard flags.contains(.maskSecondaryFn) else {
            return Unmanaged.passRetained(event)
        }

        let intercepted = dispatchFunctionKey(keyCode)
        return intercepted ? nil : Unmanaged.passRetained(event)
    }

    @discardableResult
    private func dispatchFunctionKey(_ keyCode: Int64) -> Bool {
        // Map per the user's preferred bindings:
        //   F1  → brightness down   F2  → brightness up
        //   F10 → mute
        //   F11 → volume down       F12 → volume up
        //   F5  → keyboard backlight down   F6 → keyboard backlight up
        let volume: VolumeKeyDirection?
        let brightness: BrightnessKeyDirection?
        let keyboard: KeyboardBacklightKeyDirection?
        switch keyCode {
        case f1KeyCode:
            volume = nil;  brightness = .down; keyboard = nil
        case f2KeyCode:
            volume = nil;  brightness = .up;   keyboard = nil
        case f10KeyCode:
            volume = .mute; brightness = nil;  keyboard = nil
        case f11KeyCode:
            volume = .down; brightness = nil;  keyboard = nil
        case f12KeyCode:
            volume = .up;   brightness = nil;  keyboard = nil
        case f5KeyCode:
            volume = nil;   brightness = nil;  keyboard = .down
        case f6KeyCode:
            volume = nil;   brightness = nil;  keyboard = .up
        default:
            return false
        }

        // Per-category gate. The master `interceptSystemHUD` toggle is
        // already enforced upstream (ServiceContainer.reconcile won't even
        // call startIntercepting() when it's off), so by the time we reach
        // here the master switch is on. These per-category toggles let the
        // user keep, say, volume on our notch HUD but leave brightness to
        // the system. Returning false here makes the caller pass the
        // event through so the OS handles it normally.
        if volume != nil, !Self.userWantsVolumeInterception() { return false }
        if brightness != nil, !Self.userWantsBrightnessInterception() { return false }
        if keyboard != nil, !Self.userWantsKeyboardInterception() { return false }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let volume = volume {
                self.delegate?.didInterceptVolumeKey(direction: volume)
            }
            if let brightness = brightness {
                self.delegate?.didInterceptBrightnessKey(direction: brightness)
            }
            if let keyboard = keyboard {
                self.delegate?.didInterceptKeyboardBacklightKey(direction: keyboard)
            }
        }
        return true
    }

    /// UserDefaults read; reads default to `true` to match the @AppStorage
    /// declaration so a user with no prior pref still gets the feature on.
    /// `object(forKey:)` (not `bool(forKey:)`) is what lets us distinguish
    /// "absent" from "explicitly false."
    private static func userWantsVolumeInterception() -> Bool {
        (UserDefaults.standard.object(forKey: SettingsKeys.interceptVolume) as? Bool) ?? true
    }
    private static func userWantsBrightnessInterception() -> Bool {
        (UserDefaults.standard.object(forKey: SettingsKeys.interceptBrightness) as? Bool) ?? true
    }
    private static func userWantsKeyboardInterception() -> Bool {
        // Default OFF to match SettingsViewModel's @AppStorage init value —
        // keyboard backlight intercept is opt-in because the HUD design
        // isn't finalized yet.
        (UserDefaults.standard.object(forKey: SettingsKeys.interceptKeyboard) as? Bool) ?? false
    }

    private func handleSystemDefinedEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == HUDInterceptionService.auxiliarySubtype else {
            return Unmanaged.passRetained(event)
        }

        let data1 = nsEvent.data1
        let auxKeyCode = Int64((data1 & 0xFFFF0000) >> 16)
        let keyFlags = data1 & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        guard isKeyDown else {
            return Unmanaged.passRetained(event)
        }

        let intercepted = dispatchAuxKey(auxKeyCode)
        return intercepted ? nil : Unmanaged.passRetained(event)
    }

    @discardableResult
    private func dispatchAuxKey(_ auxKeyCode: Int64) -> Bool {
        let volume: VolumeKeyDirection?
        let brightness: BrightnessKeyDirection?
        let keyboard: KeyboardBacklightKeyDirection?

        // NX_KEYTYPE_* constants from <IOKit/hidsystem/ev_keymap.h> — the
        // canonical IOKit aux-key codes. The previous table here had
        // SOUND_UP/DOWN flipped, BRIGHTNESS_UP/DOWN flipped, and listed 20
        // as ILLUMINATION_UP (it's actually NX_KEYTYPE_REWIND), which made
        // every aux key dispatch the wrong action. User-visible symptom:
        // hangul/eng key dimmed the screen, the dimmer key brightened it,
        // the brightener key turned volume down, etc.
        //
        //   NX_KEYTYPE_SOUND_UP         = 0
        //   NX_KEYTYPE_SOUND_DOWN       = 1
        //   NX_KEYTYPE_BRIGHTNESS_UP    = 2
        //   NX_KEYTYPE_BRIGHTNESS_DOWN  = 3
        //   NX_KEYTYPE_MUTE             = 7
        //   NX_KEYTYPE_PLAY             = 16  (left as default→ passthrough)
        //   NX_KEYTYPE_NEXT             = 17  (passthrough)
        //   NX_KEYTYPE_PREVIOUS         = 18  (passthrough)
        //   NX_KEYTYPE_REWIND           = 20  (passthrough)
        //   NX_KEYTYPE_ILLUMINATION_UP   = 21
        //   NX_KEYTYPE_ILLUMINATION_DOWN = 22
        //   NX_KEYTYPE_ILLUMINATION_TOGGLE = 23
        //   144 / 145 — legacy NX_KEYTYPE_BRIGHTNESS_UP / DOWN values
        //                 sent by some pre-2015 Mac keyboards. Kept as
        //                 fallback so we don't regress on those models.
        switch auxKeyCode {
        case 0:
            volume = .up;   brightness = nil;  keyboard = nil
        case 1:
            volume = .down; brightness = nil;  keyboard = nil
        case 2:
            volume = nil;   brightness = .up;  keyboard = nil
        case 3:
            volume = nil;   brightness = .down; keyboard = nil
        case 7:
            volume = .mute; brightness = nil;  keyboard = nil
        case 21:
            volume = nil;   brightness = nil;  keyboard = .up
        case 22:
            volume = nil;   brightness = nil;  keyboard = .down
        case 23:
            volume = nil;   brightness = nil;  keyboard = .toggle
        case 144:
            volume = nil;   brightness = .up;  keyboard = nil
        case 145:
            volume = nil;   brightness = .down; keyboard = nil
        default:
            // Includes media keys (play / next / prev / rewind /
            // fast-forward) and the Korean han/eng + Japanese kana keys.
            // We deliberately do NOT intercept any of these — they belong
            // to the system or input-method handler. Pre-fix, the table
            // misclassified them as volume/brightness actions.
            return false
        }

        // Per-category gate. See `dispatchFunctionKey` for full rationale.
        if volume != nil, !Self.userWantsVolumeInterception() { return false }
        if brightness != nil, !Self.userWantsBrightnessInterception() { return false }
        if keyboard != nil, !Self.userWantsKeyboardInterception() { return false }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let volume = volume {
                self.delegate?.didInterceptVolumeKey(direction: volume)
            }
            if let brightness = brightness {
                self.delegate?.didInterceptBrightnessKey(direction: brightness)
            }
            if let keyboard = keyboard {
                self.delegate?.didInterceptKeyboardBacklightKey(direction: keyboard)
            }
        }
        return true
    }

    // MARK: - Cleanup

    deinit {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        isIntercepting = false
    }
}

// `handleInterceptionError(_:)` extension was removed — it was defined
// but never wired anywhere, and the actual failure mode it tried to
// recover from (CGEvent tap disabled by timeout / user input) is now
// handled inline in `handleEvent` by re-arming the tap, which is the
// canonical recovery path Apple recommends. Surfacing a fail-event to
// the delegate at the same moment would have triggered the SystemHUDService
// to flip `isIntercepting = false` and confuse the Settings panel —
// the tap was disabled for ~milliseconds, not actually broken.
