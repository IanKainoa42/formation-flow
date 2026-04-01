import SwiftUI

struct FormationThumbnailStrip: View {
    @ObservedObject var store: RoutineStore
    @Binding var selectedFormationID: UUID?
    let canAddFormation: Bool
    let onAddFormation: () -> Void
    let onRenameFormation: (Formation) -> Void
    let onDeleteFormation: (UUID) -> Void
    let onDuplicateFormation: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(store.routine.formations.enumerated()), id: \.element.id) { index, formation in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))
                        }

                        let isSelected = formation.id == selectedFormationID
                        let accentColor = TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)

                        Button {
                            selectedFormationID = formation.id
                        } label: {
                            VStack(spacing: 3) {
                                FormationThumbnailView(
                                    athletes: store.renderedAthletes(for: formation.id),
                                    isSelected: isSelected,
                                    accentColor: accentColor
                                )

                                Text(formation.name)
                                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 56)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(formation.id)
                        .contextMenu {
                            Button {
                                onRenameFormation(formation)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(action: onDuplicateFormation) {
                                Label("Duplicate as Next", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) {
                                onDeleteFormation(formation.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    // Add formation button
                    Button(action: onAddFormation) {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .foregroundColor(.secondary.opacity(0.4))
                                .frame(width: 52, height: 40)
                                .overlay {
                                    Image(systemName: canAddFormation ? "plus" : "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                            Text("Add")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedFormationID) { _, newID in
                if let newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
        .background(.bar)
    }
}
