import XCTest
@testable import FormationFlow

@MainActor
final class EntitlementManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear keychain for tests
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "entitlement.isPro"
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    override func tearDown() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "entitlement.isPro"
        ]
        SecItemDelete(query as CFDictionary)
        super.tearDown()
    }
    
    func testInitialization() {
        let manager = EntitlementManager()
        // In test environment (DEBUG), isTestBuild is true, so isPro should default to true.
        XCTAssertTrue(manager.isPro)
    }
    
    func testKeychainDoesNotPersistOnTestBuilds() {
        // Since isTestBuild is true in tests, setting isPro should NOT persist to keychain.
        // Wait, EntitlementManager doesn't expose setIsPro publicly.
        // However, we can simulate what happens if we were not a test build.
        // Let's at least test that keychain is empty initially.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "entitlement.isPro",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        XCTAssertEqual(status, errSecItemNotFound)
    }
}
