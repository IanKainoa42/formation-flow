import SwiftUI

enum SwapFormationTarget: String, CaseIterable {
    case start = "Start"
    case end = "End"
}

/// How many transition paths the editor draws at once. Persisted as a user
/// preference so coaches can dial down clutter. Default is `.selectedOnly` —
/// only the selected athlete's path shows, everything else recedes.
enum PathDisplayScope: String, CaseIterable, Identifiable {
    case off
    case selectedOnly
    case currentFormation
    case allFormations

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Hidden"
        case .selectedOnly: return "Selected Athlete"
        case .currentFormation: return "This Formation"
        case .allFormations: return "All Formations"
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "eye.slash"
        case .selectedOnly: return "scope"
        case .currentFormation: return "point.topleft.down.curvedto.point.bottomright.up"
        case .allFormations: return "square.stack.3d.up.fill"
        }
    }
}

/// How idle transition paths are previewed. `flow` = the ambient comet pulse
/// sweeping each path; `step` = static "one tick per count" markers. Persisted
/// so the coach's choice sticks. Default `.flow` (on-brand for FormationFlow).
enum TransitionPreviewMode: String, CaseIterable, Identifiable {
    case flow
    case step

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flow: return "Flow"
        case .step: return "Step"
        }
    }

    var systemImage: String {
        switch self {
        case .flow: return "wind"
        case .step: return "figure.walk"
        }
    }
}

struct FormationMoveUndoSnapshot: Equatable {
    let formationID: UUID
    let positions: [UUID: CGPoint]
}

struct PathEditUndoSnapshot {
    let startFormationID: UUID
    let endFormationID: UUID
    let affectedAthleteIDs: Set<UUID>
    let selectedAthleteIDs: Set<UUID>
    let transitions: [UUID: AthleteTransition]
    let startPositions: [UUID: CGPoint]
    let endPositions: [UUID: CGPoint]
    let message: String
}

/// Keeps high-frequency waypoint drag state out of `RoutineStore`. The draft is
/// intentionally not observable: `TransitionPlayer` publishes the lightweight
/// preview, while the persisted routine changes once when the gesture ends.
@MainActor
final class PathHandleDragDraft {
    let startFormationID: UUID
    let endFormationID: UUID
    let originalSpec: TransitionSpec
    let undoSnapshot: PathEditUndoSnapshot?
    var transitionSpec: TransitionSpec

    init(
        startFormationID: UUID,
        endFormationID: UUID,
        transitionSpec: TransitionSpec,
        undoSnapshot: PathEditUndoSnapshot?
    ) {
        self.startFormationID = startFormationID
        self.endFormationID = endFormationID
        self.originalSpec = transitionSpec
        self.undoSnapshot = undoSnapshot
        self.transitionSpec = transitionSpec
    }

    var hasChanges: Bool {
        transitionSpec != originalSpec
    }
}

struct PathHandleHit {
    let athleteID: UUID
    let waypointID: UUID?
    let position: CGPoint
}

let editorToolbarButtonHeight: CGFloat = 44

struct EditorToolbarButtonLabel: View {
    let title: String
    let systemImage: String
    var isProminent = false
    var indicatorColor: Color?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)

            if let indicatorColor {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isProminent ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .frame(height: editorToolbarButtonHeight)
        .background {
            Capsule(style: .continuous)
                .fill(isProminent ? Color.coral : Color.secondary.opacity(0.14))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(isProminent ? 0 : 0.12), lineWidth: 0.5)
        }
        .contentShape(Capsule(style: .continuous))
        .fixedSize()
    }
}

enum PathSketchAnchorSide {
    case start
    case end
}

struct FormationBadgeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0))
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SnapResult {
    let translation: CGPoint
    let alignmentGuides: [AlignmentGuideRenderItem]
    let mirrorGuides: [FormationMirrorGuideRenderItem]
}

struct FormationMirrorSnapResult {
    let translation: CGPoint
    let guides: [FormationMirrorGuideRenderItem]
}

