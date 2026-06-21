import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchWindowManager: NSObject, NotchWindowManagerProtocol {
    // MARK: - Protocol Properties
    var isVisible: Bool { notchWindow?.isVisible ?? false }
    weak var delegate: NotchWindowManagerDelegate?
    
    // MARK: - Dependencies
    private let serviceContainer: ServiceContainer
    private weak var appCoordinator: AppCoordinator?
    
    // MARK: - Private Properties
    private var notchWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var notchViewModel: NotchViewModel?
    private var cancellables = Set<AnyCancellable>()
    /// Last `CGDirectDisplayID` we successfully placed the notch on. Used
    /// to keep the notch on the *same physical monitor* after a cable
    /// reconnect or resolution change — `NSScreen.screens` order can shuffle,
    /// so we can't rely on "first screen with safeAreaInsets". When the
    /// remembered display is still attached, we prefer it; otherwise we
    /// fall back to `preferredNotchScreen()`'s heuristic.
    private var lastUsedDisplayID: CGDirectDisplayID?
    
    // Window configuration constants — sourced from `NotchConfiguration`
    // so the SwiftUI `.frame(...)` in NotchView and the NSWindow frame stay
    // identical. They previously diverged (window 300 vs SwiftUI 400 when
    // expanded), which silently clipped the rightmost ~100pt of content.
    private struct Constants {
        static let defaultNotchWidth: CGFloat = NotchConfiguration.default.width
        static let defaultNotchHeight: CGFloat = NotchConfiguration.default.height
        static let expandedNotchWidth: CGFloat = NotchConfiguration.expanded.width
        static let expandedNotchHeight: CGFloat = NotchConfiguration.expanded.height
        static let cornerRadius: CGFloat = 16
        static let notchTopOffset: CGFloat = 0 // Align with actual MacBook notch
    }
    
    // MARK: - Initialization
    init(serviceContainer: ServiceContainer) {
        self.serviceContainer = serviceContainer
        super.init()
    }
    
    func setAppCoordinator(_ appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
    
    // MARK: - Protocol Implementation
    func initialize() async throws {
        AppLogger.general.debug("NotchWindowManager.initialize() begin — screens=\(NSScreen.screens.count, privacy: .public)")
        setupNotchWindow()
        AppLogger.general.debug("NotchWindowManager: notchWindow=\(self.notchWindow != nil ? "ready" : "nil", privacy: .public)")
        setupNotchContent()
        AppLogger.general.debug("NotchWindowManager: hostingController=\(self.hostingController != nil ? "ready" : "nil", privacy: .public)")
        observeScreenChanges()
        AppLogger.general.debug("NotchWindowManager.initialize() done")
    }

    private func observeScreenChanges() {
        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updatePosition()
        }
        .store(in: &cancellables)

        // React to the user toggling "Show on monitors without a hardware
        // notch" in real time — without this, the user would need to
        // unplug/replug a display before the change took effect.
        UserDefaults.standard
            .publisher(for: \.notchDisplayPolicy)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                AppLogger.general.notice(
                    "Notch: notchDisplayPolicy → \(value ?? "nil", privacy: .public); re-evaluating placement."
                )
                // Clear the sticky pin so the new policy gets a fresh pick.
                self?.lastUsedDisplayID = nil
                self?.updatePosition()
            }
            .store(in: &cancellables)
    }
    
    func show() {
        guard let window = notchWindow else { return }
        updatePosition()
        window.makeKeyAndOrderFront(nil)
        AppLogger.general.debug("NotchWindowManager.show(): isVisible=\(window.isVisible, privacy: .public) level=\(window.level.rawValue, privacy: .public)")
        delegate?.windowDidAppear()
    }
    
    func hide() {
        notchWindow?.orderOut(nil)
        delegate?.windowDidDisappear()
    }
    
    func updatePosition() {
        guard let notchWindow = notchWindow else { return }

        // If every display has been disconnected (rare but possible during
        // clamshell + monitor swap), hide rather than leaving the window at
        // a stale frame. A subsequent screen-change notification will fire
        // when a display is reattached, at which point we re-position.
        guard let screen = preferredNotchScreen() else {
            AppLogger.general.notice("Notch: no eligible screens; hiding window.")
            notchWindow.orderOut(nil)
            return
        }

        if !notchWindow.isVisible {
            notchWindow.orderFront(nil)
        }
        // Pick frame based on current state — previously this always used
        // the collapsed frame, so a show() while expanded snapped the window
        // back to collapsed dimensions before the Combine subscriber's
        // `expandNotch()` could resize it again. The user perceived this as
        // "the notch jumps to a different position when I hide and show."
        let isExpanded = notchViewModel?.isExpanded ?? false
        let newFrame = isExpanded
            ? calculateExpandedFrame(for: screen)
            : calculateNotchFrame(for: screen)
        notchWindow.setFrame(newFrame, display: true, animate: false)
        delegate?.windowDidChangePosition()

        // Trace what we picked so the user can correlate "I plugged a
        // monitor in" with the resulting window placement when filing a
        // multi-display bug. `.notice` shows up in Console.app by default.
        let safeAreaTop: CGFloat
        if #available(macOS 12.0, *) {
            safeAreaTop = screen.safeAreaInsets.top
        } else {
            safeAreaTop = 0
        }
        AppLogger.general.notice(
            "Notch placed on display \(screen.displayID, privacy: .public) safeAreaTop=\(safeAreaTop, privacy: .public) frame=\(NSStringFromRect(newFrame), privacy: .public)"
        )
    }
    
    func cleanup() {
        hide() // Use synchronous hide instead of async hideNotchWindow()
        settingsWindow?.orderOut(nil) // Use direct window hide instead of async hideSettingsWindow()
        cancellables.removeAll()
        notchViewModel = nil
        hostingController = nil
        notchWindow = nil
        settingsWindow = nil
        delegate = nil
    }
    
    func showNotchWindow() async throws {
        show()
    }
    
    func hideNotchWindow() async throws {
        hide()
    }
    
    func showSettingsWindow() async throws {
        if settingsWindow == nil {
            setupSettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    func hideSettingsWindow() async throws {
        settingsWindow?.orderOut(nil)
    }
    
    func updateNotchPosition() async throws {
        updatePosition()
    }

    /// Hover intent handler called by `NotchWindowContentView`'s
    /// `mouseEntered`/`mouseExited`. We *don't* expand the notch immediately
    /// on `entered=true` — instead we wait ~1s so the user has to actually
    /// rest the cursor over the notch. Passing through (e.g. on the way to
    /// a menubar item) shouldn't trigger expansion.
    ///
    /// We also stopped routing hover through SwiftUI's `.onHover` because
    /// the notch's frame interpolates during expand/collapse, which causes
    /// SwiftUI to toggle `isHovered` rapidly mid-animation and produces a
    /// visible expand→collapse→expand loop. `NSTrackingArea` on the window
    /// is anchored to a stable AppKit view and doesn't suffer from this.
    func handleHoverIntent(entered: Bool) {
        // Tear down any pending expand from a previous enter — whether we
        // got a new enter (debounce reset) or an exit (cancel outright).
        hoverIntentWorkItem?.cancel()
        hoverIntentWorkItem = nil

        guard let viewModel = notchViewModel else { return }

        // While the notch is auto-pulsing (e.g. for a track or play/pause
        // change), AppKit fires a spurious `mouseEntered` because the
        // window grew underneath the cursor. We don't want that to
        // transition the pulse into a hover state — that would leave the
        // notch stuck open until the user manually moved the mouse out.
        // The pulse owns its own collapse timer; just ignore the enter.
        if entered, viewModel.isPulsing { return }

        if entered {
            let work = DispatchWorkItem { [weak self, weak viewModel] in
                guard let self = self, let vm = viewModel else { return }
                // Bail out if the cursor already left during the delay —
                // `hoverIntentWorkItem == nil` after an exit.
                guard self.hoverIntentWorkItem != nil else { return }
                vm.handleHover(true)
                self.hoverIntentWorkItem = nil
            }
            hoverIntentWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverIntentDelay, execute: work)
        } else {
            // Spurious mouseExited rejection.
            //
            // During the expand animation, `NSWindow.setFrame` grows the
            // content view from 200×32 to 480×180 over ~0.3s. AppKit's
            // tracking-area machinery briefly evaluates the cursor against
            // the *old* (smaller) rect before catching up, so mouseExited
            // fires even though the cursor is still inside what is now a
            // much larger window. That fake exit was collapsing the notch
            // milliseconds after it had finished expanding.
            //
            // Verify against the live window frame in screen coordinates
            // before honoring the exit. If the cursor is still inside,
            // re-arm a tracking re-evaluation so a real exit isn't missed.
            if let window = notchWindow {
                let cursor = NSEvent.mouseLocation
                if NSPointInRect(cursor, window.frame) {
                    // Cursor is still inside. The spurious exit fired during
                    // the expand animation — schedule a re-check but cancel
                    // any previous one so rapid exits don't accumulate timers.
                    exitVerifyWorkItem?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self, let win = self.notchWindow else { return }
                        if !NSPointInRect(NSEvent.mouseLocation, win.frame) {
                            self.notchViewModel?.handleHover(false)
                        }
                        self.exitVerifyWorkItem = nil
                    }
                    exitVerifyWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
                    return
                }
            }
            exitVerifyWorkItem?.cancel()
            exitVerifyWorkItem = nil
            viewModel.handleHover(false)
        }
    }

    /// Time the cursor must stay on the notch before it expands. Tuned to
    /// 1.0s — short enough to feel responsive when the user actually wants
    /// the notch, long enough that walking the cursor past it doesn't fire.
    private let hoverIntentDelay: TimeInterval = 1.0
    private var hoverIntentWorkItem: DispatchWorkItem?
    /// Cancellable item for the spurious-exit re-verification delay.
    /// Stored so rapid mouseExited events cancel any previous pending
    /// re-check instead of accumulating concurrent timers.
    private var exitVerifyWorkItem: DispatchWorkItem?

    // MARK: - Private Methods
    private func setupNotchWindow() {
        // Fall back to `NSScreen.main` if the configured policy can't pick
        // a screen — without this, a stale `.notchOnly` setting on a Mac
        // without hardware notch (or a transient screen state at launch)
        // would silently abort the entire notch UI. updatePosition() will
        // re-evaluate the policy on each screen change and orderOut later
        // if the policy truly says we shouldn't be visible.
        let screen: NSScreen
        if let picked = preferredNotchScreen() {
            screen = picked
        } else if let main = NSScreen.main {
            AppLogger.general.notice(
                "NotchWindowManager: preferredNotchScreen returned nil — falling back to NSScreen.main so the window still gets created."
            )
            screen = main
        } else {
            AppLogger.general.error(
                "NotchWindowManager: NO screens available at startup; cannot create notch window."
            )
            return
        }

        let initialFrame = calculateNotchFrame(for: screen)
        AppLogger.general.notice(
            "NotchWindowManager: creating window on display \(screen.displayID, privacy: .public) frame=\(NSStringFromRect(initialFrame), privacy: .public)"
        )
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        configureNotchWindow(window)
        self.notchWindow = window
    }
    
    private func configureNotchWindow(_ window: NSWindow) {
        // Essential window properties for notch overlay (BoringNotch pattern)
        window.level = NSWindow.Level.screenSaver // Above everything except screen savers
        window.collectionBehavior = [
            .canJoinAllSpaces,    // Appear on all spaces
            .stationary,          // Don't move with spaces
            .ignoresCycle,        // Don't appear in window cycling
            .fullScreenAuxiliary  // Appear in fullscreen
        ]
        
        // Visual configuration
        window.isMovable = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        
        // Enable mouse tracking for hover effects
        window.acceptsMouseMovedEvents = true
        
        // Custom NSView for mouse tracking. We hand it a weak reference to
        // self so `mouseEntered` can route hover into our delegate — the
        // earlier `window.windowController as? NotchWindowManager` cast
        // could never succeed because NotchWindowManager is an NSObject,
        // not an NSWindowController. The hover callback path was silently
        // dead until this wiring landed.
        let contentView = NotchWindowContentView()
        contentView.manager = self
        window.contentView = contentView
    }
    
    private func setupNotchContent() {
        guard let window = notchWindow,
              let appCoordinator = appCoordinator else { return }

        // Use AppCoordinator's single NotchViewModel instance to avoid duplicate state.
        // AppCoordinator mutates this VM in processSystemEvent; manager must observe the same one.
        let notchViewModel = appCoordinator.notchViewModel
        self.notchViewModel = notchViewModel

        bindViewModel(notchViewModel)

        // Create NotchView with proper viewModel and environment
        let notchView = NotchView(viewModel: notchViewModel)
            .environmentObject(appCoordinator)
        
        let hostingController = NSHostingController(rootView: AnyView(notchView))

        // Cut the SwiftUI→AutoLayout intrinsic-size feedback loop.
        //
        // Default `NSHostingController.sizingOptions` is `.intrinsicContentSize`,
        // which makes `NSHostingView` republish its intrinsic content size
        // every time the SwiftUI body returns a new size hint. NotchView's
        // body is animation-driven (`.frame(...)` interpolates with
        // `viewModel.isExpanded`, plus `actionPulse` runs a spring on every
        // `currentContent` change), so within a single AppKit display cycle
        // SwiftUI can invalidate constraints more times than there are views
        // in the window — which trips AppKit's hard exception:
        // `NSGenericException: more Update Constraints passes than views`.
        //
        // We pin the hosting view to the window content view explicitly
        // below, so we *don't need* intrinsic-size feedback at all — the
        // window's frame is driven by `expandNotch()` / `collapseNotch()`,
        // not by SwiftUI. Setting `sizingOptions = []` disables the feedback
        // without affecting visual layout.
        hostingController.sizingOptions = []

        // Configure hosting controller
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.layer?.cornerRadius = Constants.cornerRadius

        // Pin via autoresizing rather than AutoLayout. We previously used
        // NSLayoutConstraint pins to leading/trailing/top/bottom anchors,
        // but combined with NSHostingView's intrinsic-size churn this fed
        // back into NSWindow's display cycle and contributed to the
        // constraint-pass crash above. Autoresizing produces the same
        // "fill superview" behavior with no AutoLayout participation.
        guard let contentView = window.contentView else { return }
        hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        hostingController.view.autoresizingMask = [.width, .height]
        hostingController.view.frame = contentView.bounds
        contentView.addSubview(hostingController.view)

        self.hostingController = hostingController
    }
    
    private func bindViewModel(_ viewModel: NotchViewModel) {
        viewModel.$isExpanded
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                guard let self = self else { return }
                if expanded {
                    self.expandNotch(animated: true)
                } else {
                    self.collapseNotch(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    private func calculateNotchFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let width = Constants.defaultNotchWidth
        let height = Constants.defaultNotchHeight

        // Detect physical notch height via safeAreaInsets (macOS 12+).
        // Returns 0 on non-notch displays.
        let notchHeight: CGFloat
        if #available(macOS 12.0, *) {
            notchHeight = screen.safeAreaInsets.top
        } else {
            notchHeight = 0
        }

        // `screen.frame` is in the global coordinate system. Secondary
        // displays can have a non-zero origin (e.g. {-1920, 0} for a screen
        // to the left of primary, or {0, -1080} for one below). Adding
        // `screenFrame.origin` is what makes the window land on the *right*
        // display — without it, every multi-display setup placed the notch
        // on whichever display happened to contain (0,0).
        let menuBarHeight = NSStatusBar.system.thickness
        let topY: CGFloat
        if notchHeight > 0 {
            topY = screenFrame.origin.y + screenFrame.height - max(notchHeight, height)
        } else {
            topY = screenFrame.origin.y + screenFrame.height - height - menuBarHeight - Constants.notchTopOffset
        }

        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        return NSRect(x: x, y: topY, width: width, height: height)
    }

    /// Selects which screen to place the notch on, honoring three policies:
    /// `.notchOnly`, `.primaryOnly`, `.allDisplays`. See NotchDisplayPolicy
    /// for definitions.
    ///
    /// "Sticky" behavior: if we previously placed the notch on display X
    /// (tracked via `CGDirectDisplayID`), we keep using X as long as it's
    /// still attached AND still passes the current policy. On miss, we
    /// re-pick from scratch using the policy's heuristic.
    private func preferredNotchScreen() -> NSScreen? {
        let policy = currentDisplayPolicy()

        // Honor remembered display ID if it's still attached AND allowed.
        if let id = lastUsedDisplayID,
           let remembered = NSScreen.screens.first(where: { $0.displayID == id }),
           screenAllowed(remembered, policy: policy) {
            return remembered
        }
        // Cached display no longer allowed (user toggled policy, or display
        // detached). Clear so the heuristic below runs fresh.
        lastUsedDisplayID = nil

        let pick = pickScreen(for: policy)
        lastUsedDisplayID = pick?.displayID
        return pick
    }

    private func pickScreen(for policy: NotchDisplayPolicy) -> NSScreen? {
        switch policy {
        case .notchOnly:
            // Only hardware notch displays. Return nil if none attached —
            // updatePosition() will hide the window.
            if #available(macOS 12.0, *) {
                return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            }
            return nil

        case .primaryOnly:
            // The display that currently owns the menu bar. When clamshell
            // is closed this is the external monitor; when open it's the
            // MacBook (usually the notch display).
            return NSScreen.main

        case .allDisplays:
            // Prefer notch display when available (so the overlay aligns
            // with the physical notch), else any attached screen.
            if #available(macOS 12.0, *),
               let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return notchScreen
            }
            return NSScreen.main
        }
    }

    private func screenAllowed(_ screen: NSScreen, policy: NotchDisplayPolicy) -> Bool {
        switch policy {
        case .notchOnly:
            if #available(macOS 12.0, *) {
                return screen.safeAreaInsets.top > 0
            }
            return false
        case .primaryOnly:
            // Only the current main screen qualifies.
            return screen.displayID == NSScreen.main?.displayID
        case .allDisplays:
            return true
        }
    }

    private func currentDisplayPolicy() -> NotchDisplayPolicy {
        if let raw = UserDefaults.standard.string(forKey: SettingsKeys.notchDisplayPolicy),
           let policy = NotchDisplayPolicy(rawValue: raw) {
            return policy
        }
        return .allDisplays
    }
    
    private func setupSettingsWindow() {
        // Earlier this just allocated an empty NSWindow — no
        // contentViewController, no hosted SwiftUI view — so the user got
        // a blank "SmartEdge Settings" pane. Host the real SettingsView
        // here. AppCoordinator is injected so panels that need the
        // coordinator (notch toggles, permission flow, etc.) get it via
        // `.environmentObject` exactly the way the SmartEdgeApp's
        // SwiftUI `Settings { }` scene would have.
        let rootView = settingsRootView()
        let hosting = NSHostingController(rootView: rootView)
        // Match SettingsView's `frame(minWidth: 800, minHeight: 600)` so the
        // window opens at the size the layout was designed for instead of
        // the old 600x400 default that was clipping the sidebar.
        let initialFrame = NSRect(x: 0, y: 0, width: 900, height: 640)
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SmartEdge Settings"
        window.contentViewController = hosting
        window.setContentSize(initialFrame.size)
        window.center()
        window.isReleasedWhenClosed = false
        // Force an opaque window. Without this, NavigationSplitView's
        // vibrant sidebar samples whatever is *behind* the window (desktop,
        // other apps, the notch player bar) and bleeds it through — which
        // read as the settings screen "overlapping" other windows.
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor

        self.settingsWindow = window
    }

    /// Builds the SwiftUI root for the Settings window. Split out so the
    /// `@ViewBuilder` AnyView erasure happens in one place — without it the
    /// conditional `if let appCoordinator` would force the caller to deal
    /// with two unrelated View types.
    @ViewBuilder
    private func settingsRootView() -> some View {
        if let appCoordinator = appCoordinator {
            SettingsView().environmentObject(appCoordinator)
        } else {
            // Defensive fallback: AppCoordinator should always be wired by
            // the time the user can trigger Settings, but if early-launch
            // ordering ever changes we'd rather show the panel than crash.
            SettingsView()
        }
    }
    
    // MARK: - Animation Support (Future Enhancement)
    func expandNotch(animated: Bool = true) {
        guard let window = notchWindow,
              let screen = preferredNotchScreen() else { return }

        let expandedFrame = calculateExpandedFrame(for: screen)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(expandedFrame, display: true)
            }
        } else {
            window.setFrame(expandedFrame, display: true)
        }
    }

    private func calculateExpandedFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let width = Constants.expandedNotchWidth
        let height = Constants.expandedNotchHeight

        let notchHeight: CGFloat
        if #available(macOS 12.0, *) {
            notchHeight = screen.safeAreaInsets.top
        } else {
            notchHeight = 0
        }

        // Add screen origin so secondary displays land at the correct
        // global coordinate. See `calculateNotchFrame` for the full reasoning.
        let menuBarHeight = NSStatusBar.system.thickness
        let y: CGFloat
        if notchHeight > 0 {
            y = screenFrame.origin.y + screenFrame.height - height
        } else {
            y = screenFrame.origin.y + screenFrame.height - height - menuBarHeight - Constants.notchTopOffset
        }

        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func collapseNotch(animated: Bool = true) {
        guard let window = notchWindow,
              let screen = preferredNotchScreen() else { return }

        let collapsedFrame = calculateNotchFrame(for: screen)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().setFrame(collapsedFrame, display: true)
            }
        } else {
            window.setFrame(collapsedFrame, display: true)
        }
    }
}

