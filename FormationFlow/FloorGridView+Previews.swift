import SwiftUI

// MARK: - Previews

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var store = RoutineStore()
        @StateObject private var entitlementManager = EntitlementManager()
        @State private var selectedAthleteIDs: Set<UUID> = []
        @State private var isSwapMode = false
        @State private var triggerDeleteAthlete = false

        var body: some View {
            NavigationStack {
                FloorGridView(
                    store: store,
                    selectedAthleteIDs: $selectedAthleteIDs,
                    isSwapMode: $isSwapMode,
                    triggerDeleteAthlete: $triggerDeleteAthlete,
                    formationID: store.routine.formations.first?.id ?? UUID()
                ) {}
            }
            .environmentObject(entitlementManager)
        }
    }

    return PreviewWrapper()
}
