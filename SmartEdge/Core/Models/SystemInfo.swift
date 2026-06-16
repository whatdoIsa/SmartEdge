import Foundation

struct SystemInfo {
    let cpuUsage: Double
    let memoryUsage: Double
    let batteryLevel: Double
    
    init(cpuUsage: Double = 0, memoryUsage: Double = 0, batteryLevel: Double = 1.0) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.batteryLevel = batteryLevel
    }
}