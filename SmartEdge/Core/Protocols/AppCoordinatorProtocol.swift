import Foundation

@MainActor
protocol AppCoordinatorProtocol: ObservableObject {
    
    // MARK: - Services
    
    var mediaService: MediaServiceProtocol { get }
    
    // MARK: - State
    
    var isInitialized: Bool { get }
    var isServicesRunning: Bool { get }
    var lastError: Error? { get }
    
    // MARK: - Lifecycle
    
    func initialize() async throws
    func startServices() async throws
    func stopServices() async
    func shutdown() async
    
    // MARK: - Error Handling
    
    func handleServiceError(_ error: Error, from service: String)
    func clearError()
    
    // MARK: - App Events
    
    func handleAppDidBecomeActive()
    func handleAppWillResignActive()
    func handleAppWillTerminate()
    func handleSystemSleep()
    func handleSystemWake()
}