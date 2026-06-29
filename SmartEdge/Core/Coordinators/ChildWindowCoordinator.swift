import AppKit
import SwiftUI

/// Owns the lifecycle of the auxiliary windows AppCoordinator used to
/// manage inline (permission guide, pomodoro stats). Each window is
/// lazily created on first show, cached for reuse, and torn down via
/// `WindowCloseHandler` when the user clicks the close button.
///
/// Why "Child"? The main notch + settings windows live in
/// `NotchWindowManager`. This coordinator only handles the secondary
/// HUD-style windows that AppCoordinator was managing inline before
/// the K-tier refactor split them out.
@MainActor
final class ChildWindowCoordinator {
    private var permissionGuideWindow: NSWindow?
    private var permissionGuideHandler: WindowCloseHandler?
    private var pomodoroStatsWindow: NSWindow?
    private var pomodoroStatsHandler: WindowCloseHandler?
    private var shelfWindow: NSWindow?
    private var shelfHandler: WindowCloseHandler?

    /// Opens (or focuses, if already open) the permission guide window.
    /// `onContinue` fires when the user clicks "Continue" inside the view
    /// — typically used to kick off the actual permission request flow.
    func showPermissionGuide(onContinue: @escaping () -> Void) {
        if permissionGuideWindow == nil {
            let view = PermissionGuideView(
                permissionManager: ServiceContainer.shared.systemPermissionManager,
                onContinue: { [weak self] in
                    // Dismiss the window first so the system permission
                    // prompts that `onContinue` triggers aren't obscured.
                    self?.permissionGuideWindow?.orderOut(nil)
                    onContinue()
                }
            )
            permissionGuideWindow = makeWindow(
                title: "SmartEdge — Permissions",
                content: view
            ) { [weak self] in
                self?.permissionGuideWindow = nil
                self?.permissionGuideHandler = nil
            } storeHandlerIn: { handler in
                permissionGuideHandler = handler
            }
        }
        focus(permissionGuideWindow)
    }

    /// Opens the focus-session statistics window backed by the same
    /// PomodoroViewModel the notch uses, so live state stays consistent.
    func showPomodoroStatistics(viewModel: PomodoroViewModel) {
        if pomodoroStatsWindow == nil {
            let view = PomodoroStatisticsView(viewModel: viewModel)
            pomodoroStatsWindow = makeWindow(
                title: "SmartEdge — Focus Statistics",
                content: view
            ) { [weak self] in
                self?.pomodoroStatsWindow = nil
                self?.pomodoroStatsHandler = nil
            } storeHandlerIn: { handler in
                pomodoroStatsHandler = handler
            }
        }
        focus(pomodoroStatsWindow)
    }

    /// Opens (or focuses) the Quick Shelf as a centered standalone window.
    /// A normal window receives Finder drag-and-drop natively, sidestepping
    /// the notch overlay's window-level drop restriction.
    func showShelf(viewModel: ShelfViewModel) {
        if shelfWindow == nil {
            let view = ShelfView(viewModel: viewModel)
            let window = makeWindow(
                title: "Quick Shelf",
                content: view
            ) { [weak self] in
                self?.shelfWindow = nil
                self?.shelfHandler = nil
            } storeHandlerIn: { handler in
                shelfHandler = handler
            }
            window.setContentSize(NSSize(width: 380, height: 460))
            // Seamless header: hide the native title (the view draws its own
            // "Quick Shelf" header) and let content run under a transparent
            // title bar, keeping just the traffic-light controls.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.center()
            shelfWindow = window
        }
        focus(shelfWindow)
    }

    // MARK: - Private

    /// Builds a `.titled` + `.closable` window hosting the given SwiftUI
    /// view, installs a `WindowCloseHandler` so we drop our cached
    /// reference when the user closes it, and centers it on screen.
    ///
    /// `storeHandlerIn` lets the caller stash the handler in the matching
    /// strong reference — `NSWindow.delegate` is `weak`, so without that
    /// strong hold the handler would deallocate immediately and we'd
    /// never get the close callback.
    private func makeWindow<Content: View>(
        title: String,
        content: Content,
        onClose: @escaping () -> Void,
        storeHandlerIn: (WindowCloseHandler) -> Void
    ) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        let handler = WindowCloseHandler(onClose: onClose)
        window.delegate = handler
        storeHandlerIn(handler)
        return window
    }

    private func focus(_ window: NSWindow?) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// NSWindowDelegate that calls a closure on window close so callers can
/// drop their cached reference. Lifted out of AppCoordinator with the
/// K-tier refactor so multiple coordinators can use it.
final class WindowCloseHandler: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
