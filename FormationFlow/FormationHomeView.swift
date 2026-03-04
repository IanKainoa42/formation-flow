import SwiftUI

// MARK: - Formation Home View

struct FormationHomeView: View {
    enum Tab: String, CaseIterable {
        case start = "Start"
        case end = "End"
        case transition = "Transition"
    }

    @State private var selectedTab: Tab = .start
    @State private var startFormation: Formation
    @State private var endFormation: Formation

    init() {
        let base = Formation.bowlingPin(name: "Start")
        var end = base
        end.id = UUID()
        end.name = "End"
        _startFormation = State(initialValue: base)
        _endFormation = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch selectedTab {
                case .start:
                    FloorGridView(formation: $startFormation)
                case .end:
                    FloorGridView(formation: $endFormation)
                case .transition:
                    TransitionPlayerView(
                        startFormation: startFormation,
                        endFormation: endFormation
                    )
                }
            }
            .navigationTitle(selectedTab.rawValue)
            .toolbar {
                #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: resetAll) {
                            Label("Reset All", systemImage: "arrow.counterclockwise")
                        }
                    }
                #else
                    ToolbarItem {
                        Button(action: resetAll) {
                            Label("Reset All", systemImage: "arrow.counterclockwise")
                        }
                    }
                #endif
            }
        }
    }

    private func resetAll() {
        let base = Formation.bowlingPin(name: "Start")
        var end = base
        end.id = UUID()
        end.name = "End"
        startFormation = base
        endFormation = end
    }
}

// MARK: - Previews

#Preview {
    FormationHomeView()
}
