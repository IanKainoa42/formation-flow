import SwiftUI

@main
struct FormationFlowApp: App {
    var body: some Scene {
        WindowGroup {
            RoutineWorkspaceView()
                .preferredColorScheme(.dark)
                .tint(.orange)
        }
    }
}
