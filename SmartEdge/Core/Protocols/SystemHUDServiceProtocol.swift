//
//  SystemHUDServiceProtocol.swift
//  SmartEdge
//
//  Protocol for system HUD interception service
//  Based on BoringNotch patterns
//

import Foundation
import Combine

@MainActor
protocol SystemHUDServiceProtocol: ObservableObject {
    // MARK: - Published Properties
    var isIntercepting: Bool { get }
    var currentHUD: SystemHUDInfo? { get }
    var hasAccessibilityPermission: Bool { get }
    
    // MARK: - Permission Management
    func requestAccessibilityPermission()
    func checkAccessibilityPermission() -> Bool
    
    // MARK: - Interception Control
    func startIntercepting()
    func stopIntercepting()
    
    // MARK: - HUD Events
    func handleVolumeChange(_ level: Float, isMuted: Bool)
    func handleBrightnessChange(_ level: Float)
    func handleKeyboardBacklightChange(_ level: Float)
    
    // MARK: - Publishers
    var hudPublisher: AnyPublisher<SystemHUDInfo?, Never> { get }
    var interceptingPublisher: AnyPublisher<Bool, Never> { get }
}

// MARK: - Default Implementations

extension SystemHUDServiceProtocol {
    func checkAccessibilityPermission() -> Bool {
        return hasAccessibilityPermission
    }
}

// MARK: - Delegate

@MainActor
protocol SystemHUDServiceDelegate: AnyObject {
    func systemHUDService(_ service: SystemHUDService, didInterceptHUD type: SystemHUDType, value: Double)
}