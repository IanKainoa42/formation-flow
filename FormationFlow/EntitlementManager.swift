import Foundation
import StoreKit
import OSLog

@MainActor
final class EntitlementManager: ObservableObject {
    static let productID = "com.formationflow.prounlock"
    private static let cacheKey = "entitlement.isPro"
    private static let logger = Logger(subsystem: "FormationFlow", category: "Entitlement")

    @Published private(set) var isPro: Bool = false

    private var updateTask: Task<Void, Never>?

    init() {
        Self.logger.info("EntitlementManager initializing...")
        
        // Start listening for transactions
        updateTask = Task {
            await listenForTransactions()
        }
        
        // Check current entitlement status
        Task {
            await checkEntitlement()
        }
    }

    deinit {
        updateTask?.cancel()
    }

    func purchase() async throws -> PurchaseResult {
        Self.logger.info("🛒 Purchase initiated")
        
        // Load the product
        Self.logger.info("📦 Loading products...")
        let products = try await Product.products(for: [Self.productID])
        
        guard let product = products.first else {
            Self.logger.error("❌ Product not found: \(Self.productID)")
            throw PurchaseError.productUnavailable
        }
        
        Self.logger.info("✅ Product loaded: \(product.displayName) - \(product.displayPrice)")
        
        // Attempt the purchase
        Self.logger.info("💳 Starting purchase flow...")
        let result = try await product.purchase()
        
        Self.logger.info("📱 Purchase result received")
        
        switch result {
        case .success(let verification):
            Self.logger.info("✅ Purchase succeeded, verifying...")
            // Verify the transaction
            let transaction = try checkVerified(verification)
            
            // Update entitlement
            await checkEntitlement()
            
            // Finish the transaction
            await transaction.finish()
            
            Self.logger.info("🎉 Purchase completed successfully")
            return .success
            
        case .userCancelled:
            Self.logger.info("❌ User cancelled purchase")
            return .userCancelled
            
        case .pending:
            Self.logger.info("⏳ Purchase pending approval")
            return .pending
            
        @unknown default:
            Self.logger.error("❓ Unknown purchase result")
            return .failed
        }
    }

    func restore() async {
        Self.logger.info("Restoring purchases")
        await checkEntitlement()
    }

    private func checkEntitlement() async {
        var hasPurchased = false
        
        // Check all transactions for this user
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            
            if transaction.productID == Self.productID {
                hasPurchased = true
                Self.logger.info("Found verified entitlement for product: \(Self.productID)")
                break
            }
        }
        
        setIsPro(hasPurchased)
    }

    private func listenForTransactions() async {
        // Listen for transaction updates
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else {
                Self.logger.warning("Received unverified transaction")
                continue
            }
            
            Self.logger.info("Transaction update received for product: \(transaction.productID)")
            
            // Update entitlement
            await checkEntitlement()
            
            // Finish the transaction
            await transaction.finish()
        }
    }

    private func setIsPro(_ value: Bool) {
        self.isPro = value
        Self.logger.info("isPro set to: \(value)")
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            Self.logger.error("Transaction verification failed: \(error.localizedDescription)")
            throw error
        case .verified(let safe):
            return safe
        }
    }

    enum PurchaseResult {
        case success
        case userCancelled
        case pending
        case failed
    }

    enum PurchaseError: LocalizedError {
        case productUnavailable

        var errorDescription: String? {
            switch self {
            case .productUnavailable:
                return "Purchase is temporarily unavailable. Please check your connection and try again."
            }
        }
    }
}
