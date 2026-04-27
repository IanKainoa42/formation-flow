import Foundation
import StoreKit
import OSLog

@MainActor
final class EntitlementManager: ObservableObject {
    static let productID = "com.formationflow.prounlock"
    private static let cacheKey = "entitlement.isPro"
    private static let logger = Logger(subsystem: "FormationFlow", category: "Entitlement")

    @Published private(set) var isPro: Bool

    private var updateTask: Task<Void, Never>?

    /// True for debug builds and TestFlight (sandbox receipt), false for App Store.
    private static var isTestBuild: Bool {
        #if DEBUG
        return true
        #else
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            return receiptURL.lastPathComponent == "sandboxReceipt"
        }
        return false
        #endif
    }

    init() {
        if Self.isTestBuild {
            self.isPro = true
        } else {
            self.isPro = Self.readIsProFromKeychain()
        }
        updateTask = Task { [weak self] in
            await self?.checkEntitlement()
            await self?.listenForTransactions()
        }
    }

    private static func readIsProFromKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: cacheKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject? = nil
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return data == Data([1])
        }
        return false
    }

    private static func writeIsProToKeychain(_ value: Bool) {
        let valueData = Data([value ? 1 : 0])
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: cacheKey
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: valueData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        } else {
            var newQuery = query
            newQuery[kSecValueData as String] = valueData
            newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(newQuery as CFDictionary, nil)
        }
    }

    deinit {
        updateTask?.cancel()
    }

    func purchase() async throws -> PurchaseResult {
        let products = try await Product.products(for: [Self.productID])
        guard let product = products.first else {
            Self.logger.error("Product not found: \(Self.productID, privacy: .private)")
            throw PurchaseError.productUnavailable
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                setIsPro(true)
                return .success
            }
            return .failed
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .failed
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            Self.logger.error("AppStore.sync failed during restore: \(error.localizedDescription, privacy: .private)")
        }
        await checkEntitlement()
    }

    private func checkEntitlement() async {
        if Self.isTestBuild {
            setIsPro(true)
            return
        }
        var foundPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                foundPro = true
                break
            }
        }
        setIsPro(foundPro)
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.productID {
                    let active = transaction.revocationDate == nil
                    setIsPro(active)
                }
                await transaction.finish()
            }
        }
    }

    private func setIsPro(_ value: Bool) {
        guard isPro != value else { return }
        isPro = value
        Self.writeIsProToKeychain(value)
        Self.logger.log("isPro=\(value, privacy: .private)")
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
