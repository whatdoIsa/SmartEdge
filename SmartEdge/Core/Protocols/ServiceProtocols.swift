//
//  ServiceProtocols.swift
//  SmartEdge
//

import Foundation
import AppKit
import EventKit
import CoreBluetooth
import Combine

// This file serves as an index for all service protocols
// Individual protocols are defined in separate files for better organization

// MARK: - Core Service Protocols

// NotchWindowManagerProtocol - defined in NotchWindowProtocol.swift
// MediaServiceProtocol - defined in MediaServiceProtocol.swift
// SettingsServiceProtocol - defined in SettingsServiceProtocol.swift (to be created)
// SystemServiceProtocol - defined in SystemServiceProtocol.swift (to be created)
// SystemHUDServiceProtocol - defined in SystemHUDServiceProtocol.swift (to be created)

// MARK: - System Monitoring Protocols

// BatteryServiceProtocol - defined in BatteryServiceProtocol.swift
// BluetoothServiceProtocol - defined in BluetoothServiceProtocol.swift

// MARK: - Shelf Service Protocols

// ShelfServiceProtocol - defined in ShelfServiceProtocol.swift
@MainActor
protocol ClipboardMonitorServiceProtocol {
    var clipboardUpdatesPublisher: AnyPublisher<ClipboardItem, Never> { get }

    func startMonitoring() async
    func stopMonitoring() async
    func getCurrentClipboard() async -> ClipboardItem?
    func getClipboardHistory() async -> [ClipboardItem]
    func clearHistory() async
}
// FileSharingServiceProtocol - defined in ShelfServiceProtocol.swift

// MARK: - Mock Services (for testing and development)

// These will be replaced with actual implementations as services are developed

// MockShelfService is defined in ShelfServiceProtocol.swift to avoid circular dependencies

// MockCalendarService is defined in CalendarServiceProtocol.swift to avoid circular dependencies

// MockBatteryService is defined in BatteryServiceProtocol.swift to avoid circular dependencies

// MockBluetoothService is defined in BluetoothServiceProtocol.swift to avoid circular dependencies

// MARK: - Protocol Requirements

// These protocols need to be defined in their respective files:

// Simplified protocols without missing types
@MainActor
protocol SettingsServiceProtocol {
    var settingsPublisher: AnyPublisher<AppSettings, Never> { get }
    func initialize() async throws
    func resetToDefaults() async
    func getCurrentSettings() async -> AppSettings
}

@MainActor
protocol SystemServiceProtocol {
    var systemEventPublisher: AnyPublisher<SystemEvent, Never> { get }
    func initialize() async throws
    func requestAllPermissions() async throws -> Bool
}

// MockSystemHUDService is defined in SystemHUDServiceProtocol.swift to avoid circular dependencies

// MockMediaService is defined in MediaServiceProtocol.swift to avoid circular dependencies

// MockNotchCoordinator is defined in NotchCoordinatorProtocol.swift to avoid circular dependencies

// CalendarServiceProtocol defined in CalendarServiceProtocol.swift

// CalendarEvent defined in CalendarModels.swift