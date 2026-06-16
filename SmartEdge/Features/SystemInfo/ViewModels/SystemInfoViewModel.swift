import Foundation
import Combine

@MainActor
final class SystemInfoViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    init() {}
    
    deinit {
        // Cancel all Combine subscriptions
        cancellables.removeAll()
    }
}