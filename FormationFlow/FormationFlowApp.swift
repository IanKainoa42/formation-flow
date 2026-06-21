import SwiftUI
import UIKit

@main
struct FormationFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var entitlementManager = EntitlementManager()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            RoutineWorkspaceView()
                .environmentObject(entitlementManager)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { hasSeenOnboarding = !$0 }
                )) {
                    OnboardingView()
                }
        }
    }
}

/// Holds the current allowed-orientation mask. The floor editor on iPhone forces
/// landscape (the wide court fills the screen); the rest of the phone app stays
/// portrait. iPad is never constrained — its default mask is `.all`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

/// Drives app-forced rotation. Setting the mask both restricts what the user can
/// rotate to and (via `requestGeometryUpdate`) actively rotates the window to a
/// valid orientation even when the device's rotation lock is on.
enum OrientationLock {
    static func set(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        guard let scene = activeWindowScene() else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
        return scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.first as? UIWindowScene
    }
}

// MARK: - First-Launch Onboarding
//
// A five-screen first-launch intro. It is a HANDS-ON tour, not a slideshow: the
// opening lets you tap the floor to drop athletes (and clear them — the full
// create/delete cycle), and the transitions screen drives the REAL animation
// engine (`TransitionPlayer`) so pressing play actually moves the athletes. No
// fake controls, no pricing — the paywall lives in the app, not the intro.
//
// All code lives here (not a standalone file): `Models.swift`, `FloorGridView`
// and `FormationHomeView` are frozen (see CLAUDE.md). This reuses the public
// `FloorCanvasView` renderer + `TransitionPlayer` without touching a locked file.

// MARK: - Theme

private enum OB {
    static let bg = Color(hex: 0x0A0C0F)
    static let card = Color(hex: 0x101318)
    static let bar = Color(hex: 0x0E1217)
    static let barBorder = Color.white.opacity(0.09)
    static let tile = Color.white.opacity(0.05)
    static let txt = Color(hex: 0xF5F5F7)
    static let txtDim = Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.60)
    static let txtFaint = Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.30)
    static let accent = Color(hex: 0xFF375F)

    /// The floor color for screen `index` — cycles the app's formation palette so
    /// the flow walks every color (one per page). Mirrors how the editor colors a
    /// formation by index; role is conveyed by SHAPE, never by color.
    static func pageColor(_ index: Int) -> Color {
        TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Title model (one italic+accent clause per title)

private struct TitleRun {
    let text: String
    let accent: Bool
    init(_ text: String, accent: Bool = false) {
        self.text = text
        self.accent = accent
    }
}

// MARK: - Page spec

private enum CardSide { case left, right, center }

/// How a screen's floor behaves.
private enum ScreenMode {
    case interactive   // tap to drop athletes, clear to delete (screen 01)
    case realPlay      // real TransitionPlayer animation, real play button (screen 03)
    case still         // static formation (screens 02, 05)
    case paths         // static formation + paths + collision flag (screen 04)
}

private struct OBPage: Identifiable {
    let id = UUID()
    let eyebrow: String
    let title: [TitleRun]
    let body: String
    let side: CardSide
    let cta: String?
    let wide: Bool

    // Floor
    let formation: OnboardingDemo.FormationKind
    let showPaths: Bool
    let pulse: Bool
    let selected: Set<UUID>
    let grouped: [Set<UUID>]
    let mode: ScreenMode
}

// MARK: - Onboarding entry

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var page = Int(ProcessInfo.processInfo.environment["OB_PAGE"] ?? "") ?? 0

    private let pages = OnboardingContent.pages

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.25)) { hasSeenOnboarding = true }
    }

    var body: some View {
        GeometryReader { geo in
            let isPhone = hSize == .compact || geo.size.width < 600
            ZStack {
                OB.bg.ignoresSafeArea()

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, spec in
                        OnboardingScreen(
                            spec: spec,
                            screenIndex: index,
                            isPhone: isPhone,
                            page: page,
                            pageCount: pages.count,
                            advance: { advance() },
                            dismiss: dismiss
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                // Skip — top-trailing, under the wordmark bar.
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip", action: dismiss)
                            .font(.system(.footnote, design: .monospaced).weight(.semibold))
                            .foregroundStyle(OB.txtFaint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.black.opacity(0.28)))
                    }
                    Spacer()
                }
                .padding(.top, isPhone ? 52 : 60)
                .padding(.trailing, 12)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func advance() {
        if page >= pages.count - 1 {
            dismiss()
        } else {
            withAnimation(.easeInOut(duration: 0.35)) { page += 1 }
        }
    }
}

