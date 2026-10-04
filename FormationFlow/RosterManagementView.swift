import SwiftUI

// MARK: - Roster Management

struct RosterManagementView: View {
    @ObservedObject var store: RoutineStore
    let onAddAthlete: () -> Void
    let onDeleteAthletes: ([UUID]) -> Void
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingTeamEntry = false
    @State private var showingUpgrade = false
    @State private var copiedEntries: [RosterImportEntry] = []
    @State private var errorMessage: String?

    private var otherRoutines: [Routine] {
        store.workspace.routines.filter { $0.id != store.routine.id && !$0.roster.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        copiedEntries = []
                        if entitlementManager.isPro { showingTeamEntry = true }
                        else { showingUpgrade = true }
                    } label: {
                        Label(entitlementManager.isPro ? "Add Team from Names" : "Add Team from Names (Pro)",
                              systemImage: "person.3.fill")
                    }
                    .accessibilityIdentifier("roster.addTeam")
                    if !otherRoutines.isEmpty {
                        Menu {
                            ForEach(otherRoutines) { routine in
                                Button("\(routine.name) · \(routine.roster.count) athletes") {
                                    copyRoster(from: routine)
                                }
                            }
                        } label: {
                            Label(entitlementManager.isPro ? "Copy Roster from Routine" : "Copy Roster from Routine (Pro)",
                                  systemImage: "person.2.badge.plus")
                        }
                    }
                    Button(action: onAddAthlete) {
                        Label("Add One Athlete", systemImage: "plus")
                    }
                } footer: {
                    Text("Athletes are shared across every formation in this routine.")
                }

