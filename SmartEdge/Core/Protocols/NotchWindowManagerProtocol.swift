import Foundation

@MainActor
protocol NotchWindowManagerProtocol: AnyObject {
    var isVisible: Bool { get }
    var delegate: NotchWindowManagerDelegate? { get set }
    
    func show()
    func hide()
    func updatePosition()
    func updateNotchPosition() async throws
    func cleanup()
    
    // AppCoordinator compatibility methods
    func showNotchWindow() async throws
    func hideNotchWindow() async throws
    func showSettingsWindow() async throws
    func hideSettingsWindow() async throws
    func initialize() async throws
}

@MainActor
protocol NotchWindowManagerDelegate: AnyObject {
    func windowDidAppear()
    func windowDidDisappear()
    func windowDidChangePosition()
}