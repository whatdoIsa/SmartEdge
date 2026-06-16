import Foundation
import Combine

@MainActor
final class SystemHUDViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var isVisible = false
    @Published private(set) var hudType: SystemHUDType = .volume(0.5)
    @Published private(set) var value: Double = 0.0
    @Published private(set) var isMuted = false
    @Published private(set) var animationProgress: Double = 0.0
    
    // MARK: - Private Properties
    private var hideTimer: Timer?
    private let hideDelay: TimeInterval = 2.0
    private var cancellables = Set<AnyCancellable>()
    private let notificationCenter = NotificationCenter.default
    
    init() {
        setupNotificationObservers()
    }
    
    deinit {
        hideTimer?.invalidate()
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    func showHUD(type: SystemHUDType, value: Double, isMuted: Bool = false) {
        self.hudType = type
        self.value = value
        self.isMuted = isMuted
        self.isVisible = true

        // Defer progress update so View applies its own animation curve after the
        // primary spring transition begins. The View binds .animation(...) to
        // animationProgress with an easeInOut curve.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.animationProgress = value
        }

        scheduleHide()
    }

    func hideHUD() {
        hideTimer?.invalidate()
        hideTimer = nil

        isVisible = false
    }

    func updateValue(_ newValue: Double, isMuted: Bool = false) {
        self.value = newValue
        self.isMuted = isMuted
        self.animationProgress = newValue

        if isVisible {
            scheduleHide()
        }
    }
    
    // MARK: - Private Methods
    private func setupNotificationObservers() {
        // Listen for system HUD events from SystemHUDService
        notificationCenter
            .publisher(for: .systemHUDDidShow)
            .compactMap { $0.userInfo as? [String: Any] }
            .sink { [weak self] userInfo in
                guard let self = self,
                      let hudInfo = userInfo["hudInfo"] as? SystemHUDInfo else { return }
                
                self.showHUD(type: hudInfo.type, value: hudInfo.value, isMuted: hudInfo.isMuted)
            }
            .store(in: &cancellables)
    }
    
    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hideHUD()
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let systemHUDDidShow = Notification.Name("SystemHUDDidShow")
}

// SystemHUDType is defined in NotchModels.swift