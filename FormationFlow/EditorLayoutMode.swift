import CoreGraphics

// MARK: - Pure layout inputs (UIKit/SwiftUI-free)

/// Mirrors `UIUserInterfaceIdiom` without importing UIKit so unit tests stay lightweight.
enum DeviceClass: Equatable, Sendable {
    case phone
    case pad
    case mac
    case unspecified
}

/// Mirrors `UserInterfaceSizeClass` without importing SwiftUI.
enum LayoutSizeClass: Equatable, Sendable {
    case compact
    case regular
    case unspecified
}

/// Primary editor/workspace layout bucket — one value per device × orientation combo
/// the 1.2.0 UI actually branches on.
enum EditorLayoutMode: String, CaseIterable, Sendable, Equatable {
    case iPhonePortrait
    case iPhoneLandscape
    case iPadPortrait
    case iPadLandscape
    case iPadCompactWidth
}

// MARK: - Resolved layout context

/// Central layout decisions for FormationFlow editor and workspace chrome.
/// Views should read this (via `EnvironmentValues.editorLayoutContext`) instead of
/// scattering `UIDevice` / size-class checks.
struct EditorLayoutContext: Equatable, Sendable {
    let mode: EditorLayoutMode
    /// Former `isCompactLayout`: compact horizontal size class or phone idiom.
    let usesCompactWorkspace: Bool
    let isPhone: Bool
    let isPhoneLandscape: Bool
    /// iPad held upright; **not** inferable from size class alone (needs bounds).
    let isIPadPortrait: Bool
    /// Former `isHeightConstrained`: `verticalSizeClass == .compact` (landscape phones).
    let isHeightConstrained: Bool
    let horizontalSizeClass: LayoutSizeClass
    let verticalSizeClass: LayoutSizeClass

    // MARK: Chrome / transport policy (1.2.0 behavior)

    /// Phone landscape side rail; also routine playback landscape rail width.
    var showsPhoneLandscapeRail: Bool { isPhoneLandscape }

    var showsPhonePortraitTopChrome: Bool { isPhone && !isPhoneLandscape }
    var showsPhonePortraitBottomChrome: Bool { isPhone && !isPhoneLandscape }

    /// iPad/mac split workspace uses sidebar transport; portrait iPad uses bottom overlay only.
    var showsSidebarTransport: Bool { !isIPadPortrait && !usesCompactWorkspace }

    /// Bottom floating transport (iPad portrait + phone portrait).
    var showsBottomTransportOverlay: Bool { isIPadPortrait || (isPhone && !isPhoneLandscape) }

    var hidesInspectorTransportInPortrait: Bool { isIPadPortrait }

    var usesCompactInspectorSheets: Bool { usesCompactWorkspace }

    /// Navigation bar hidden on phone landscape floor editor (FormationHomeView).
    var hidesPhoneLandscapeNavigationBar: Bool { isPhoneLandscape }

    var workspaceUsesCompactNavigationStack: Bool { usesCompactWorkspace }

    /// iPad portrait workspace (no formation sidebar).
    var usesIPadPortraitWorkspace: Bool { isIPadPortrait }

    static let fallback = EditorLayoutContext(
        mode: .iPadLandscape,
        usesCompactWorkspace: false,
        isPhone: false,
        isPhoneLandscape: false,
        isIPadPortrait: false,
        isHeightConstrained: false,
        horizontalSizeClass: .regular,
        verticalSizeClass: .regular
    )

    static func resolve(
        horizontal: LayoutSizeClass,
        vertical: LayoutSizeClass,
        device: DeviceClass,
        bounds: CGSize?
    ) -> EditorLayoutContext {
        let isPhone = device == .phone
        let isHeightConstrained = vertical == .compact
        let usesCompactWorkspace = horizontal == .compact || isPhone
        let isPhoneLandscape = isPhone && isHeightConstrained

        let isIPadPortrait: Bool = {
            guard device == .pad, let bounds else { return false }
            return bounds.height > bounds.width
        }()

        let mode: EditorLayoutMode
        if isPhone {
            mode = isPhoneLandscape ? .iPhoneLandscape : .iPhonePortrait
        } else if device == .pad {
            if isIPadPortrait {
                mode = .iPadPortrait
            } else if horizontal == .compact {
                mode = .iPadCompactWidth
            } else {
                mode = .iPadLandscape
            }
        } else {
            mode = usesCompactWorkspace ? .iPadCompactWidth : .iPadLandscape
        }

        return EditorLayoutContext(
            mode: mode,
            usesCompactWorkspace: usesCompactWorkspace,
            isPhone: isPhone,
            isPhoneLandscape: isPhoneLandscape,
            isIPadPortrait: isIPadPortrait,
            isHeightConstrained: isHeightConstrained,
            horizontalSizeClass: horizontal,
            verticalSizeClass: vertical
        )
    }
}

#if DEBUG
extension EditorLayoutContext {
    /// Fixtures for unit tests — bounds size in points (not logical class).
    static func fixture(
        mode: EditorLayoutMode,
        bounds: CGSize? = nil
    ) -> EditorLayoutContext {
        switch mode {
        case .iPhonePortrait:
            return resolve(
                horizontal: .compact,
                vertical: .regular,
                device: .phone,
                bounds: bounds ?? CGSize(width: 390, height: 844)
            )
        case .iPhoneLandscape:
            return resolve(
                horizontal: .compact,
                vertical: .compact,
                device: .phone,
                bounds: bounds ?? CGSize(width: 844, height: 390)
            )
        case .iPadPortrait:
            return resolve(
                horizontal: .regular,
                vertical: .regular,
                device: .pad,
                bounds: bounds ?? CGSize(width: 820, height: 1180)
            )
        case .iPadLandscape:
            return resolve(
                horizontal: .regular,
                vertical: .regular,
                device: .pad,
                bounds: bounds ?? CGSize(width: 1180, height: 820)
            )
        case .iPadCompactWidth:
            return resolve(
                horizontal: .compact,
                vertical: .regular,
                device: .pad,
                bounds: bounds ?? CGSize(width: 320, height: 1180)
            )
        }
    }
}
#endif
