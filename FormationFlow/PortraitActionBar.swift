import SwiftUI

struct PortraitActionBar: View {
    let onAddAthlete: () -> Void
    let onShowRoster: () -> Void
    let onShowNotes: () -> Void
    let onUndo: () -> Void
    let onTogglePaths: () -> Void
    let onSharePreview: () -> Void
    let showTransitionPaths: Bool
    let hasTransition: Bool
    let undoDisabled: Bool
    let hasNotes: Bool

    // Collision badges
    let collidingCount: Int
    let onCycleCollision: () -> Void
    let pathCollidingCount: Int
    let onCyclePathCollision: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left group
            HStack(spacing: 2) {
                if collidingCount > 0 {
                    Button(action: onCycleCollision) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("\(collidingCount)")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.red.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Athlete spacing alerts")
                    .accessibilityHint("Tap to cycle through collisions")
                }

                if showTransitionPaths, pathCollidingCount > 0 {
                    Button(action: onCyclePathCollision) {
                        HStack(spacing: 4) {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            Text("\(pathCollidingCount)")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Path crossing alerts")
                    .accessibilityHint("Tap to cycle through path conflicts")
                }

                Button(action: onAddAthlete) {
                    Label("Athlete", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)

                Button(action: onShowRoster) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Roster")
                .accessibilityHint("Show the athlete roster")
                .help("Show the athlete roster")

                Button(action: onShowNotes) {
                    Image(systemName: "note.text")
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Notes")
                .accessibilityHint("Show formation notes")
                .help("Show formation notes")
                .overlay(alignment: .topTrailing) {
                    if hasNotes {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }

                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(undoDisabled)
                .accessibilityLabel("Undo move")
                .accessibilityHint(undoDisabled ? "Nothing to undo" : "Undo the last move")
                .help(undoDisabled ? "Nothing to undo" : "Undo the last move")

                if hasTransition {
                    Button(action: onTogglePaths) {
                        Image(systemName: showTransitionPaths ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(showTransitionPaths ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(showTransitionPaths ? "Hide paths" : "Show paths")
                    .accessibilityHint("Toggle visibility of transition paths")
                    .help("Toggle visibility of transition paths")
                }
            }

            Spacer()

            // Right: share
            if hasTransition {
                Button(action: onSharePreview) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Share preview")
                .accessibilityHint("Share transition preview")
                .help("Share transition preview")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.bar)
    }
}