enum FormationMirrorSnapEngine {
    static func snap(
        translation: CGPoint,
        startingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        threshold: CGFloat = 0.8
    ) -> FormationMirrorSnapResult {
        guard !startingPositions.isEmpty, !otherAthletePositions.isEmpty else {
            return FormationMirrorSnapResult(translation: translation, guides: [])
        }

        let movingPositions = startingPositions.map {
            CGPoint(x: $0.x + translation.x, y: $0.y + translation.y)
        }

        guard let match = bestMirrorMatch(
            movingPositions: movingPositions,
            otherAthletePositions: otherAthletePositions,
            threshold: threshold
        ) else {
            return FormationMirrorSnapResult(translation: translation, guides: [])
        }

        let adjustedTranslation = CGPoint(
            x: translation.x + match.delta.x,
            y: translation.y + match.delta.y
        )
        let adjustedMovingPositions = startingPositions.map {
            CGPoint(x: $0.x + adjustedTranslation.x, y: $0.y + adjustedTranslation.y)
        }

        return FormationMirrorSnapResult(
            translation: adjustedTranslation,
            guides: mirrorGuides(
                movingPositions: adjustedMovingPositions,
                otherAthletePositions: otherAthletePositions
            )
        )
    }

    private static func bestMirrorMatch(
        movingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        threshold: CGFloat
    ) -> MirrorMatch? {
        let mirrorAxisX = CourtConstants.width / 2
        let thresholdSquared = threshold * threshold
        var bestMatch: MirrorMatch?

        for movingPosition in movingPositions {
            for sourcePosition in otherAthletePositions {
                guard abs(sourcePosition.x - mirrorAxisX) > 0.25 else { continue }

                let targetPosition = mirroredPosition(for: sourcePosition)
                let delta = CGPoint(
                    x: targetPosition.x - movingPosition.x,
                    y: targetPosition.y - movingPosition.y
                )
                guard abs(delta.x) <= threshold, abs(delta.y) <= threshold else { continue }

                let distanceSquared = delta.x * delta.x + delta.y * delta.y
                guard distanceSquared <= thresholdSquared else { continue }

                let candidate = MirrorMatch(delta: delta, distanceSquared: distanceSquared)
                if bestMatch == nil || candidate.distanceSquared < bestMatch!.distanceSquared {
                    bestMatch = candidate
                }
            }
        }

        return bestMatch
    }

    private static func mirrorGuides(
        movingPositions: [CGPoint],
        otherAthletePositions: [CGPoint],
        threshold: CGFloat = 0.35
    ) -> [FormationMirrorGuideRenderItem] {
        let mirrorAxisX = CourtConstants.width / 2
        let thresholdSquared = threshold * threshold
        var guides: [FormationMirrorGuideRenderItem] = []
        var seenGuides = Set<FormationMirrorGuideRenderItem>()

        for movingPosition in movingPositions {
            for sourcePosition in otherAthletePositions {
                guard abs(sourcePosition.x - mirrorAxisX) > 0.25 else { continue }

                let targetPosition = mirroredPosition(for: sourcePosition)
                let dx = targetPosition.x - movingPosition.x
                let dy = targetPosition.y - movingPosition.y
                guard dx * dx + dy * dy <= thresholdSquared else { continue }

                let guide = FormationMirrorGuideRenderItem(
                    sourcePosition: sourcePosition,
                    mirroredPosition: targetPosition
                )
                if seenGuides.insert(guide).inserted {
                    guides.append(guide)
                    if guides.count >= 4 { return guides }
                }
            }
        }

        return guides
    }

    private static func mirroredPosition(for sourcePosition: CGPoint) -> CGPoint {
        CGPoint(
            x: CourtConstants.width - sourcePosition.x,
            y: sourcePosition.y
        )
    }

    private struct MirrorMatch {
        let delta: CGPoint
        let distanceSquared: CGFloat
    }
}
