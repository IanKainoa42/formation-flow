import SwiftUI

// MARK: - Formation List View

struct FormationListView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared
    @State private var showingNewFormationAlert = false
    @State private var newFormationName = ""
    @State private var activeFormation: Formation?

    var body: some View {
        Group {
            if persistenceManager.formations.isEmpty {
                ContentUnavailableView(
                    "No Saved Formations",
                    systemImage: "square.grid.2x2",
                    description: Text("Tap + to create your first formation.")
                )
            } else {
                List {
                    ForEach(persistenceManager.formations) { formation in
                        NavigationLink(destination: FloorGridView(formation: formation)) {
                            HStack(spacing: 12) {
                                FormationThumbnailView(formation: formation)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6).stroke(
                                            Color.gray.opacity(0.3)))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formation.name).font(.headline)
                                    Text("\(formation.athletes.count) athletes")
                                        .font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                                if !formation.notes.isEmpty {
                                    Image(systemName: "note.text")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            persistenceManager.deleteFormation(
                                id: persistenceManager.formations[index].id)
                        }
                    }
                    .onMove { from, to in
                        persistenceManager.moveFormation(from: from, to: to)
                    }
                }
            }
        }
        .navigationTitle("Saved Formations")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !persistenceManager.formations.isEmpty {
                    EditButton()
                }
                Button(action: { showingNewFormationAlert = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Formation", isPresented: $showingNewFormationAlert) {
            TextField("Formation name", text: $newFormationName)
            Button("Create") {
                var formation = Formation()
                formation.name = newFormationName.isEmpty ? "Untitled Formation" : newFormationName
                persistenceManager.addFormation(formation)
                activeFormation = formation
                newFormationName = ""
            }
            Button("Cancel", role: .cancel) { newFormationName = "" }
        }
        .navigationDestination(item: $activeFormation) { formation in
            FloorGridView(formation: formation)
        }
    }
}

// MARK: - Previews

#Preview("Formation List") {
    NavigationStack {
        FormationListView()
    }
}
