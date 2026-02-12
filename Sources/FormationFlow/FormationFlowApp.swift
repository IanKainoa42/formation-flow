import SwiftUI

@main
struct FormationFlowApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MainMenuView()
            }
        }
    }
}

#Preview {
    NavigationStack {
        MainMenuView()
    }
}