// MARK: - Custom NSView for Mouse Tracking
private class NotchWindowContentView: NSView {
    /// Weak so the view doesn't keep the manager alive past `cleanup()`.
    weak var manager: NotchWindowManager?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // NSView created programmatically never receives `awakeFromNib`,
        // so we set up the tracking area here. `updateTrackingAreas` then
        // refreshes it whenever the bounds change.
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Only rebuild if we don't already have one. `updateTrackingAreas`
        // fires on every bounds change, and the notch window bounds change
        // on every animation frame during expand/collapse. Rebuilding on
        // each frame multiplies AppKit's input-event processing cost with
        // no benefit — `.inVisibleRect` already keeps the tracked region
        // current without a full teardown/rebuild.
        if trackingAreas.isEmpty {
            setupTrackingArea()
        }
    }

    private func setupTrackingArea() {
        trackingAreas.forEach { removeTrackingArea($0) }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Hand off to the manager, which applies a 1-second hover-intent
        // delay before actually expanding. We were previously routing this
        // through SwiftUI's `.onHover`, which fired false/true rapidly
        // while the notch frame was mid-animation and caused an
        // expand→collapse loop. AppKit's tracking area is anchored to a
        // stable view and doesn't have that problem.
        Task { @MainActor [weak manager] in
            manager?.handleHoverIntent(entered: true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        Task { @MainActor [weak manager] in
            manager?.handleHoverIntent(entered: false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
}

// MARK: - UserDefaults KVO bridge
//
// `UserDefaults.publisher(for:)` needs an @objc dynamic property to observe.
// The property name **must match the UserDefaults key name exactly** — KVO
// derives the key from the property name, so a mismatch silently swallows
// every change notification. Keep this in sync with
// `SettingsKeys.showOnNonNotchDisplays`.
private extension UserDefaults {
    /// KVO bridge for the display policy. Returns String? (optional) so
    /// KVO fires on the initial nil → first-set transition too.
    @objc dynamic var notchDisplayPolicy: String? {
        string(forKey: SettingsKeys.notchDisplayPolicy)
    }
}

// MARK: - NSScreen → CGDirectDisplayID
private extension NSScreen {
    /// Pulls the underlying Core Graphics display ID from the screen's
    /// device description. Returns 0 if unavailable (extremely rare —
    /// would mean the screen has no `NSScreenNumber` key, which doesn't
    /// happen on modern macOS).
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}