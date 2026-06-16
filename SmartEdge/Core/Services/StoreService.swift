import Foundation
import StoreKit

/// StoreKit 2 entitlement + purchase manager for the single "SmartEdge Pro"
/// non-consumable unlock.
///
/// Monetization model (decided 2026-06-15): Freemium. The free tier keeps
/// music + clock + the basic notch; Pro unlocks Shelf, Calendar, and
/// Pomodoro. One-time purchase, no subscription.
///
/// StoreKit 2 (macOS 12+; our target is 13) gives us verified transactions
/// without a receipt-validation server — `Transaction.currentEntitlements`
/// is the source of truth and is cryptographically verified by the OS.
///
/// For local testing before App Store Connect is configured, add the bundled
/// `SmartEdge.storekit` configuration file to the run scheme (Xcode → Edit
/// Scheme → Run → Options → StoreKit Configuration). In production the same
/// product ID resolves against App Store Connect automatically.
@MainActor
final class StoreService: ObservableObject {

    /// Must match the product ID created in App Store Connect (and the local
    /// .storekit file). Reverse-DNS under the app's bundle ID by convention.
    static let proProductID = "com.smartedge.app.pro"

    /// The single source of truth the rest of the app gates on.
    @Published private(set) var isPro = false
    /// Loaded product (nil until `loadProducts` succeeds) — drives the
    /// localized price string in the Pro settings panel.
    @Published private(set) var proProduct: Product?
    @Published private(set) var purchaseInFlight = false
    @Published private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Start listening for transactions BEFORE the first entitlement
        // refresh so a purchase that completes on another device / mid-launch
        // isn't missed.
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Loading

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
            if proProduct == nil {
                AppLogger.general.error("StoreKit: Pro product not found (App Store Connect / .storekit not configured?)")
            }
        } catch {
            lastError = error.localizedDescription
            AppLogger.general.error("StoreKit loadProducts failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Purchase / Restore

    func purchasePro() async {
        guard let product = proProduct else {
            // Try a reload in case products weren't ready yet.
            await loadProducts()
            guard proProduct != nil else {
                lastError = "Product unavailable. Check your connection and try again."
                return
            }
            return await purchasePro()
        }

        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                } else {
                    lastError = "Purchase could not be verified."
                }
            case .userCancelled:
                break  // silent — user backed out
            case .pending:
                // Ask-to-Buy / SCA — entitlement arrives later via the
                // Transaction.updates listener.
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
            AppLogger.general.error("StoreKit purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Restore: StoreKit 2 entitlements sync automatically, but the App Store
    /// guidelines require an explicit "Restore Purchases" affordance.
    /// `AppStore.sync()` forces a refresh against the account.
    func restore() async {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            try await AppStore.sync()
        } catch {
            // sync throws if the user cancels the sign-in sheet — not fatal.
            AppLogger.general.notice("StoreKit AppStore.sync ended: \(error.localizedDescription, privacy: .public)")
        }
        await refreshEntitlement()
    }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID, transaction.revocationDate == nil {
                entitled = true
            }
        }
        if isPro != entitled { isPro = entitled }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    // MARK: - Display

    /// Localized price string for the Pro product ("$7.99" / "₩9,900"),
    /// or a fallback while the product is still loading.
    var proPriceText: String {
        proProduct?.displayPrice ?? "—"
    }
}
