import sys

def patch_file(file_path):
    with open(file_path, 'r') as f:
        content = f.read()

    # Apply the second change properly now
    search_str_2 = """        } message: {
            Text("This clears the roster, formations, notes, and transition data, then starts over with one empty formation.")
        }
        .alert("Authentication Failed", isPresented: $showingAuthFailedAlert) {"""

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
        .alert("Authentication Failed", isPresented: $showingAuthFailedAlert) {"""

    content = content.replace(search_str_2, replace_str_2)

    with open(file_path, 'w') as f:
        f.write(content)

    print("Patch 2 applied successfully.")

patch_file('FormationFlow/FormationHomeView.swift')
