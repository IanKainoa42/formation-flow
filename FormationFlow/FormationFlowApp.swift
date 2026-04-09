import SwiftUI

@main
struct FormationFlowApp: App {
    @StateObject private var entitlementManager = EntitlementManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RoutineWorkspaceView()
                .environmentObject(entitlementManager)
                .blur(radius: (scenePhase == .background || scenePhase == .inactive) ? 15 : 0)
        }
    }
}
