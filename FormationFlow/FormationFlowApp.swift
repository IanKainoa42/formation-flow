import SwiftUI

@main
struct FormationFlowApp: App {
    @StateObject private var persistenceManager = PersistenceManager.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MainMenuView()
            }
            .environmentObject(persistenceManager)
        }
    }
}

#Preview {
    NavigationStack {
        MainMenuView()
    }
}
