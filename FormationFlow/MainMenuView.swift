import SwiftUI

// MARK: - Main Menu View

struct MainMenuView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @State private var showingNewFormationAlert = false
    @State private var newFormationName = ""
    @State private var navigateToEditor = false
    @State private var activeFormation: Formation?

    var body: some View {
        VStack(spacing: 20) {
            Text("Formation Flow")
                .font(.title)
                .bold()

            Text("Digital Choreography Tool")
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()

            Button(action: { showingNewFormationAlert = true }) {
                Label("New Formation", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            NavigationLink(destination: FormationListView()) {
                Label {
                    HStack {
                        Text("Saved Formations")
                        if !persistenceManager.formations.isEmpty {
                            Text("(\\(persistenceManager.formations.count))")
                                .foregroundColor(.gray)
                        }
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.3))
                .foregroundColor(.primary)
                .cornerRadius(8)
            }

            NavigationLink(destination: TransitionSetupView()) {
                Label("Transitions", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.3))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Formation Flow")
        .alert("New Formation", isPresented: $showingNewFormationAlert) {
            TextField("Formation name", text: $newFormationName)
            Button("Create") {
                // Bug 3 fix: blank slate, not sample()
                var formation = Formation()
                formation.name = newFormationName.isEmpty ? "Untitled Formation" : newFormationName
                persistenceManager.addFormation(formation)
                activeFormation = formation
                newFormationName = ""
                navigateToEditor = true
            }
            Button("Cancel", role: .cancel) { newFormationName = "" }
        }
        .navigationDestination(isPresented: $navigateToEditor) {
            if let formation = activeFormation {
                FloorGridView(formation: formation)
            }
        }
    }
}

// MARK: - Previews

#Preview("Menu") {
    NavigationStack {
        MainMenuView()
    }
}
