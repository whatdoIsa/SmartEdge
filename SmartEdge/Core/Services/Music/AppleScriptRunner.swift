import Foundation

/// In-process AppleScript execution on a dedicated serial background queue.
///
/// Why in-process `NSAppleScript` (not `/usr/bin/osascript`): the App Store
/// build runs under App Sandbox, which blocks spawning external executables
/// — the same wall that killed the old perl-based adapter approach.
/// `NSAppleScript` runs the script inside our own process via Apple Events,
/// which the sandbox permits *given* the `scripting-targets` (or
/// temporary-exception apple-events) entitlement plus the user's one-time
/// Automation grant.
///
/// Why a background queue: Apple Event dispatch is synchronous IPC — if the
/// target app (Music / Spotify) is mid-launch or busy, the call blocks until
/// it answers. Running on the main thread would freeze the notch UI (exactly
/// the jank the original AppleScript source suffered). We confine every
/// execution to one serial queue and hop results back to the caller's actor.
///
/// A fresh `NSAppleScript` is compiled per call. Compilation of these tiny
/// property-read scripts is sub-millisecond, and per-call instances sidestep
/// `NSAppleScript`'s documented "don't share an instance across threads"
/// constraint.
final class AppleScriptRunner: @unchecked Sendable {

    /// Serial queue so two polls can't race the same `NSAppleScript` machinery.
    private let queue = DispatchQueue(label: "com.smartedge.applescript", qos: .utility)

    /// Run `source` and return its result coerced to a String, or nil on
    /// error / non-string result. Never throws — AppleScript failures
    /// (app not scriptable, permission denied, target not running) are
    /// expected control flow here, surfaced as nil so callers degrade
    /// gracefully instead of crashing.
    func runString(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: nil)
                    return
                }
                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    // -1743 = not authorized (Automation permission not granted).
                    // -600  = target app not running. Both are normal; log at
                    // debug so we don't spam the user's console.
                    let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                    AppLogger.media.debug("AppleScript error \(code, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: descriptor.stringValue)
            }
        }
    }

    /// Result of a script run that needs to distinguish a permission denial
    /// from "no value" — the queries use this to drive the authorization
    /// state machine. `errorCode` is the AppleScript/Apple-Event error number
    /// (nil on success); -1743 means Automation isn't authorized.
    struct ScriptResult {
        let value: String?
        let errorCode: Int?
    }

    /// Like `runString`, but surfaces the error code so the caller can tell a
    /// permission denial (-1743) apart from a transient failure. Sending this
    /// real Apple Event is also what triggers the macOS Automation prompt on
    /// the first send while the grant is undetermined (the app has the
    /// `automation.apple-events` entitlement + usage string, so the send is
    /// prompted rather than silently denied).
    func runWithStatus(_ source: String) async -> ScriptResult {
        await withCheckedContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: ScriptResult(value: nil, errorCode: nil))
                    return
                }
                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                    AppLogger.media.debug("AppleScript error \(code, privacy: .public)")
                    continuation.resume(returning: ScriptResult(value: nil, errorCode: code))
                    return
                }
                continuation.resume(returning: ScriptResult(value: descriptor.stringValue, errorCode: nil))
            }
        }
    }

    /// Run `source` and return the raw bytes of its result descriptor.
    /// Used for Apple Music artwork (`data of artwork 1 of current track`),
    /// which comes back as a binary descriptor, not a string.
    func runData(_ source: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: nil)
                    return
                }
                let descriptor = script.executeAndReturnError(&errorInfo)
                if errorInfo != nil {
                    continuation.resume(returning: nil)
                    return
                }
                // Non-empty data only — an empty descriptor means "no artwork".
                let data = descriptor.data
                continuation.resume(returning: data.isEmpty ? nil : data)
            }
        }
    }

    /// Fire-and-forget command (play/pause/next/…). We don't need the result,
    /// only that it dispatched. Still serial-queued so it can't interleave
    /// with a poll mid-flight.
    func runCommand(_ source: String) {
        queue.async {
            var errorInfo: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        }
    }

}
