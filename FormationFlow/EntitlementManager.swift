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
        
        // Restore last known state instantly to avoid UI flicker while StoreKit checks
        self.isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)

        #if DEBUG
        if CommandLine.arguments.contains("-NonPro") {
            Self.logger.info("DEBUG: -NonPro flag set, forcing isPro = false")
            self.isPro = false
            return
        }
        #endif

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

            // Grant entitlement directly from the verified transaction.
            // Do NOT rely on a Transaction.currentEntitlements re-query here — it can
            // race and not yet include the just-completed purchase, leaving isPro=false
            // so the paywall never dismisses (looks like a failed buy). This was the
            // reported TestFlight bug: sheet appears, purchase completes, nothing unlocks.
            setIsPro(true)

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

    /// Returns the outcome of the post-sync entitlement query so callers can tell
    /// "you don't own this" apart from "we couldn't reach the store" — telling an offline
    /// paying user that no purchase was found is a lie the UI used to tell.
    @discardableResult
    func restore() async -> QueryOutcome {
        Self.logger.info("Restoring purchases — syncing with App Store")
        // Force a refresh from the App Store so previously-owned non-consumables are
        // re-delivered into Transaction.currentEntitlements. Without this, a user who
        // already owns Pro (prior purchase) sees the paywall, and tapping Upgrade hits
        // "You've already downloaded this" because re-buying an owned non-consumable is
        // refused. AppStore.sync() is the canonical restore path. May prompt for sign-in.
        var syncSucceeded = false
        do {
            try await AppStore.sync()
            syncSucceeded = true
        } catch {
            Self.logger.error("AppStore.sync failed during restore: \(error.localizedDescription, privacy: .private)")
        }
        // Only a sync that actually completed makes a subsequent empty result meaningful.
        return await checkEntitlement(authoritative: syncSucceeded)
    }

    #if DEBUG
    func debugForceProStatus() async {
        setIsPro(true)
    }

    func debugResetProStatus() async {
        setIsPro(false)
    }
    #endif

    /// Outcome of an entitlement query.
    ///
    /// `Transaction.currentEntitlements` yields an empty sequence BOTH when the user
    /// genuinely owns nothing AND when the store could not be reached (offline, signed out
    /// of the App Store, sandbox hiccup). Those two cases must be told apart before
    /// anything is revoked — collapsing them is what took Pro away from paying users.
    enum QueryOutcome {
        /// A verified, unrevoked transaction for our product was found.
        case entitled
        /// Authoritative absence — either an explicit revocation, or nothing found
        /// immediately after a successful `AppStore.sync()`. Safe to revoke on.
        case notEntitled
        /// Absence that proves nothing: we could not establish that we actually asked
        /// the store. The previous value must be held.
        case unknown
    }

    /// Pure decision: given what we currently believe and what the store said, what is `isPro`?
    ///
    /// Deliberately free of StoreKit state so the revoke rule can be reasoned about and
    /// tested directly. The whole defect this fixes lives in the `.unknown` case.
    static func resolveIsPro(current: Bool, outcome: QueryOutcome) -> Bool {
        switch outcome {
        case .entitled:    return true
        case .notEntitled: return false
        case .unknown:     return current
        }
    }

    /// - Parameter authoritative: pass `true` ONLY when a real server round-trip just
    ///   succeeded (i.e. right after `AppStore.sync()`). At launch this is always `false`:
    ///   absence there is not evidence of anything.
    @discardableResult
    private func checkEntitlement(authoritative: Bool = false) async -> QueryOutcome {
        let outcome = await queryEntitlement(authoritative: authoritative)

        if case .unknown = outcome {
            Self.logger.info("Entitlement query inconclusive (store unreachable) — holding isPro = \(self.isPro)")
        }

        setIsPro(Self.resolveIsPro(current: isPro, outcome: outcome))
        return outcome
    }

    private func queryEntitlement(authoritative: Bool) async -> QueryOutcome {
        // Check all transactions for this user
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            if transaction.productID == Self.productID {
                Self.logger.info("Found verified entitlement for product: \(Self.productID)")
                return transaction.revocationDate == nil ? .entitled : .notEntitled
            }
        }

        // Nothing found. There is NO reliable way to ask StoreKit "was that a real
        // answer?" — `Transaction.currentEntitlements` has no failure channel, and
        // `Product.products(for:)` is NOT a usable reachability probe because StoreKit
        // serves cached product metadata offline. Verified on device 2026-08-27: in
        // airplane mode the product still loads, so a probe-based check reported
        // "store reachable" and revoked a live entitlement anyway.
        //
        // So absence is only trusted when the caller just completed a real server
        // round-trip (`AppStore.sync()` in restore()). At launch, absence is held.
        // Revocations still arrive through Transaction.updates, so refunds and
        // family-sharing removal are not missed.
        if !authoritative {
            Self.logger.info("No entitlement found, but the query was not authoritative — holding")
        }
        return authoritative ? .notEntitled : .unknown
    }

    private func listenForTransactions() async {
        // Listen for transaction updates
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else {
                Self.logger.warning("Received unverified transaction")
                continue
            }
            
            Self.logger.info("Transaction update received for product: \(transaction.productID)")

            if transaction.productID == Self.productID {
                // Apply the transaction we were just handed instead of re-querying
                // currentEntitlements — exactly the reason given in purchase() above. The
                // re-query can lag behind this callback and read as "not owned" moments
                // after a successful buy, re-locking Pro. `revocationDate` is the
                // authoritative signal here. (purchase() was fixed in 4fffcce; this second
                // call site was missed and could still undo it.)
                setIsPro(transaction.revocationDate == nil)
            } else {
                await checkEntitlement()
            }

            // Finish the transaction
            await transaction.finish()
        }
    }

    private func setIsPro(_ value: Bool) {
        let changed = self.isPro != value

        // Only assign when it actually changed — isPro is @Published and a redundant
        // write would churn every observing view.
        if changed {
            self.isPro = value
            Self.logger.info("isPro set to: \(value)")
        }

        // Persist UNCONDITIONALLY. The cache can drift from the in-memory value —
        // the DEBUG -NonPro path assigns isPro directly, and init() seeds isPro from
        // the cache before StoreKit answers — so gating the write on an in-memory
        // change can leave a stale entitlement on disk that outlives the session that
        // set it. Writing every time keeps disk and memory in agreement.
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
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