// MARK: - One screen

private struct OnboardingScreen: View {
    let spec: OBPage
    /// Position in the flow — drives the per-page rainbow floor color.
    let screenIndex: Int
    let isPhone: Bool
    let page: Int
    let pageCount: Int
    let advance: () -> Void
    let dismiss: () -> Void

    var body: some View {
        if isPhone { phoneLayout } else { padLayout }
    }

    // The live floor for this screen, chosen by mode.
    @ViewBuilder private var floor: some View {
        switch spec.mode {
        case .interactive: InteractiveDemoFloor(spec: spec, colorIndex: screenIndex)
        case .realPlay:    RealPlayDemoFloor(colorIndex: screenIndex)
        default:           DemoFloor(spec: spec, colorIndex: screenIndex)
        }
    }

    // iPad: hero floor full-bleed, card floats left/right/center.
    private var padLayout: some View {
        ZStack {
            floor
            scrim
            wordmarkBar.allowsHitTesting(false)
            HStack {
                if spec.side != .left { Spacer(minLength: 0) }
                introCard(maxWidth: spec.wide ? 470 : 432)
                if spec.side != .right { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 28)
        }
    }

    // iPhone: wordmark bar, floor sized to the court (no dead gap), copy fills the rest.
    private var phoneLayout: some View {
        GeometryReader { geo in
            let courtH = geo.size.width * CourtConstants.height / CourtConstants.width
            VStack(spacing: 0) {
                phoneWordmarkBar
                floor
                    .frame(height: courtH)
                    .clipped()
                bottomSheet
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Scrim

    private var scrim: some View {
        Group {
            if spec.side == .center {
                RadialGradient(
                    colors: [Color.black.opacity(0.10), Color.black.opacity(0.78)],
                    center: .center, startRadius: 60, endRadius: 620
                )
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.10), Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Wordmark bars (brand only — no fake nav controls)

    private var wordmarkBar: some View {
        VStack {
            wordmark
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(OB.bar.opacity(0.66))
                .overlay(Rectangle().fill(OB.barBorder).frame(height: 1), alignment: .bottom)
            Spacer()
        }
    }

    private var phoneWordmarkBar: some View {
        wordmark
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(OB.bar.opacity(0.72))
            .overlay(Rectangle().fill(OB.barBorder).frame(height: 1), alignment: .bottom)
    }

    private var wordmark: some View {
        Text("FORMATIONFLOW")
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .tracking(2.0)
            .foregroundStyle(OB.txt)
    }

    // MARK: Intro card (iPad)

    private func introCard(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            eyebrowView
            titleView(size: 34)
            bodyView(size: 14.5)
            HStack(alignment: .center) {
                pageDots
                Spacer()
                if let cta = spec.cta { ctaButton(cta) }
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(OB.card.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.6), radius: 40, x: 0, y: 30)
    }

    // MARK: Bottom sheet (iPhone) — fills the space below the court

    private var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(OB.txtFaint).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
            eyebrowView
            titleView(size: 26)
            bodyView(size: 14)
            Spacer(minLength: 8)
            pageDots
            if let cta = spec.cta {
                ctaButton(cta).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(OB.card.opacity(0.96))
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: -10)
    }

    // MARK: Card pieces

    private var eyebrowView: some View {
        Text("• " + spec.eyebrow)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(OB.accent)
    }

    private func titleView(size: CGFloat) -> some View {
        spec.title.reduce(Text("")) { partial, run in
            partial + Text(run.text)
                .font(.system(size: size, weight: .heavy))
                .italic(run.accent)
                .foregroundColor(run.accent ? OB.accent : OB.txt)
        }
        .tracking(-0.9)
        .lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func bodyView(size: CGFloat) -> some View {
        Text(spec.body)
            .font(.system(size: size))
            .foregroundStyle(OB.txtDim)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? OB.accent : Color.white.opacity(0.18))
                    .frame(width: i == page ? 22 : 6, height: 6)
            }
        }
    }

    private func ctaButton(_ text: String) -> some View {
        Button(action: advance) {
            HStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(OB.accent))
            .shadow(color: OB.accent.opacity(0.55), radius: 14, x: 0, y: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Static demo floor (non-interactive)

private struct DemoFloor: View {
    let spec: OBPage
    let colorIndex: Int

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CourtConstants.width
            let yOffset = max(0, (geo.size.height - CourtConstants.height * cell) / 2)
            let formColor = OB.pageColor(colorIndex)
            let nextColor = OB.pageColor(colorIndex + 1)
            FloorCanvasView(
                athletes: OnboardingDemo.shared.athletes(for: spec.formation),
                selectedAthleteIDs: spec.selected,
                groupedAthleteIDSets: spec.grouped,
                transitionPaths: spec.showPaths ? OnboardingDemo.shared.paths : [],
                collisionIDs: [],
                pathCollisionIDs: [],
                cellSize: cell,
                offset: CGPoint(x: 0, y: yOffset),
                hasTransition: false,
                startFormationColor: formColor,
                endFormationColor: nextColor,
                formationColor: formColor,
                useRoleColors: false,
                showCenterMark: false,
                showPathPulse: spec.pulse,
                transitionCounts: 8
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Interactive demo floor (tap to drop, clear to delete)

private struct InteractiveDemoFloor: View {
    let spec: OBPage
    let colorIndex: Int

    @State private var placed: [RenderedAthlete] = []

    // Cycle shapes as the user taps so they see the role-shape variety.
    private static let roleCycle: [AthleteRole] = [.base, .flyer, .spotter, .tumbler, .backspot]

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CourtConstants.width
            let yOffset = max(0, (geo.size.height - CourtConstants.height * cell) / 2)
            let formColor = OB.pageColor(colorIndex)
            let nextColor = OB.pageColor(colorIndex + 1)

            ZStack {
                FloorCanvasView(
                    athletes: OnboardingDemo.shared.athletes(for: spec.formation) + placed,
                    transitionPaths: spec.showPaths ? OnboardingDemo.shared.paths : [],
                    cellSize: cell,
                    offset: CGPoint(x: 0, y: yOffset),
                    hasTransition: false,
                    startFormationColor: formColor,
                    endFormationColor: nextColor,
                    formationColor: formColor,
                    useRoleColors: false,
                    showCenterMark: false,
                    showPathPulse: spec.pulse,
                    transitionCounts: 8
                )

                // Tap layer — drop an athlete at the tapped floor cell.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture(coordinateSpace: .local)
                            .onEnded { value in
                                let fx = value.location.x / cell
                                let fy = (value.location.y - yOffset) / cell
                                guard fx >= 1, fx <= CourtConstants.width - 1,
                                      fy >= 1, fy <= CourtConstants.height - 1 else { return }
                                let role = Self.roleCycle[placed.count % Self.roleCycle.count]
                                let athlete = RenderedAthlete(
                                    id: UUID(),
                                    label: "\(placed.count + 1)",
                                    role: role,
                                    position: CGPoint(x: (fx).rounded(), y: (fy).rounded())
                                )
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    placed.append(athlete)
                                }
                            }
                    )

                // Prompt / clear overlay.
                VStack {
                    Spacer()
                    if placed.isEmpty {
                        floorHint("Tap the floor to drop an athlete", icon: "hand.tap.fill")
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { placed.removeAll() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Clear \(placed.count)")
                            }
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .overlay(Capsule().stroke(OB.barBorder, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func floorHint(_ text: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundStyle(OB.txt)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .overlay(Capsule().stroke(OB.barBorder, lineWidth: 1))
    }
}

// MARK: - Real-play demo floor (drives the actual TransitionPlayer)

private struct RealPlayDemoFloor: View {
    let colorIndex: Int
    @StateObject private var player: TransitionPlayer

    init(colorIndex: Int) {
        self.colorIndex = colorIndex
        let demo = OnboardingDemo.shared
        let p = TransitionPlayer(
            startAthletes: demo.athletes(for: .openingV),
            endAthletes: demo.athletes(for: .lines),
            transitionSpec: demo.transitionSpec()
        )
        p.isLooping = true
        p.autoRewindOnIdle = false
        _player = StateObject(wrappedValue: p)
    }

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CourtConstants.width
            let yOffset = max(0, (geo.size.height - CourtConstants.height * cell) / 2)
            let formColor = OB.pageColor(colorIndex)
            let nextColor = OB.pageColor(colorIndex + 1)

            ZStack {
                FloorCanvasView(
                    athletes: player.currentAthletes,
                    transitionPaths: OnboardingDemo.shared.paths,
                    cellSize: cell,
                    offset: CGPoint(x: 0, y: yOffset),
                    hasTransition: true,
                    startFormationColor: formColor,
                    endFormationColor: nextColor,
                    transitionProgress: player.progress,
                    formationColor: formColor,
                    useRoleColors: false,
                    showCenterMark: false,
                    transitionCounts: 8
                )

                // One REAL control — play/pause the actual engine.
                VStack {
                    Spacer()
                    Button {
                        if player.isPlaying { player.pause() } else { player.play() }
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(OB.accent))
                            .shadow(color: OB.accent.opacity(0.5), radius: 14, x: 0, y: 6)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                }
                .padding(.bottom, 16)
            }
        }
        .onDisappear { player.pause() }
    }
}

// MARK: - Bundled demo data (background surface only — never persisted)

final class OnboardingDemo {
    static let shared = OnboardingDemo()

    enum FormationKind { case openingV, lines, pyramid, closer }

    struct Member { let id: UUID; let label: String; let role: AthleteRole }

    let roster: [Member]
    let paths: [TransitionPathRenderItem]

    private let vPositions: [CGPoint]
    private let linePositions: [CGPoint]
    private let pyramidPositions: [CGPoint]
    private let closerPositions: [CGPoint]

    private init() {
        let roles: [AthleteRole] = [
            .flyer, .base, .base, .base, .base,
            .spotter, .spotter, .tumbler, .tumbler, .backspot
        ]
        roster = (0..<10).map { i in
            Member(id: UUID(), label: "A\(i + 1)", role: roles[i])
        }

        vPositions = [
            CGPoint(x: 36, y: 14),
            CGPoint(x: 29, y: 21), CGPoint(x: 43, y: 21),
            CGPoint(x: 23, y: 29), CGPoint(x: 49, y: 29),
            CGPoint(x: 17, y: 37), CGPoint(x: 55, y: 37),
            CGPoint(x: 12, y: 45), CGPoint(x: 60, y: 45),
            CGPoint(x: 36, y: 30)
        ]
        linePositions = [
            CGPoint(x: 12, y: 23), CGPoint(x: 27, y: 23), CGPoint(x: 36, y: 23),
            CGPoint(x: 45, y: 23), CGPoint(x: 60, y: 23),
            CGPoint(x: 12, y: 39), CGPoint(x: 27, y: 39), CGPoint(x: 36, y: 39),
            CGPoint(x: 45, y: 39), CGPoint(x: 60, y: 39)
        ]
        pyramidPositions = [
            CGPoint(x: 36, y: 18),
            CGPoint(x: 28, y: 28), CGPoint(x: 44, y: 28),
            CGPoint(x: 20, y: 38), CGPoint(x: 36, y: 38), CGPoint(x: 52, y: 38),
            CGPoint(x: 14, y: 46), CGPoint(x: 28, y: 46), CGPoint(x: 44, y: 46),
            CGPoint(x: 58, y: 46)
        ]
        closerPositions = (0..<10).map { i in
            CGPoint(x: 10 + CGFloat(i) * 6, y: 28 + CGFloat(i % 2) * 8)
        }

        // V → Lines transition paths. A couple bend through a smooth waypoint;
        // one carries a move delay (a staggered entrance).
        var built: [TransitionPathRenderItem] = []
        for (i, member) in roster.enumerated() {
            let start = vPositions[i]
            let end = linePositions[i]
            var waypoints: [PathWaypoint] = []
            var delay: CGFloat = 0
            if i == 1 {
                waypoints = [PathWaypoint(position: CGPoint(x: (start.x + end.x) / 2 - 5,
                                                            y: (start.y + end.y) / 2 - 4),
                                          isSmooth: true)]
                delay = 2
            } else if i == 3 {
                waypoints = [PathWaypoint(position: CGPoint(x: (start.x + end.x) / 2 + 4,
                                                            y: (start.y + end.y) / 2 + 3),
                                          isSmooth: true)]
            }
            built.append(TransitionPathRenderItem(
                athleteID: member.id,
                startPosition: start,
                endPosition: end,
                controlPoint: nil,
                waypoints: waypoints,
                moveDelay: delay
            ))
        }
        paths = built
    }

    func athletes(for kind: FormationKind) -> [RenderedAthlete] {
        let positions: [CGPoint]
        switch kind {
        case .openingV: positions = vPositions
        case .lines: positions = linePositions
        case .pyramid: positions = pyramidPositions
        case .closer: positions = closerPositions
        }
        return roster.enumerated().map { i, m in
            RenderedAthlete(id: m.id, label: m.label, role: m.role, position: positions[i])
        }
    }

    /// A real `TransitionSpec` (V → Lines) so the player animates the demo paths.
    func transitionSpec() -> TransitionSpec {
        let transitions = paths.map { path in
            AthleteTransition(
                athleteID: path.athleteID,
                moveDelay: path.moveDelay,
                pathControlPoint: path.controlPoint,
                pathWaypoints: path.waypoints
            )
        }
        return TransitionSpec(
            fromFormationID: UUID(),
            toFormationID: UUID(),
            duration: 8,
            athleteTransitions: transitions
        )
    }

    func id(_ index: Int) -> UUID { roster[index].id }
    func ids(_ indices: [Int]) -> Set<UUID> { Set(indices.map { roster[$0].id }) }
}

// MARK: - Page content (comedic, hands-on, no pricing)

private enum OnboardingContent {
    static let pages: [OBPage] = {
        let demo = OnboardingDemo.shared
        return [
            // 01 · Welcome — interactive, ambient pulse
            OBPage(
                eyebrow: "WELCOME · 01 / 05",
                title: [TitleRun("Your whole team will "),
                        TitleRun("never", accent: true),
                        TitleRun(" be at practice on time.")],
                body: "It's fine. Build the whole routine without them — tap the floor to drop an athlete, stack the masterpiece they'll fail to show up for, then wipe it and start again.",
                side: .right, cta: "Get started", wide: false,
                formation: .openingV, showPaths: true, pulse: true,
                selected: [], grouped: [], mode: .interactive
            ),
            // 02 · Roles = shapes — different formation
            OBPage(
                eyebrow: "ROSTER · 02 / 05",
                title: [TitleRun("Every role is its "),
                        TitleRun("own shape.", accent: true)],
                body: "Bases, flyers, spotters, backspots, tumblers — each role draws as a different shape on the floor, so you read a sixteen-person pyramid at a glance instead of squinting at identical dots.",
                side: .left, cta: nil, wide: false,
                formation: .pyramid, showPaths: false, pulse: false,
                selected: [], grouped: [], mode: .still
            ),
            // 03 · Transitions — REAL play
            OBPage(
                eyebrow: "TRANSITIONS · 03 / 05",
                title: [TitleRun("Press play. They "),
                        TitleRun("actually move.", accent: true)],
                body: "This is the real engine, not a video. Hit play and watch the team walk the transition between two formations in real time — so the traffic jam happens on screen, not on the mat.",
                side: .left, cta: nil, wide: false,
                formation: .openingV, showPaths: true, pulse: false,
                selected: [], grouped: [], mode: .realPlay
            ),
            // 04 · Paths & collisions
            OBPage(
                eyebrow: "PATHS · 04 / 05",
                title: [TitleRun("Two athletes, one spot, "),
                        TitleRun("zero collisions.", accent: true)],
                body: "Bend a path around a pile-up, stagger who leaves when, and let the app flag the crossings for you — before someone's elbow finds someone's face.",
                side: .right, cta: nil, wide: false,
                formation: .openingV, showPaths: true, pulse: false,
                selected: demo.ids([1, 3]), grouped: [], mode: .paths
            ),
            // 05 · Closing — no price
            OBPage(
                eyebrow: "READY · 05 / 05",
                title: [TitleRun("It all works "),
                        TitleRun("offline.", accent: true)],
                body: "No account, no Wi-Fi, no waiting — the whole routine lives on this device and runs courtside with zero bars. The only thing missing is the one you haven't built yet.",
                side: .center, cta: "Let's go", wide: true,
                formation: .closer, showPaths: false, pulse: false,
                selected: [], grouped: [], mode: .still
            )
        ]
    }()
}

#Preview {
    OnboardingView()
}
