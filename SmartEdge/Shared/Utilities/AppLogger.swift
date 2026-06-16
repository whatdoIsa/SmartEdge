import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.smartedge.app"

    static let media = Logger(subsystem: subsystem, category: "Media")
    static let battery = Logger(subsystem: subsystem, category: "Battery")
    static let bluetooth = Logger(subsystem: subsystem, category: "Bluetooth")
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")
    static let shelf = Logger(subsystem: subsystem, category: "Shelf")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let hud = Logger(subsystem: subsystem, category: "HUD")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let general = Logger(subsystem: subsystem, category: "App")
}
