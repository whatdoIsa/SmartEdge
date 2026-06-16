import SwiftUI
import Combine

/*
 Threading Safety Guide for SmartEdge
 
 This file provides examples and patterns for thread-safe UI updates.
 ALL ViewModels and Services in this project follow these patterns.
 
 CRITICAL RULE: All @Published property updates MUST happen on @MainActor
 */

// MARK: - ✅ CORRECT: ViewModel with @MainActor

@MainActor
final class ThreadSafeViewModel: ObservableObject {
    @Published var data: String = ""
    @Published var isLoading: Bool = false
    
    private var timer: Timer?
    
    // ✅ All methods automatically run on main actor
    func updateData(_ newData: String) {
        data = newData  // Safe: already on main actor
    }
    
    // ✅ Timer with main actor dispatch
    func startPeriodicUpdates() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.data = "Updated at \(Date())"
            }
        }
    }
    
    // ✅ Background work with UI update
    func loadDataInBackground() {
        isLoading = true  // Safe: on main actor
        
        Task {
            // Heavy work on background thread
            let result = await Task.detached {
                // Simulate heavy work
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return "Background result"
            }.value
            
            // UI update back on main actor (automatic because class is @MainActor)
            data = result
            isLoading = false
        }
    }
}

// MARK: - ✅ CORRECT: Service with proper threading

@MainActor
final class ThreadSafeService: ObservableObject {
    @Published var status: String = ""
    
    weak var delegate: ThreadSafeServiceDelegate?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    // ✅ Notifications received on main queue
    private func setupNotifications() {
        NotificationCenter.default
            .publisher(for: .NSApplicationDidBecomeActive)
            .receive(on: DispatchQueue.main)  // Ensure main thread
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppActivation()
                }
            }
            .store(in: &cancellables)
    }
    
    // ✅ Delegate callback with main thread guarantee
    private func handleAppActivation() {
        status = "App activated"
        delegate?.serviceDidUpdate(self)
    }
    
    // ✅ Async operation with proper threading
    func performAsyncOperation() {
        Task {
            do {
                let result = try await performBackgroundWork()
                
                // UI update guaranteed on main thread
                status = "Operation completed: \(result)"
                delegate?.serviceDidUpdate(self)
                
            } catch {
                status = "Operation failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func performBackgroundWork() async throws -> String {
        // This runs on background thread automatically
        return "Background work result"
    }
}

protocol ThreadSafeServiceDelegate: AnyObject {
    func serviceDidUpdate(_ service: ThreadSafeService)
}

// MARK: - ❌ INCORRECT PATTERNS (DON'T DO THIS)

/*
// ❌ BAD: ViewModel without @MainActor
final class UnsafeViewModel: ObservableObject {
    @Published var data: String = ""  // Can be updated from any thread!
    
    func updateFromBackground() {
        DispatchQueue.global().async {
            self.data = "Updated"  // ❌ CRASH: Publishing changes from background thread
        }
    }
}

// ❌ BAD: Timer without main thread dispatch
private func setupUnsafeTimer() {
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        self?.data = "Updated"  // ❌ May not be on main thread
    }
}

// ❌ BAD: Direct DispatchQueue.main.async (use Task { @MainActor } instead)
private func updateUIPoorly() {
    DispatchQueue.global().async {
        let result = doWork()
        
        DispatchQueue.main.async {  // ❌ OLD PATTERN
            self.data = result
        }
    }
}
*/

// MARK: - ✅ CORRECT PATTERNS FOR COMMON SCENARIOS

extension ThreadSafeViewModel {
    
    // ✅ System notification handling
    func setupSystemNotifications() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenChange()
                }
            }
            .store(in: &cancellables)
    }
    
    // ✅ Combine publisher with UI updates
    func setupCombinePublisher() {
        URLSession.shared.dataTaskPublisher(for: URL(string: "https://api.example.com")!)
            .map { $0.data }
            .decode(type: APIResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)  // Ensure main thread
            .sink(
                receiveCompletion: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.isLoading = false
                    }
                },
                receiveValue: { [weak self] response in
                    Task { @MainActor [weak self] in
                        self?.data = response.message
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // ✅ File system monitoring with UI updates
    func startFileMonitoring() {
        let fileManager = FileManager.default
        
        Task.detached {
            // Background file monitoring
            while !Task.isCancelled {
                let exists = fileManager.fileExists(atPath: "/some/path")
                
                await MainActor.run {
                    self.data = exists ? "File exists" : "File missing"
                }
                
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    
    // ✅ CoreData or heavy computation
    func performHeavyComputation() {
        Task {
            isLoading = true
            
            let result = await Task.detached(priority: .userInitiated) {
                // Heavy computation on background thread
                var sum = 0
                for i in 0..<1_000_000 {
                    sum += i
                }
                return "Computed: \(sum)"
            }.value
            
            // UI update automatically on main thread
            data = result
            isLoading = false
        }
    }
}

// MARK: - Helper Types

private struct APIResponse: Codable {
    let message: String
}

/*
 SUMMARY OF THREADING RULES:
 
 1. ✅ ALL ViewModels must be @MainActor
 2. ✅ ALL Services with @Published properties must be @MainActor
 3. ✅ Use Task { @MainActor } for Timer callbacks
 4. ✅ Use .receive(on: DispatchQueue.main) for Combine publishers
 5. ✅ Use Task.detached for heavy work, then await MainActor.run for UI updates
 6. ✅ Set CBCentralManager delegate queue to .main
 7. ✅ Use NotificationCenter.default.publisher(...).receive(on: .main)
 
 ❌ NEVER update @Published properties from background threads
 ❌ NEVER use DispatchQueue.main.async (use Task { @MainActor })
 ❌ NEVER assume delegate callbacks are on main thread
 */