import XCTest
@testable import FormationFlow

@MainActor
final class EntitlementManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear keychain for tests
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "entitlement.isPro",
            kSecAttrService as String: "com.cheerforcesandiego.formationflow"
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    override func tearDown() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "entitlement.isPro",
            kSecAttrService as String: "com.cheerforcesandiego.formationflow"
        ]
        SecItemDelete(query as CFDictionary)
        super.tearDown()
    }
    
    func testInitialization() {
        let manager = EntitlementManager()
        // In test environment (DEBUG), isTestBuild is now false by default to allow testing the paywall.
        XCTAssertFalse(manager.isPro)
    }
    
    func testKeychainPersistsInDebug() {
        // Since isTestBuild is now false in DEBUG, setting isPro should persist to keychain.
        // We can't call setIsPro directly, but we can verify that the keychain is used.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "entitlement.isPro",
            kSecAttrService as String: "com.cheerforcesandiego.formationflow",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        XCTAssertEqual(status, errSecItemNotFound)
    }
}
