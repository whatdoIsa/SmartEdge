import Foundation
import AppKit

enum NotchWindowState {
    case hidden
    case collapsed
    case expanded
    case minimized
}

// NotchContent and SystemHUDType defined in NotchModels.swift

@MainActor
protocol NotchWindowServiceProtocol: ObservableObject {
    var isVisible: Bool { get }
    var currentState: NotchWindowState { get }
    var isHovering: Bool { get }
    
    func showNotch()
    func hideNotch()
    func expandNotch()
    func minimizeNotch()
    func updateContent(_ content: NotchContent)
    func handleHover(_ hovering: Bool)
    func handleClick()
}