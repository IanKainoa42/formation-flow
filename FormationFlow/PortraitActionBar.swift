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
                    .accessibilityLabel("Athlete spacing alerts")
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
                    .accessibilityLabel("Path crossing alerts")
                }

                Button(action: onAddAthlete) {
                    Label("Athlete", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: onShowRoster) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Roster")

                Button(action: onShowNotes) {
                    Image(systemName: "note.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Notes")
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
                .controlSize(.small)
                .disabled(undoDisabled)
                .accessibilityLabel("Undo move")

                if hasTransition {
                    Button(action: onTogglePaths) {
                        Text("I")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .background(showTransitionPaths ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(showTransitionPaths ? "Hide paths" : "Show paths")
                }
            }

            Spacer()

            // Right: share
            if hasTransition {
                Button(action: onSharePreview) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Share preview")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
