import XCTest
@testable import FormationFlow

final class FreeTierLimitsTests: XCTestCase {
    func testFreeTierLimitsConstants() {
        XCTAssertEqual(FreeTierLimits.maxFormations, 2)
        XCTAssertEqual(FreeTierLimits.maxRoutines, 1)
    }
}
