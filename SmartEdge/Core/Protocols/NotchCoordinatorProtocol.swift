//
//  NotchCoordinatorProtocol.swift
//  SmartEdge
//
//  Protocol for notch state coordination
//  Based on BoringNotch patterns
//

import Foundation
import Combine

@MainActor
protocol NotchCoordinatorProtocol: ObservableObject {
    // MARK: - Published Properties
    var isExpanded: Bool { get }
    var isVisible: Bool { get }
    var currentContent: NotchContent? { get }
    var currentState: NotchState { get }
    
    // MARK: - Control Methods
    func showNotch()
    func hideNotch()
    func expandNotch()
    func collapseNotch()
    
    // MARK: - Content Management
    func setContent(_ content: NotchContent)
    func clearContent()
    func updateContent(_ content: NotchContent, animated: Bool)
    
    // MARK: - State Management
    func handleHover(_ hovering: Bool)
    func handleClick()
    func handleUserInteraction()
    
    // MARK: - Publishers
    var contentPublisher: AnyPublisher<NotchContent?, Never> { get }
    var statePublisher: AnyPublisher<NotchState, Never> { get }
}

// MARK: - Default Implementations

extension NotchCoordinatorProtocol {
    func setContent(_ content: NotchContent) {
        updateContent(content, animated: true)
    }
    
    func clearContent() {
        updateContent(.collapsed, animated: true)
    }
    
    func handleUserInteraction() {
        if !isExpanded {
            expandNotch()
        }
    }
}

// MARK: - Notch Animation Configuration

struct NotchAnimationConfig {
    let duration: TimeInterval
    let delay: TimeInterval
    let springResponse: Double
    let springDampingFraction: Double
    
    static let `default` = NotchAnimationConfig(
        duration: 0.5,
        delay: 0,
        springResponse: 0.6,
        springDampingFraction: 0.8
    )
    
    static let fast = NotchAnimationConfig(
        duration: 0.3,
        delay: 0,
        springResponse: 0.4,
        springDampingFraction: 0.9
    )
    
    static let slow = NotchAnimationConfig(
        duration: 0.8,
        delay: 0,
        springResponse: 0.8,
        springDampingFraction: 0.7
    )
}

// MARK: - Notch Events

enum NotchEvent {
    case contentChanged(NotchContent)
    case stateChanged(NotchState)
    case userInteraction
    case hover(Bool)
    case timeout
}