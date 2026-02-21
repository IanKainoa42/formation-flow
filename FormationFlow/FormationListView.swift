import SwiftUI

// MARK: - Formation List View

struct FormationListView: View {
    @StateObject private var persistenceManager = PersistenceManager.shared

    var body: some View {
        Group {
            if persistenceManager.formations.isEmpty {
                ContentUnavailableView(
                    "No Saved Formations",
                    systemImage: "square.grid.2x2",
                    description: Text("Create a new formation from the main menu.")
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
                                    Text("\\(formation.athletes.count) athletes")
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
                }
            }
        }
        .navigationTitle("Saved Formations")
    }
}

// MARK: - Previews

#Preview("Formation List") {
    NavigationStack {
        FormationListView()
    }
}
