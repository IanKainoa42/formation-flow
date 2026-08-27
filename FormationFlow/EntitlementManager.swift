import Foundation
import StoreKit
import OSLog
import Security

@MainActor
final class EntitlementManager: ObservableObject {
    static let productID = "com.formationflow.prounlock"
    private static let store = EntitlementStore.self
    private static let logger = Logger(subsystem: "FormationFlow", category: "Entitlement")

    @Published private(set) var isPro: Bool = false

    private var updateTask: Task<Void, Never>?

    init() {
        Self.logger.info("EntitlementManager initializing...")
        
        // Drop any value left in UserDefaults by earlier builds. It is NOT migrated:
        // UserDefaults is user-writable, so trusting it here would launder a forged
        // entitlement into trusted storage. A real purchase is re-verified by StoreKit on
        // the first online launch.
        Self.store.purgeLegacyDefaults()

        // Restore last known state instantly to avoid UI flicker while StoreKit checks.
        self.isPro = Self.store.load()

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
        // change can leave a stale entitlement outliving the session that set it.
        Self.store.save(value)
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

/// Integrity-protected storage for the cached entitlement flag.
///
/// This is NOT about secrecy — `isPro` is not a secret. It is about the value being
/// **unforgeable**. It previously lived in `UserDefaults`, which is user-writable:
/// `defaults write com.ianrichardson.formationflow entitlement.isPro -bool YES` unlocked
/// Pro on the Catalyst build. That matters more since the entitlement check stopped
/// revoking on unverifiable launches, because a forged value now survives indefinitely
/// offline (see EntitlementManager.queryEntitlement).
enum EntitlementStore {
    /// Versioned. Builds from Mar-May 2026 wrote a Keychain item at the UNVERSIONED
    /// account below, using this same service. Keychain items survive app upgrades, so
    /// reusing that account silently adopts whatever those builds left behind — including
    /// DEBUG force-unlock grants — with no way to tell a real purchase from a stale one.
    /// Bump this suffix if the meaning of the stored value ever changes again.
    private static let account = "entitlement.isPro.v2"
    private static let service = "com.cheerforcesandiego.formationflow"

    /// Pre-versioning storage. Both are deleted, never read.
    private static let legacyKeychainAccount = "entitlement.isPro"
    private static let legacyDefaultsKey = "entitlement.isPro"
    private static let logger = Logger(subsystem: "FormationFlow", category: "EntitlementStore")

    /// ⚠️ DO NOT "tighten" this to `WhenPasscodeSet…` or `WhenUnlocked…`.
    ///
    /// This exact line has been escalated twice by automated security passes —
    /// `AfterFirstUnlockThisDeviceOnly` → `WhenUnlockedThisDeviceOnly` (e795eb7) →
    /// `WhenPasscodeSetThisDeviceOnly` (8bc74b6) — and Keychain storage was then removed
    /// outright. `WhenPasscodeSet…` cannot be written at all on a device with no passcode
    /// and is destroyed if the user removes their passcode, which silently breaks the
    /// entitlement cache for those users. `AfterFirstUnlock…` is correct here: the value
    /// is an integrity-protected flag, not a secret, and it must be readable on every
    /// launch. `ThisDeviceOnly` keeps it out of iCloud Keychain and device backups, so an
    /// entitlement cannot ride a restore onto another device.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
    }

    static func load() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let first = data.first else {
            // Absent (or unreadable) reads as "not entitled" — never as an error the caller
            // has to handle. StoreKit is the source of truth; this is only a launch hint.
            return false
        }
        return first == 1
    }

    static func save(_ value: Bool) {
        let data = Data([value ? 1 : 0])

        // Update in place if present, otherwise add. Accessibility is set on both paths so
        // an item written by an older build is corrected rather than left as-is.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data, kSecAttrAccessible as String: accessibility] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = accessibility
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Keychain add failed: \(addStatus)")
            }
            return
        }

        logger.error("Keychain update failed: \(updateStatus)")
    }

    /// Delete every pre-versioning store. Called on every init so a downgrade/re-upgrade
    /// cycle cannot leave an adoptable value behind.
    ///
    /// Neither is migrated. UserDefaults is user-writable, and the unversioned Keychain
    /// item has no provenance — on a device that ran the Mar-May builds it may hold a
    /// DEBUG force-unlock grant that was never a purchase. StoreKit re-verifies a real
    /// purchase on the first online launch, which is the only trustworthy source.
    static func purgeLegacyDefaults() {
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)

        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: legacyKeychainAccount,
            kSecAttrService as String: service
        ] as CFDictionary)
    }

    #if DEBUG
    static func reset() {
        SecItemDelete(baseQuery as CFDictionary)
        purgeLegacyDefaults()
    }
    #endif
}
