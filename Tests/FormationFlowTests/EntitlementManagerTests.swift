import XCTest
@testable import FormationFlow

/// NOTE: this project has NO test target — `Tests/` is not referenced by
/// `FormationFlow.xcodeproj/project.pbxproj`, so nothing here is compiled or run by
/// `xcodebuild test`. Kept accurate so it is usable the day a target is wired up.
@MainActor
final class EntitlementManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EntitlementStore.reset()
    }

    override func tearDown() {
        EntitlementStore.reset()
        super.tearDown()
    }

    func testInitializationDefaultsToNonPro() {
        let manager = EntitlementManager()
        XCTAssertFalse(manager.isPro)
    }

    /// The entitlement cache must not be readable/writable through UserDefaults —
    /// that was the forgeable paywall bypass (IAN-544).
    func testEntitlementIsNotStoredInUserDefaults() {
        EntitlementStore.save(true)
        XCTAssertNil(
            UserDefaults.standard.object(forKey: "entitlement.isPro"),
            "The entitlement must live in the Keychain, never in user-writable UserDefaults."
        )
    }

    /// A value planted in UserDefaults by an attacker (or an older build) must never be
    /// adopted — it is purged, not migrated.
    func testForgedUserDefaultsValueIsNotTrusted() {
        UserDefaults.standard.set(true, forKey: "entitlement.isPro")
        let manager = EntitlementManager()
        XCTAssertFalse(manager.isPro, "A forged UserDefaults value must not grant Pro.")
        XCTAssertNil(
            UserDefaults.standard.object(forKey: "entitlement.isPro"),
            "The legacy key must be purged on init."
        )
    }

    func testStoreRoundTrips() {
        XCTAssertFalse(EntitlementStore.load())
        EntitlementStore.save(true)
        XCTAssertTrue(EntitlementStore.load())
        EntitlementStore.save(false)
        XCTAssertFalse(EntitlementStore.load())
    }
}
