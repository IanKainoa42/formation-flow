import sys

def patch_file(file_path):
    with open(file_path, 'r') as f:
        content = f.read()

    # Apply the first change
    search_str_1 = """    @State private var isSwapMode = false
    @State private var triggerDeleteAthlete = false
    @State private var isIPadPortrait = false"""

    replace_str_1 = """    @State private var isSwapMode = false
    @State private var triggerDeleteAthlete = false
    @State private var isIPadPortrait = false
    @State private var showingFormationDeleteConfirmation = false
    @State private var formationsToDelete: [UUID] = []"""

    content = content.replace(search_str_1, replace_str_1)

    # Apply the second change
    search_str_2 = """        } message: {
            Text("This clears the roster, formations, notes, and transition data, then starts over with one empty formation.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in"""

    replace_str_2 = """        } message: {
            Text("This clears the roster, formations, notes, and transition data, then starts over with one empty formation.")
        }
        .confirmationDialog(
            formationsToDelete.count > 1 ? "Delete \\(formationsToDelete.count) formations?" : "Delete formation?",
            isPresented: $showingFormationDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteFormations(ids: formationsToDelete)
            }
            Button("Cancel", role: .cancel) {
                formationsToDelete = []
            }
        } message: {
            Text("This will remove the selected formations and their transitions. This cannot be undone.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in"""

    content = content.replace(search_str_2, replace_str_2)

    # Apply the third change
    search_str_3 = """    private func requestFormationDeletion(_ formationIDs: [UUID]) {
        deleteFormations(ids: formationIDs)
    }"""

    replace_str_3 = """    private func requestFormationDeletion(_ formationIDs: [UUID]) {
        formationsToDelete = formationIDs
        showingFormationDeleteConfirmation = true
    }"""

    content = content.replace(search_str_3, replace_str_3)

    with open(file_path, 'w') as f:
        f.write(content)

    print("Patch applied successfully.")

patch_file('FormationFlow/FormationHomeView.swift')
