import AppKit
import SwiftUI
import Combine

protocol NotchWindowServiceDelegate: AnyObject {
    func notchWindowDidMove(_ service: NotchWindowService)
    func notchWindow(_ service: NotchWindowService, didChangeHoverState isHovering: Bool)
}

@MainActor
final class NotchWindowService: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    @Published var isVisible: Bool = false
    @Published var notchFrame: NSRect = .zero
    @Published var isHovering: Bool = false
    
    // MARK: - Properties
    
    weak var delegate: NotchWindowServiceDelegate?
    nonisolated(unsafe) private var notchWindow: NSWindow?
    nonisolated(unsafe) private var trackingArea: NSTrackingArea?
    private var screenChangeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupNotchWindow()
        setupScreenChangeObserver()
    }
    
    // MARK: - Public Methods
    
    func showWindow() {
        notchWindow?.orderFrontRegardless()
        notchWindow?.makeKeyAndOrderFront(nil)
        isVisible = true
    }
    
    func hideWindow() {
        notchWindow?.orderOut(nil)
        isVisible = false
    }
    
    func updateNotchPosition() {
        guard let screen = NSScreen.main else { return }
        
        // Calculate notch position based on screen with built-in camera
        let notchWidth: CGFloat = 200
        let notchHeight: CGFloat = 32
        
        let screenFrame = screen.frame
        let notchX = (screenFrame.width - notchWidth) / 2
        let notchY = screenFrame.height - notchHeight
        
        let newFrame = NSRect(
            x: notchX,
            y: notchY,
            width: notchWidth,
            height: notchHeight
        )
        
        notchFrame = newFrame
        notchWindow?.setFrame(newFrame, display: true, animate: false)
        
        updateTrackingArea()
        delegate?.notchWindowDidMove(self)
    }
    
    func setHoverState(_ isHovering: Bool) {
        self.isHovering = isHovering
        delegate?.notchWindow(self, didChangeHoverState: isHovering)
    }
    
    // MARK: - Private Methods
    
    private func setupNotchWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Ensure window appears on all spaces and stays above other windows
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        
        notchWindow = window
        
        // Setup mouse tracking
        setupMouseTracking(for: window)
        
        updateNotchPosition()
    }
    
    private func setupMouseTracking(for window: NSWindow) {
        guard let contentView = window.contentView else { return }
        
        let trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .assumeInside],
            owner: self,
            userInfo: nil
        )
        
        contentView.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }
    
    private func updateTrackingArea() {
        guard let contentView = notchWindow?.contentView else { return }
        
        // Remove old tracking area
        if let oldArea = trackingArea {
            contentView.removeTrackingArea(oldArea)
        }
        
        // Create new tracking area with updated bounds
        let newTrackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .assumeInside],
            owner: self,
            userInfo: nil
        )
        
        contentView.addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }
    
    private func setupScreenChangeObserver() {
        screenChangeObserver = NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenChange()
            }
        }
    }
    
    private func handleScreenChange() {
        // Delay to ensure screen configuration is stable
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            updateNotchPosition()
        }
    }
    
    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        let resources = UncheckedSendable(value: (window: notchWindow, tracking: trackingArea))
        DispatchQueue.main.async {
            let (window, tracking) = resources.value
            if let tracking, let contentView = window?.contentView {
                contentView.removeTrackingArea(tracking)
            }
            window?.close()
        }
    }
}

private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}

// MARK: - Mouse Tracking
// Note: Mouse tracking is handled through NSTrackingArea in the NotchView, not here
// These methods were incorrectly trying to override NSObject methods that don't exist

extension NotchWindowService {
    private func handleMouseEntered() {
        Task { @MainActor in
            setHoverState(true)
        }
    }
    
    private func handleMouseExited() {
        Task { @MainActor in
            setHoverState(false)
        }
    }
    
    private func handleMouseDown() {
        // Handle click events if needed
        Task { @MainActor in
            // Potential click-to-expand functionality
        }
    }
}