import SwiftUI

@main
struct FormationFlowApp: App {
    @StateObject private var entitlementManager = EntitlementManager()

    var body: some Scene {
        WindowGroup {
            RoutineWorkspaceView()
                .tint(.orange)
                .environmentObject(entitlementManager)
        }
    }
}
