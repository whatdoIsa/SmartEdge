import Foundation
import ApplicationServices
import AppKit
import Combine
import IOKit.hid

@MainActor
final class SystemPermissionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasInputMonitoringPermission = false
    @Published private(set) var hasScreenRecordingPermission = false
    
    // MARK: - Private Properties

    private var permissionCheckTimer: Timer?
    /// 1s instead of 2s — short enough that a user who's staring at the
    /// Settings panel right after toggling Accessibility in System Settings
    /// sees the green checkmark within a heartbeat. Background polling at
    /// 1Hz on a single boolean check is well under noise.
    private let checkInterval: TimeInterval = 1.0
    private var appActivationObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        updatePermissionStatus()
        startPeriodicPermissionCheck()
        observeAppActivation()
    }

    deinit {
        permissionCheckTimer?.invalidate()
        if let observer = appActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refresh permissions whenever the app gains focus.
    /// Without this, the user has to wait up to `checkInterval` seconds
    /// after granting a permission in System Settings before the row flips
    /// to green — which reads as "the app didn't notice." Re-checking on
    /// `didBecomeActive` makes the round-trip feel instantaneous because
    /// returning from System Settings *is* the natural "activate"
    /// moment.
    private func observeAppActivation() {
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePermissionStatus()
            }
        }
    }
    
    // MARK: - Permission Checking
    
    func hasAccessibilityPermission() async -> Bool {
        return AXIsProcessTrusted()
    }
    
    func hasInputMonitoringPermission() async -> Bool {
        // Earlier this created an event tap and discarded the result
        // without disabling/releasing the tap — every call leaked a CFMachPort
        // *and* registered a phantom callback that fired on every subsequent
        // keystroke until the process exited. With this method polled at
        // 1Hz, the leak compounded badly: an hour of runtime piled up
        // 3,600 stale callbacks routing through the event-tap chain.
        //
        // `IOHIDCheckAccess` (macOS 10.15+) is the documented permission
        // check — it returns immediately, allocates nothing, and matches the
        // exact OS-level kIOHIDRequestTypeListenEvent grant the user toggles
        // in System Settings → Privacy & Security → Input Monitoring.
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    
    func hasScreenRecordingPermission() async -> Bool {
        // Check by attempting to get screen capture permissions
        let displays = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())
        if displays != nil {
            return true
        }
        return false
    }
    
    // MARK: - Permission Requests
    
    func requestAccessibilityPermission() async {
        // Check current status
        let currentStatus = await hasAccessibilityPermission()
        
        if !currentStatus {
            // Request accessibility permission with prompt
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            let isEnabled = AXIsProcessTrustedWithOptions(options)
            
            if !isEnabled {
                // Guide user to System Preferences
                await openAccessibilityPreferences()
            }
        }
        
        // Update status
        hasAccessibilityPermission = await hasAccessibilityPermission()
    }
    
    func requestInputMonitoringPermission() async {
        let currentStatus = await hasInputMonitoringPermission()
        guard !currentStatus else {
            hasInputMonitoringPermission = true
            return
        }

        // `IOHIDRequestAccess` is the documented prompt API — it fires the
        // OS-level Input Monitoring request the same way Apple's own
        // sample code (Permission Manager TN3147) does. It returns
        // synchronously; the actual approval is async via the system
        // prompt UI. Replaces the leaky event tap we used to
        // call here — same leak rationale as `hasInputMonitoringPermission()`.
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if !granted {
            await openInputMonitoringPreferences()
        }

        hasInputMonitoringPermission = await hasInputMonitoringPermission()
    }
    
    func requestScreenRecordingPermission() async {
        let currentStatus = await hasScreenRecordingPermission()
        
        if !currentStatus {
            // Attempt screen capture to trigger permission prompt
            let imageRef = CGDisplayCreateImage(CGMainDisplayID())
            
            if imageRef == nil {
                await openScreenRecordingPreferences()
            }
        }
        
        // Update status
        hasScreenRecordingPermission = await hasScreenRecordingPermission()
    }
    
    // MARK: - System Preferences Navigation
    
    // MARK: - Public Preferences Navigation (without modal alert)
    /// Opens System Settings directly to the Accessibility privacy pane.
    func openAccessibilityPreferencesPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings directly to the Input Monitoring privacy pane.
    func openInputMonitoringPreferencesPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // The three `openXxxPreferences` paths used to call `showPermissionAlert`
    // which fires `NSAlert.runModal()`. Blocking modals from background code
    // were the root cause of "권한 다 켰는데 다이얼로그 또 뜬다" — on a dev
    // rebuild the `AXIsProcessTrusted` / event-tap checks briefly
    // report false even when the user has the toggle on, which dropped us
    // into these helpers and surfaced a modal the user had no warning was
    // coming.
    //
    // Policy now: this layer NEVER auto-shows a modal. It just opens the
    // relevant System Settings pane so the user can see the toggle, and we
    // log the attempt. The notch-routed PermissionGuide (triggered only
    // from intentional user action in `AppCoordinator.showPermissionGuide`)
    // is the single source of permission UX.

    private func openAccessibilityPreferences() async {
        AppLogger.general.notice("Permissions: opening Accessibility settings pane (silent)")
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func openInputMonitoringPreferences() async {
        AppLogger.general.notice("Permissions: opening Input Monitoring settings pane (silent)")
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    private func openScreenRecordingPreferences() async {
        AppLogger.general.notice("Permissions: opening Screen Recording settings pane (silent)")
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
    
    private func showPermissionAlert(title: String, message: String, preferencesURL: URL) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(preferencesURL)
        }
    }
    
    // MARK: - Periodic Status Updates
    
    private func startPeriodicPermissionCheck() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePermissionStatus()
            }
        }
    }
    
    private func updatePermissionStatus() {
        // The previous implementation wrapped the writes in an unstructured
        // `Task { }` which does NOT inherit @MainActor isolation — so the
        // @Published assignments could land on a background thread and the
        // SwiftUI subscriber (Settings panel) wouldn't redraw. We're already
        // @MainActor by virtue of the class annotation; just call directly.
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = checkInputMonitoringPermissionSync()
        let screenRecording = checkScreenRecordingPermissionSync()

        // `removeDuplicates` isn't applied on the @Published itself, so guard
        // here to avoid a no-op write triggering objectWillChange (which
        // would needlessly invalidate every Settings panel view subtree at
        // 1Hz).
        if hasAccessibilityPermission != accessibility {
            hasAccessibilityPermission = accessibility
        }
        if hasInputMonitoringPermission != inputMonitoring {
            hasInputMonitoringPermission = inputMonitoring
        }
        if hasScreenRecordingPermission != screenRecording {
            hasScreenRecordingPermission = screenRecording
        }
    }

    /// Sync mirror of `hasInputMonitoringPermission()`. Same IOHIDCheckAccess
    /// path — both methods now share the leak-free implementation. See the
    /// async method's doc-comment for the full rationale.
    private func checkInputMonitoringPermissionSync() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func checkScreenRecordingPermissionSync() -> Bool {
        return CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID()) != nil
    }
    
    // MARK: - Permission Status Summary
    
    func getPermissionSummary() async -> PermissionSummary {
        return PermissionSummary(
            accessibility: await hasAccessibilityPermission(),
            inputMonitoring: await hasInputMonitoringPermission(),
            screenRecording: await hasScreenRecordingPermission()
        )
    }
    
    func areAllRequiredPermissionsGranted() async -> Bool {
        let accessibility = await hasAccessibilityPermission()
        let inputMonitoring = await hasInputMonitoringPermission()
        
        // Screen recording is optional for basic functionality
        return accessibility && inputMonitoring
    }
    
    func requestAllRequiredPermissions() async {
        await requestAccessibilityPermission()
        await requestInputMonitoringPermission()
    }
}

// MARK: - Supporting Types

struct PermissionSummary {
    let accessibility: Bool
    let inputMonitoring: Bool
    let screenRecording: Bool
    
    var allGranted: Bool {
        return accessibility && inputMonitoring && screenRecording
    }
    
    var requiredGranted: Bool {
        return accessibility && inputMonitoring
    }
    
    var missingPermissions: [String] {
        var missing: [String] = []
        
        if !accessibility {
            missing.append("Accessibility")
        }
        
        if !inputMonitoring {
            missing.append("Input Monitoring")
        }
        
        if !screenRecording {
            missing.append("Screen Recording")
        }
        
        return missing
    }
}