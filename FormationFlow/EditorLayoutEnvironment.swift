import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Bridging helpers

extension LayoutSizeClass {
    init(_ sizeClass: UserInterfaceSizeClass?) {
        switch sizeClass {
        case .compact: self = .compact
        case .regular: self = .regular
        case nil: self = .unspecified
        @unknown default: self = .unspecified
        }
    }
}

enum DeviceClassBridge {
    static var current: DeviceClass {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return .phone
        case .pad: return .pad
        case .mac: return .mac
        default: return .unspecified
        }
        #else
        return .mac
        #endif
    }
}

extension EditorLayoutContext {
    static func resolve(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        bounds: CGSize?
    ) -> EditorLayoutContext {
        EditorLayoutContext.resolve(
            horizontal: LayoutSizeClass(horizontal),
            vertical: LayoutSizeClass(vertical),
            device: DeviceClassBridge.current,
            bounds: bounds
        )
    }
}

// MARK: - SwiftUI environment

private struct EditorLayoutContextKey: EnvironmentKey {
    static let defaultValue = EditorLayoutContext.fallback
}

extension EnvironmentValues {
    var editorLayoutContext: EditorLayoutContext {
        get { self[EditorLayoutContextKey.self] }
        set { self[EditorLayoutContextKey.self] = newValue }
    }
}

/// Publishes a resolved `EditorLayoutContext` from live size classes and optional bounds.
struct EditorLayoutContextReader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let bounds: CGSize
    let content: (EditorLayoutContext) -> AnyView

    init(bounds: CGSize, @ViewBuilder content: @escaping (EditorLayoutContext) -> some View) {
        self.bounds = bounds
        self.content = { AnyView(content($0)) }
    }

    var body: some View {
        let context = EditorLayoutContext.resolve(
            horizontal: horizontalSizeClass,
            vertical: verticalSizeClass,
            bounds: bounds == .zero ? nil : bounds
        )
        content(context)
            .environment(\.editorLayoutContext, context)
    }
}
