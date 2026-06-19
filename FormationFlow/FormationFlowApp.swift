import SwiftUI
import UIKit

@main
struct FormationFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var entitlementManager = EntitlementManager()

    var body: some Scene {
        WindowGroup {
            RoutineWorkspaceView()
                .environmentObject(entitlementManager)
        }
    }
}

/// Holds the current allowed-orientation mask. The floor editor on iPhone forces
/// landscape (the wide court fills the screen); the rest of the phone app stays
/// portrait. iPad is never constrained — its default mask is `.all`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

/// Drives app-forced rotation. Setting the mask both restricts what the user can
/// rotate to and (via `requestGeometryUpdate`) actively rotates the window to a
/// valid orientation even when the device's rotation lock is on.
enum OrientationLock {
    static func set(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        guard let scene = activeWindowScene() else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
        return scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.first as? UIWindowScene
    }
}
