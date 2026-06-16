import Foundation
import Darwin
import Combine

/// Polls system-wide CPU and memory usage. Emits an alert when either crosses
/// a configurable threshold. Alert emission is rate-limited so users aren't
/// spammed when the machine sits near the threshold.
@MainActor
final class SystemStatsService: ObservableObject {
    struct Snapshot: Equatable {
        let cpuUsagePercent: Double  // 0...100
        let memoryUsagePercent: Double  // 0...100
        let timestamp: Date
    }

    enum AlertKind: Equatable {
        case highCPU(percent: Double)
        case highMemory(percent: Double)

        var title: String {
            switch self {
            case .highCPU: return "High CPU Usage"
            case .highMemory: return "High Memory Usage"
            }
        }

        var icon: String {
            switch self {
            case .highCPU: return "cpu"
            case .highMemory: return "memorychip"
            }
        }

        func body() -> String {
            switch self {
            case .highCPU(let percent):
                return String(format: "CPU at %.0f%%. A heavy app may be running.", percent)
            case .highMemory(let percent):
                return String(format: "Memory at %.0f%%. Consider closing some apps.", percent)
            }
        }
    }

    @Published private(set) var snapshot: Snapshot = .init(cpuUsagePercent: 0, memoryUsagePercent: 0, timestamp: .distantPast)

    /// Set by AppCoordinator to surface alerts to the notch.
    var onAlert: ((AlertKind) -> Void)?

    // Tunables
    var cpuThreshold: Double = 80
    var memoryThreshold: Double = 90
    var pollInterval: TimeInterval = 5.0
    var alertCooldown: TimeInterval = 60.0

    // State
    private var timer: Timer?
    private var lastCPUAlert: Date?
    private var lastMemoryAlert: Date?
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Polling

    private func poll() {
        let cpu = readCPUUsage()
        let memory = readMemoryUsage()
        snapshot = Snapshot(cpuUsagePercent: cpu, memoryUsagePercent: memory, timestamp: Date())

        if cpu >= cpuThreshold {
            emitIfReady(.highCPU(percent: cpu), last: &lastCPUAlert)
        }
        if memory >= memoryThreshold {
            emitIfReady(.highMemory(percent: memory), last: &lastMemoryAlert)
        }
    }

    private func emitIfReady(_ alert: AlertKind, last: inout Date?) {
        let now = Date()
        if let last = last, now.timeIntervalSince(last) < alertCooldown {
            return
        }
        last = now
        onAlert?(alert)
    }

    // MARK: - CPU

    /// Returns aggregate CPU usage across all cores as a 0-100 percent.
    private func readCPUUsage() -> Double {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return snapshot.cpuUsagePercent
        }
        let user = cpuLoad.cpu_ticks.0
        let system = cpuLoad.cpu_ticks.1
        let idle = cpuLoad.cpu_ticks.2
        let nice = cpuLoad.cpu_ticks.3

        guard let prev = previousCPUTicks else {
            previousCPUTicks = (user, system, idle, nice)
            return 0
        }
        let userDelta = Double(user &- prev.user)
        let systemDelta = Double(system &- prev.system)
        let idleDelta = Double(idle &- prev.idle)
        let niceDelta = Double(nice &- prev.nice)
        let total = userDelta + systemDelta + idleDelta + niceDelta
        previousCPUTicks = (user, system, idle, nice)
        guard total > 0 else { return 0 }
        let busy = userDelta + systemDelta + niceDelta
        return min(100, max(0, (busy / total) * 100))
    }

    // MARK: - Memory

    /// Returns memory usage (active + wired) as a 0-100 percent of total RAM.
    private func readMemoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return snapshot.memoryUsagePercent
        }
        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(100, max(0, (used / total) * 100))
    }
}