                Section("Athletes (\(store.routine.roster.count))") {
                    if store.routine.roster.isEmpty {
                        Text("Paste your team’s names to get started, or add one athlete.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.routine.roster) { athlete in
                        RosterAthleteEditorRow(store: store, athlete: athlete, isPro: entitlementManager.isPro)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { onDeleteAthletes([athlete.id]) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { offsets in
                        let roster = store.routine.roster
                        onDeleteAthletes(offsets.compactMap { roster.indices.contains($0) ? roster[$0].id : nil })
                    }
                    .onMove { store.moveRoster(fromOffsets: $0, toOffset: $1) }
                }
                if !entitlementManager.isPro {
                    Section {
                        Button("Unlock custom labels, roles and team entry") { showingUpgrade = true }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Manage Roster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingTeamEntry) {
                RosterTeamEntryView(store: store, initialEntries: copiedEntries)
                    .environmentObject(entitlementManager)
            }
            .sheet(isPresented: $showingUpgrade) {
                ProUpgradeSheet().environmentObject(entitlementManager)
            }
        }
    }

    private func copyRoster(from routine: Routine) {
        guard entitlementManager.isPro else { showingUpgrade = true; return }
        do {
            copiedEntries = try RosterImport.copy(routine.roster, existingLabels: store.routine.roster.map(\.label))
            errorMessage = nil
            showingTeamEntry = true
        } catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Existing Athlete Editing

private struct RosterAthleteEditorRow: View {
    @ObservedObject var store: RoutineStore
    let athlete: RosterAthlete
    let isPro: Bool
    @State private var label: String
    @State private var errorMessage: String?
    @FocusState private var editingLabel: Bool

    init(store: RoutineStore, athlete: RosterAthlete, isPro: Bool) {
        self.store = store
        self.athlete = athlete
        self.isPro = isPro
        _label = State(initialValue: athlete.label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AthleteRoleMarkerShape(role: athlete.role)
                    .fill(athlete.role.color)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                TextField("Label", text: $label)
                    .frame(width: 70)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($editingLabel)
                    .submitLabel(.done)
                    .disabled(!isPro)
                    .accessibilityLabel("Floor label for \(athlete.label)")
                    .onSubmit { saveLabel() }
                    .onChange(of: editingLabel) { _, focused in
                        if !focused { saveLabel() }
                    }
                    .onChange(of: athlete.label) { _, value in
                        if !editingLabel { label = value }
                    }
                    .onDisappear { saveLabel() }
                Spacer()
                Picker("Role for \(athlete.label)", selection: Binding(
                    get: { athlete.role },
                    set: { role in
                        guard isPro else { return }
                        store.mutateRosterAthlete(id: athlete.id) { $0.role = role }
                    }
                )) {
                    ForEach(AthleteRole.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .labelsHidden()
                .disabled(!isPro)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
    }

    private func saveLabel() {
        guard isPro, label != athlete.label else { return }
        let candidate = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = RosterImportEntry(sourceName: candidate, label: candidate, role: athlete.role)
        let otherLabels = store.routine.roster.filter { $0.id != athlete.id }.map(\.label)
        guard RosterImport.valid([entry], existingLabels: otherLabels) else {
            errorMessage = "Use a unique label with 1–3 characters and no spaces."
            label = athlete.label
            return
        }
        store.mutateRosterAthlete(id: athlete.id) { $0.label = candidate }
        errorMessage = nil
    }
}

// MARK: - Team Entry and Review

struct RosterTeamEntryView: View {
    @ObservedObject var store: RoutineStore
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var entries: [RosterImportEntry]
    @State private var errorMessage: String?
    @State private var teamRole: AthleteRole = .base
    @FocusState private var editingNames: Bool

    init(store: RoutineStore, initialEntries: [RosterImportEntry] = []) {
        self.store = store
        _entries = State(initialValue: initialEntries)
    }

    private var validEntries: Bool {
        RosterImport.valid(entries, existingLabels: store.routine.roster.map(\.label))
    }

    var body: some View {
        NavigationStack {
            Form {
                if entries.isEmpty {
                    Section {
                        TextField("One athlete per line", text: $text, axis: .vertical)
                            .lineLimit(8...16)
                            .frame(minHeight: 180, alignment: .topLeading)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Athlete names, one per line")
                            .accessibilityIdentifier("roster.names")
                            .focused($editingNames)
                    } header: {
                        Text("Paste names")
                    } footer: {
                        Text("One athlete per line. You can also paste Name and Role columns from a spreadsheet, or enter “Alex Smith, Flyer”. Unrecognized roles start as Base; check them on the next screen.")
                    }
                    Section {
                        Button("Review Athletes") { editingNames = false; prepareEntries() }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("roster.review")
                    }
                } else {
                    Section {
                        Picker("Role", selection: $teamRole) {
                            ForEach(AthleteRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        Button("Apply Role to Everyone") {
                            for index in entries.indices { entries[index].role = teamRole }
                        }
                    } header: {
                        Text("Assign together")
                    }
                    Section {
                        ForEach($entries) { $entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.sourceName).font(.subheadline).foregroundStyle(.secondary)
                                HStack {
                                    TextField("Floor label", text: $entry.label)
                                        .frame(width: 90)
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled()
                                        .accessibilityLabel("Floor label for \(entry.sourceName)")
                                    Spacer()
                                    Picker("Role for \(entry.sourceName)", selection: $entry.role) {
                                        ForEach(AthleteRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                                    }
                                    .labelsHidden()
                                }
                            }
                        }
                        .onDelete { entries.remove(atOffsets: $0) }
                    } header: {
                        Text("Review \(entries.count) \(entries.count == 1 ? "athlete" : "athletes")")
                    } footer: {
                        Text("Only floor labels (1–3 characters) and roles are saved. Full names are used here to help you review. Existing athletes and positions stay in place.")
                    }
                    if !validEntries {
                        Section {
                            Text("Each athlete needs a unique floor label with 1–3 characters and no spaces, including athletes already in this routine.")
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button("Add \(entries.count) \(entries.count == 1 ? "Athlete" : "Athletes")") { addEntries() }
                            .disabled(!validEntries || !entitlementManager.isPro)
                            .accessibilityIdentifier("roster.import")
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(entries.isEmpty ? "Add Team" : "Review Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Review Athletes") { editingNames = false; prepareEntries() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !entries.isEmpty && !text.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit Names") { entries = []; errorMessage = nil }
                    }
                }
            }
        }
    }

    private func prepareEntries() {
        do {
            entries = try RosterImport.prepare(text, existingLabels: store.routine.roster.map(\.label))
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func addEntries() {
        do {
            try store.importRoster(entries, isPro: entitlementManager.isPro)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
