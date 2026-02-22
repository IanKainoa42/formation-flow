import SwiftUI

// MARK: - Formation List View

struct FormationListView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared

    @ViewBuilder
    var body: some View {
        if persistenceManager.formations.isEmpty {
            ContentUnavailableView(
                "No Saved Formations",
                systemImage: "square.grid.2x2",
                description: Text("Create a new formation from the main menu.")
            )
            .navigationTitle("Saved Formations")
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
            .navigationTitle("Saved Formations")
            .toolbar {
                EditButton()
            }
        }
    }
}

// MARK: - Previews

#Preview("Formation List") {
    NavigationStack {
        FormationListView()
    }
}
