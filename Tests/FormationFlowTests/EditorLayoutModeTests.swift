import CoreGraphics
import XCTest
@testable import FormationFlow

final class EditorLayoutModeTests: XCTestCase {

    // MARK: - Mode resolution matrix

    func testIPhonePortrait() {
        let ctx = EditorLayoutContext.fixture(mode: .iPhonePortrait)
        XCTAssertEqual(ctx.mode, .iPhonePortrait)
        XCTAssertTrue(ctx.isPhone)
        XCTAssertFalse(ctx.isPhoneLandscape)
        XCTAssertTrue(ctx.usesCompactWorkspace)
        XCTAssertTrue(ctx.showsPhonePortraitBottomChrome)
        XCTAssertFalse(ctx.showsPhoneLandscapeRail)
        XCTAssertFalse(ctx.isIPadPortrait)
    }

    func testIPhoneLandscape() {
        let ctx = EditorLayoutContext.fixture(mode: .iPhoneLandscape)
        XCTAssertEqual(ctx.mode, .iPhoneLandscape)
        XCTAssertTrue(ctx.isPhoneLandscape)
        XCTAssertTrue(ctx.isHeightConstrained)
        XCTAssertTrue(ctx.showsPhoneLandscapeRail)
        XCTAssertFalse(ctx.showsPhonePortraitBottomChrome)
        XCTAssertTrue(ctx.hidesPhoneLandscapeNavigationBar)
    }

    func testIPadPortrait() {
        let ctx = EditorLayoutContext.fixture(mode: .iPadPortrait)
        XCTAssertEqual(ctx.mode, .iPadPortrait)
        XCTAssertTrue(ctx.isIPadPortrait)
        XCTAssertFalse(ctx.usesCompactWorkspace)
        XCTAssertTrue(ctx.usesIPadPortraitWorkspace)
        XCTAssertTrue(ctx.showsBottomTransportOverlay)
        XCTAssertTrue(ctx.hidesInspectorTransportInPortrait)
        XCTAssertFalse(ctx.showsSidebarTransport)
    }

    func testIPadLandscape() {
        let ctx = EditorLayoutContext.fixture(mode: .iPadLandscape)
        XCTAssertEqual(ctx.mode, .iPadLandscape)
        XCTAssertFalse(ctx.isIPadPortrait)
        XCTAssertTrue(ctx.showsSidebarTransport)
        XCTAssertFalse(ctx.showsBottomTransportOverlay)
    }

    func testIPadCompactWidthSplitView() {
        let ctx = EditorLayoutContext.fixture(mode: .iPadCompactWidth)
        XCTAssertEqual(ctx.mode, .iPadCompactWidth)
        XCTAssertTrue(ctx.usesCompactWorkspace)
        XCTAssertFalse(ctx.isPhone)
        XCTAssertFalse(ctx.isIPadPortrait)
        XCTAssertTrue(ctx.workspaceUsesCompactNavigationStack)
    }

    func testIPadPortraitRequiresTallerBounds() {
        let portrait = EditorLayoutContext.resolve(
            horizontal: .regular,
            vertical: .regular,
            device: .pad,
            bounds: CGSize(width: 800, height: 1100)
        )
        XCTAssertTrue(portrait.isIPadPortrait)

        let landscape = EditorLayoutContext.resolve(
            horizontal: .regular,
            vertical: .regular,
            device: .pad,
            bounds: CGSize(width: 1100, height: 800)
        )
        XCTAssertFalse(landscape.isIPadPortrait)
        XCTAssertEqual(landscape.mode, .iPadLandscape)
    }

    func testPhoneForcesCompactWorkspaceEvenWithRegularHorizontal() {
        let ctx = EditorLayoutContext.resolve(
            horizontal: .regular,
            vertical: .regular,
            device: .phone,
            bounds: CGSize(width: 390, height: 844)
        )
        XCTAssertTrue(ctx.usesCompactWorkspace)
        XCTAssertEqual(ctx.mode, .iPhonePortrait)
    }

    func testSmallPhoneSELandscapeBounds() {
        let ctx = EditorLayoutContext.resolve(
            horizontal: .compact,
            vertical: .compact,
            device: .phone,
            bounds: CGSize(width: 667, height: 375)
        )
        XCTAssertEqual(ctx.mode, .iPhoneLandscape)
        XCTAssertTrue(ctx.showsPhoneLandscapeRail)
    }

    func testTransportPolicyPortraitVsLandscape() {
        let phonePortrait = EditorLayoutContext.fixture(mode: .iPhonePortrait)
        let phoneLandscape = EditorLayoutContext.fixture(mode: .iPhoneLandscape)
        let iPadPortrait = EditorLayoutContext.fixture(mode: .iPadPortrait)
        let iPadLandscape = EditorLayoutContext.fixture(mode: .iPadLandscape)

        XCTAssertTrue(phonePortrait.showsBottomTransportOverlay)
        XCTAssertFalse(phoneLandscape.showsBottomTransportOverlay)

        XCTAssertTrue(iPadPortrait.showsBottomTransportOverlay)
        XCTAssertTrue(iPadLandscape.showsSidebarTransport)
    }
}
