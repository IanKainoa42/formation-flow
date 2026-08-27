import XCTest
@testable import FormationFlow

/// Regression cover for the entitlement revoke rule (IAN-517 follow-up).
///
/// The defect: `checkEntitlement()` ended in an unconditional `setIsPro(hasPurchased)`.
/// `Transaction.currentEntitlements` yields an empty sequence when the store cannot be
/// reached (offline, signed out of the App Store, sandbox hiccup) exactly as it does when
/// the user owns nothing — so an inconclusive query revoked a paid entitlement.
///
/// NOTE: this project has NO test target — `Tests/` is not referenced by
/// `FormationFlow.xcodeproj/project.pbxproj`, so this file is not compiled or run by
/// `xcodebuild test` today. It documents the contract and is ready for the day a test
/// target is wired. The same assertions were verified against the real compiled source
/// via a standalone `swiftc` harness.
@MainActor
final class EntitlementRevocationTests: XCTestCase {

    /// The regression itself: an inconclusive query must never take Pro away.
    func testStoreUnreachableDoesNotRevokePaidEntitlement() {
        XCTAssertTrue(
            EntitlementManager.resolveIsPro(current: true, outcome: .unknown),
            "An unreachable store must hold the existing entitlement, not revoke it."
        )
    }

    /// The other half: an inconclusive query must not hand out Pro either.
    func testStoreUnreachableDoesNotGrantEntitlement() {
        XCTAssertFalse(
            EntitlementManager.resolveIsPro(current: false, outcome: .unknown),
            "An unreachable store must not grant Pro to a free user."
        )
    }

    /// Revocation must still work when the store actually answered — refunds,
    /// family-sharing removal, and a forged local cache all depend on this.
    func testAuthoritativeNotEntitledRevokes() {
        XCTAssertFalse(
            EntitlementManager.resolveIsPro(current: true, outcome: .notEntitled),
            "A store that answered and reported no ownership must revoke."
        )
    }

    func testEntitledGrantsAndHolds() {
        XCTAssertTrue(EntitlementManager.resolveIsPro(current: false, outcome: .entitled))
        XCTAssertTrue(EntitlementManager.resolveIsPro(current: true, outcome: .entitled))
    }

    func testNotEntitledStaysOff() {
        XCTAssertFalse(EntitlementManager.resolveIsPro(current: false, outcome: .notEntitled))
    }
}
