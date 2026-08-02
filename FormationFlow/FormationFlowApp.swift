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

// MARK: - Editor Theme

enum FormationEditorTheme {
    static let stageBackground = Color(red: 0.055, green: 0.058, blue: 0.064)
    static let stageBackgroundLift = Color(red: 0.095, green: 0.103, blue: 0.112)
    static let glassStroke = Color.white.opacity(0.11)
    static let glassHighlight = Color.white.opacity(0.075)
    static let glassShadow = Color.black.opacity(0.26)

    static let floorPanelLight = Color(red: 0.172, green: 0.178, blue: 0.178)
    static let floorPanelDark = Color(red: 0.126, green: 0.132, blue: 0.136)
    static let floorFineGrid = Color.white.opacity(0.025)
    static let floorGrain = Color.white.opacity(0.055)
    static let floorGroove = Color.black.opacity(0.18)
}

private struct FormationGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let shadowRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay {
                        LinearGradient(
                            colors: [
                                FormationEditorTheme.glassHighlight,
                                Color.white.opacity(0.015),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FormationEditorTheme.glassStroke, lineWidth: 0.8)
            }
            .shadow(
                color: FormationEditorTheme.glassShadow,
                radius: shadowRadius,
                x: 0,
                y: shadowRadius * 0.35
            )
    }
}

extension View {
    func formationGlassPanel(
        cornerRadius: CGFloat = 18,
        material: Material = .ultraThinMaterial,
        shadowRadius: CGFloat = 14
    ) -> some View {
        modifier(FormationGlassPanelModifier(
            cornerRadius: cornerRadius,
            material: material,
            shadowRadius: shadowRadius
        ))
    }
}

// MARK: - First-Launch Onboarding
//
// A six-screen first-launch intro that walks the EXACT app workflow, in order,
// across one coherent routine (empty floor → V → Lines), using the app's REAL
// controls — not mock chrome:
//   01 ADD          — tap the "+ Add" button (auto-spawn), drag to place
//   02 FORMATIONS   — "Duplicate as Next" clones the formation; team rearranges
//   03 INTO/OUT OF  — the pip-badge tab: each formation links both directions
//   04 PATHS        — draw/bend the route, stagger timing, flag collisions
//   05 PREVIEW      — the "Flow / Step" toggle + real play engine
//   06 READY        — it all works offline
// It is a HANDS-ON tour, not a slideshow: screen 01 spawns/drags real athletes,
// 02 + 05 drive the actual `TransitionPlayer`, and 03/05 use the same Into-Out and
// Flow/Step controls as the editor. No fake controls, no pricing — the paywall
// lives in the app, not the intro.
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

/// How a screen's floor behaves. Each mirrors a real app control, not a mockup.
private enum ScreenMode {
    case addPlace      // 01 — real "Add" (+) button spawns athletes; drag to place
    case duplicate     // 02 — "Duplicate as Next" clones the formation; team rearranges
    case inOut         // 03 — "Into / Out of" tab flips which transition is shown
    case paths         // 04 — static formation + paths + waypoints + collision flag
    case flowStep      // 05 — "Flow / Step" preview toggle + real play engine
    case still         // 06 — static formation (closer)
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
    @State private var page = 0

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
        case .addPlace:  AddPlaceDemoFloor(colorIndex: screenIndex)
        case .duplicate: DuplicateDemoFloor(colorIndex: screenIndex)
        case .inOut:     InOutDemoFloor(colorIndex: screenIndex)
        case .paths:     PathsDemoFloor(colorIndex: screenIndex)
        case .flowStep:  FlowStepDemoFloor(colorIndex: screenIndex)
        default:         DemoFloor(spec: spec, colorIndex: screenIndex)
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

// MARK: - Shared floor chrome

/// A small floating pill used for floor hints (matches the real editor's status pills).
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

/// Floor-feet ↔ screen helpers shared by the interactive demo floors.
private struct FloorMetrics {
    let cell: CGFloat
    let yOffset: CGFloat
    init(_ geo: GeometryProxy) {
        cell = geo.size.width / CourtConstants.width
        yOffset = max(0, (geo.size.height - CourtConstants.height * cell) / 2)
    }
    func feet(_ loc: CGPoint) -> CGPoint {
        CGPoint(x: loc.x / cell, y: (loc.y - yOffset) / cell)
    }
}

// MARK: - 01 · Add demo floor (real "Add" button → auto-spawn → drag to place)

private struct AddPlaceDemoFloor: View {
    let colorIndex: Int

    @State private var placed: [RenderedAthlete] = []
    @State private var draggingID: UUID?
    @State private var didDrag = false

    // Roles cycle as you add so the role-shape variety is visible (bases, flyers…).
    private static let roleCycle: [AthleteRole] = [.flyer, .base, .base, .spotter, .tumbler, .backspot]

    var body: some View {
        GeometryReader { geo in
            let m = FloorMetrics(geo)
            let formColor = OB.pageColor(colorIndex)

            ZStack {
                FloorCanvasView(
                    athletes: placed,
                    selectedAthleteIDs: draggingID.map { [$0] } ?? [],
                    cellSize: m.cell,
                    offset: CGPoint(x: 0, y: m.yOffset),
                    hasTransition: false,
                    formationColor: formColor,
                    useRoleColors: false,
                    showCenterMark: false
                )

                // Drag layer — grab the nearest athlete and move it (mirrors the
                // real long-press-drag placement, minus the long press).
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .local)
                            .onChanged { value in
                                let p = m.feet(value.location)
                                if draggingID == nil {
                                    draggingID = nearestID(to: m.feet(value.startLocation))
                                }
                                guard let id = draggingID,
                                      let idx = placed.firstIndex(where: { $0.id == id }) else { return }
                                placed[idx] = placed[idx].moved(to: clamp(p))
                                didDrag = true
                            }
                            .onEnded { _ in
                                if let id = draggingID,
                                   let idx = placed.firstIndex(where: { $0.id == id }) {
                                    placed[idx] = placed[idx].moved(to: placed[idx].position.rounded())
                                }
                                draggingID = nil
                            }
                    )

                // Bottom controls: the REAL "Add" button + a Clear, matching the
                // editor's control strip (Add = plus.circle.fill, prominent).
                VStack(spacing: 10) {
                    Spacer()
                    if placed.isEmpty {
                        floorHint("Tap Add to spawn your first athlete", icon: "plus.circle.fill")
                    } else if !didDrag {
                        floorHint("Now drag anyone to place them", icon: "hand.draw.fill")
                    }
                    HStack(spacing: 10) {
                        Button(action: addAthlete) {
                            Label("Add", systemImage: "plus.circle.fill")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 12).fill(OB.accent))
                                .shadow(color: OB.accent.opacity(0.5), radius: 12, x: 0, y: 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !placed.isEmpty {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { placed.removeAll(); didDrag = false }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(OB.barBorder, lineWidth: 1))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear all")
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func addAthlete() {
        let i = placed.count
        let role = Self.roleCycle[i % Self.roleCycle.count]
        let athlete = RenderedAthlete(
            id: UUID(),
            label: "A\(i + 1)",
            role: role,
            position: FormationTemplates.defaultSpawnPosition(for: i)
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { placed.append(athlete) }
    }

    private func nearestID(to feet: CGPoint) -> UUID? {
        placed.min(by: {
            hypot($0.position.x - feet.x, $0.position.y - feet.y)
                < hypot($1.position.x - feet.x, $1.position.y - feet.y)
        })?.id
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 1), CourtConstants.width - 1),
                y: min(max(p.y, 1), CourtConstants.height - 1))
    }
}

private extension CGPoint {
    func rounded() -> CGPoint { CGPoint(x: x.rounded(), y: y.rounded()) }
}

private extension RenderedAthlete {
    func moved(to p: CGPoint) -> RenderedAthlete {
        RenderedAthlete(id: id, label: label, role: role, position: p)
    }
}

// MARK: - 02 · Duplicate demo floor ("Duplicate as Next" → team rearranges)

private struct DuplicateDemoFloor: View {
    let colorIndex: Int
    @StateObject private var player: TransitionPlayer
    @State private var duplicated = false

    init(colorIndex: Int) {
        self.colorIndex = colorIndex
        let demo = OnboardingDemo.shared
        let p = TransitionPlayer(
            startAthletes: demo.athletes(for: .openingV),
            endAthletes: demo.athletes(for: .lines),
            transitionSpec: demo.transitionSpec()
        )
        p.isLooping = false
        p.autoRewindOnIdle = false
        _player = StateObject(wrappedValue: p)
    }

    var body: some View {
        GeometryReader { geo in
            let m = FloorMetrics(geo)
            let formColor = OB.pageColor(colorIndex)
            let nextColor = OB.pageColor(colorIndex + 1)

            ZStack {
                FloorCanvasView(
                    athletes: player.currentAthletes,
                    cellSize: m.cell,
                    offset: CGPoint(x: 0, y: m.yOffset),
                    hasTransition: true,
                    startFormationColor: formColor,
                    endFormationColor: nextColor,
                    transitionProgress: player.progress,
                    formationColor: duplicated ? nextColor : formColor,
                    useRoleColors: false,
                    showCenterMark: false
                )

                // Formation pips (ordered list) — "1" then "1 2" after duplicating.
                VStack {
                    HStack(spacing: 6) {
                        formationPip("1", active: !duplicated)
                        if duplicated {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(OB.txtFaint)
                            formationPip("2", active: true)
                        }
                    }
                    .padding(.top, 12)
                    Spacer()
                }

                // The REAL "Duplicate as Next" action.
                VStack {
                    Spacer()
                    Button(action: duplicate) {
                        Label(duplicated ? "Formation 2 created" : "Duplicate as Next",
                              systemImage: duplicated ? "checkmark.circle.fill" : "plus.square.on.square")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(duplicated ? Color.black.opacity(0.55) : OB.accent))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(duplicated ? OB.barBorder : .clear, lineWidth: 1))
                            .shadow(color: duplicated ? .clear : OB.accent.opacity(0.5), radius: 12, x: 0, y: 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(duplicated)
                }
                .padding(.bottom, 16)
            }
        }
        .onDisappear { player.pause() }
    }

    private func duplicate() {
        withAnimation(.easeInOut(duration: 0.3)) { duplicated = true }
        player.play()
    }

    private func formationPip(_ n: String, active: Bool) -> some View {
        Text(n)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(active ? .white : OB.txtFaint)
            .frame(width: 26, height: 26)
            .background(Circle().fill(active ? OB.accent : Color.black.opacity(0.45)))
            .overlay(Circle().stroke(OB.barBorder, lineWidth: 1))
    }
}

// MARK: - 03 · Into / Out demo floor (each formation links both ways)

// MARK: - 04 · Paths demo floor (drag waypoint handles → live collision flag)

/// Hands-on path editing: the two selected athletes (index 1 & 3) carry
/// draggable waypoint handles, exactly like the real editor. Bend a path into a
/// neighbor's lane and the engine flags the collision in real time.
private struct PathsDemoFloor: View {
    let colorIndex: Int

    // Mutable copy of the V→Lines demo paths so dragged handles persist.
    @State private var paths: [TransitionPathRenderItem] = OnboardingDemo.shared.paths
    @State private var grabbed: GrabbedHandle?
    @State private var didBend = false

    private struct GrabbedHandle { let pathID: UUID; let waypointID: UUID }

    // Athletes 1 & 3 are the ones carrying waypoints (and thus visible handles).
    private static let selected = OnboardingDemo.shared.ids([1, 3])

    var body: some View {
        GeometryReader { geo in
            let m = FloorMetrics(geo)
            let formColor = OB.pageColor(colorIndex)
            let nextColor = OB.pageColor(colorIndex + 1)
            let collisions = PathCalculations.findPathCollisionDetails(
                paths: paths,
                counts: 8,
                detailLevel: .markersOnly
            )

            ZStack {
                FloorCanvasView(
                    athletes: OnboardingDemo.shared.athletes(for: .openingV),
                    selectedAthleteIDs: Self.selected,
                    transitionPaths: paths,
                    collisionIDs: [],
                    pathCollisionIDs: collisions.ids,
                    pathCollisionStartProgresses: collisions.startProgresses,
                    cellSize: m.cell,
                    offset: CGPoint(x: 0, y: m.yOffset),
                    hasTransition: false,
                    startFormationColor: formColor,
                    endFormationColor: nextColor,
                    formationColor: formColor,
                    useRoleColors: false,
                    showCenterMark: false,
                    showPathPulse: false,
                    transitionCounts: 8
                )

                // Handle-drag layer — grab the nearest selected waypoint and bend it.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .local)
                            .onChanged { value in
                                if grabbed == nil {
                                    grabbed = nearestHandle(to: m.feet(value.startLocation))
                                }
                                guard let g = grabbed else { return }
                                moveWaypoint(g, to: clamp(m.feet(value.location)))
                                didBend = true
                            }
                            .onEnded { _ in grabbed = nil }
                    )

                // Adaptive hint: teach the gesture, then name a collision when one fires.
                VStack {
                    Spacer()
                    if !collisions.ids.isEmpty {
                        floorHint("Collision — they'd fight for the same spot", icon: "exclamationmark.triangle.fill")
                    } else if !didBend {
                        floorHint("Drag a handle to bend the path", icon: "hand.draw.fill")
                    }
                }
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.2), value: collisions.ids.isEmpty)
            }
        }
    }

    private func nearestHandle(to feet: CGPoint) -> GrabbedHandle? {
        var best: GrabbedHandle?
        var bestDist: CGFloat = 4   // grab radius in feet
        for path in paths where Self.selected.contains(path.athleteID) {
            for wp in path.waypoints {
                let d = hypot(wp.position.x - feet.x, wp.position.y - feet.y)
                if d < bestDist { bestDist = d; best = GrabbedHandle(pathID: path.athleteID, waypointID: wp.id) }
            }
        }
        return best
    }

    private func moveWaypoint(_ g: GrabbedHandle, to feet: CGPoint) {
        guard let pi = paths.firstIndex(where: { $0.athleteID == g.pathID }) else { return }
        let p = paths[pi]
        let newWaypoints = p.waypoints.map { wp -> PathWaypoint in
            wp.id == g.waypointID
                ? PathWaypoint(id: wp.id, position: feet, isSmooth: wp.isSmooth, holdDuration: wp.holdDuration)
                : wp
        }
        paths[pi] = TransitionPathRenderItem(
            athleteID: p.athleteID,
            startPosition: p.startPosition,
            endPosition: p.endPosition,
            controlPoint: p.controlPoint,
            waypoints: newWaypoints,
            moveDelay: p.moveDelay
        )
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 1), CourtConstants.width - 1),
                y: min(max(p.y, 1), CourtConstants.height - 1))
    }
}

// MARK: - 03 · Into / Out of demo floor ("Into / Out of" tab flips the transition)

private struct InOutDemoFloor: View {
    let colorIndex: Int
    @State private var showingInto = true

    var body: some View {
        GeometryReader { geo in
            let m = FloorMetrics(geo)
            let demo = OnboardingDemo.shared
            let formColor = OB.pageColor(colorIndex)
            let neighborColor = OB.pageColor(colorIndex + (showingInto ? -1 : 1))

            ZStack {
                FloorCanvasView(
                    athletes: demo.athletes(for: .lines),     // formation 2 = the "current" one
                    transitionPaths: showingInto ? demo.intoPaths : demo.outPaths,
                    cellSize: m.cell,
                    offset: CGPoint(x: 0, y: m.yOffset),
                    hasTransition: false,
                    startFormationColor: showingInto ? neighborColor : formColor,
                    endFormationColor: showingInto ? formColor : neighborColor,
                    formationColor: formColor,
                    useRoleColors: false,
                    showCenterMark: false,
                    showPathPulse: true
                )

                // The real FormationPipBadge "Into / Out of" segmented tab.
                VStack {
                    inOutTab.padding(.top, 12)
                    Spacer()
                    floorHint(showingInto ? "Coming in from formation 1"
                                          : "Going out to formation 3",
                              icon: showingInto ? "arrow.down.right" : "arrow.up.right")
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private var inOutTab: some View {
        HStack(spacing: 0) {
            segment("Into", selected: showingInto) { showingInto = true }
            segment("Out of", selected: !showingInto) { showingInto = false }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .overlay(Capsule().stroke(OB.barBorder, lineWidth: 1))
    }

    private func segment(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { action() } }) {
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? .white : OB.txtDim)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(Capsule().fill(selected ? OB.accent : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 05 · Flow / Step demo floor (preview toggle + real play engine)

private struct FlowStepDemoFloor: View {
    let colorIndex: Int
    @StateObject private var player: TransitionPlayer
    @State private var mode: TransitionPreviewMode = .flow

    // The preview routes two athletes head-on so a collision is always visible.
    private let scenario: OnboardingDemo.PreviewScenario

    init(colorIndex: Int) {
        self.colorIndex = colorIndex
        let scn = OnboardingDemo.shared.previewScenario()
        self.scenario = scn
        let p = TransitionPlayer(
            startAthletes: scn.start,
            endAthletes: scn.end,
            transitionSpec: scn.spec
        )
        p.isLooping = true
        p.autoRewindOnIdle = false
        _player = StateObject(wrappedValue: p)
    }

    var body: some View {
        GeometryReader { geo in
            let m = FloorMetrics(geo)
            let formColor = OB.pageColor(colorIndex)
            let nextColor = OB.pageColor(colorIndex + 1)
            let idle = !player.isPlaying
            // Static path warning is always on; live circle-flash fires only when
            // the two crossing athletes actually overlap mid-move.
            let liveCollisions = PathCalculations.collisionSummary(in: player.currentAthletes).ids

            ZStack {
                FloorCanvasView(
                    athletes: player.currentAthletes,
                    transitionPaths: scenario.paths,
                    collisionIDs: liveCollisions,
                    pathCollisionIDs: scenario.collisionIDs,
                    pathCollisionStartProgresses: scenario.collisionStartProgresses,
                    cellSize: m.cell,
                    offset: CGPoint(x: 0, y: m.yOffset),
                    hasTransition: true,
                    startFormationColor: formColor,
                    endFormationColor: nextColor,
                    transitionProgress: player.progress,
                    formationColor: formColor,
                    useRoleColors: false,
                    showCenterMark: false,
                    showPathPulse: idle && mode == .flow,
                    transitionCounts: 8,
                    showCountSteps: idle && mode == .step
                )

                // Top: the real "Flow / Step" preview toggle + a collision flag.
                VStack(spacing: 10) {
                    flowStepTab.padding(.top, 12)
                    if !liveCollisions.isEmpty {
                        floorHint("Collision — two athletes hit here", icon: "exclamationmark.triangle.fill")
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.2), value: liveCollisions.isEmpty)

                // Bottom: the real play/pause engine control.
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
                    .padding(.bottom, 16)
                }
            }
        }
        .onDisappear { player.pause() }
    }

    private var flowStepTab: some View {
        HStack(spacing: 0) {
            ForEach(TransitionPreviewMode.allCases) { m in
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { mode = m } }) {
                    Label(m.label, systemImage: m.systemImage)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(mode == m ? .white : OB.txtDim)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(mode == m ? OB.accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .overlay(Capsule().stroke(OB.barBorder, lineWidth: 1))
    }
}

// MARK: - Bundled demo data (background surface only — never persisted)

final class OnboardingDemo {
    static let shared = OnboardingDemo()

    enum FormationKind { case empty, openingV, lines, pyramid, closer }

    struct Member { let id: UUID; let label: String; let role: AthleteRole }

    let roster: [Member]
    let paths: [TransitionPathRenderItem]
    /// Into = the transition arriving at formation 2 (V → Lines).
    var intoPaths: [TransitionPathRenderItem] { paths }
    /// Out of = the transition leaving formation 2 (Lines → pyramid).
    let outPaths: [TransitionPathRenderItem]

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

        // Out-of paths: the same team leaving Lines for the next formation (pyramid).
        let lines = linePositions
        let pyramid = pyramidPositions
        let members = roster
        outPaths = members.enumerated().map { i, member in
            TransitionPathRenderItem(
                athleteID: member.id,
                startPosition: lines[i],
                endPosition: pyramid[i],
                controlPoint: nil,
                waypoints: [],
                moveDelay: 0
            )
        }
    }

    func athletes(for kind: FormationKind) -> [RenderedAthlete] {
        let positions: [CGPoint]
        switch kind {
        case .empty: return []
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

    // MARK: Screen 05 preview scenario

    /// A bundle the preview screen plays: start/end formations, the per-athlete
    /// paths, a real `TransitionSpec`, and the IDs the engine flags as colliding.
    struct PreviewScenario {
        let start: [RenderedAthlete]
        let end: [RenderedAthlete]
        let paths: [TransitionPathRenderItem]
        let spec: TransitionSpec
        let collisionIDs: Set<UUID>
        let collisionStartProgresses: [UUID: CGFloat]
    }

    /// The V→Lines move, but athletes 5 & 6 are routed head-on through the same
    /// center spot (start/end swapped) so they cross at exactly t=0.5 — a
    /// guaranteed collision the live flag catches during playback. Athlete 1
    /// keeps its staggered (late) entrance. Everyone else runs clean.
    func previewScenario() -> PreviewScenario {
        var starts = vPositions
        var ends = linePositions
        let p = CGPoint(x: 22, y: 33), q = CGPoint(x: 50, y: 33)
        starts[5] = p; ends[5] = q
        starts[6] = q; ends[6] = p

        let start = roster.enumerated().map { i, m in
            RenderedAthlete(id: m.id, label: m.label, role: m.role, position: starts[i])
        }
        let end = roster.enumerated().map { i, m in
            RenderedAthlete(id: m.id, label: m.label, role: m.role, position: ends[i])
        }
        let items: [TransitionPathRenderItem] = roster.enumerated().map { i, m in
            TransitionPathRenderItem(
                athleteID: m.id,
                startPosition: starts[i],
                endPosition: ends[i],
                controlPoint: nil,
                waypoints: i == 1 ? paths[1].waypoints : [],
                moveDelay: i == 1 ? 2 : 0
            )
        }
        let transitions = items.map {
            AthleteTransition(
                athleteID: $0.athleteID,
                moveDelay: $0.moveDelay,
                pathControlPoint: $0.controlPoint,
                pathWaypoints: $0.waypoints
            )
        }
        let spec = TransitionSpec(
            fromFormationID: UUID(),
            toFormationID: UUID(),
            duration: 8,
            athleteTransitions: transitions
        )
        let collisions = PathCalculations.findPathCollisionDetails(
            paths: items,
            counts: 8,
            detailLevel: .markersOnly
        )
        return PreviewScenario(
            start: start,
            end: end,
            paths: items,
            spec: spec,
            collisionIDs: collisions.ids,
            collisionStartProgresses: collisions.startProgresses
        )
    }
}

// MARK: - Page content (comedic, hands-on, no pricing)

private enum OnboardingContent {
    static let pages: [OBPage] = {
        let demo = OnboardingDemo.shared
        return [
            // 01 · ADD — tap the + Add button, then drag to place
            OBPage(
                eyebrow: "ASSEMBLE · 01 / 06",
                title: [TitleRun("Tap "),
                        TitleRun("Add", accent: true),
                        TitleRun(" to summon some humans.")],
                body: "Hit Add and an athlete appears out of nowhere — then drag them wherever you want. " +
                "Each role draws as its own shape, so you can spot a base from a flyer without " +
                "squinting. Best part: in here, they stand exactly where you put them. Wild, we know.",
                side: .right, cta: "Let's build", wide: false,
                formation: .empty, showPaths: false, pulse: false,
                selected: [], grouped: [], mode: .addPlace
            ),
            // 02 · FORMATIONS — Duplicate as Next clones the formation
            OBPage(
                eyebrow: "COPY-PASTE · 02 / 06",
                title: [TitleRun("Clone the whole squad in "),
                        TitleRun("one tap.", accent: true)],
                body: "Tap Duplicate as Next and your entire team is copied into a fresh formation — now " +
                "just slide everyone to their new spots. It's cloning without the lab coat or the " +
                "awkward ethics questions. Stack a few and congratulations: you've got a routine.",
                side: .left, cta: nil, wide: false,
                formation: .lines, showPaths: false, pulse: false,
                selected: [], grouped: [], mode: .duplicate
            ),
            // 03 · INTO / OUT OF — each formation links both directions
            OBPage(
                eyebrow: "INTO / OUT OF · 03 / 06",
                title: [TitleRun("A way in. "),
                        TitleRun("A way out.", accent: true)],
                body: "Every formation has a move coming Into it and a move going Out of it. Flip the tab " +
                "to choreograph either side. Picture a polite entrance and a dramatic exit — and yes, " +
                "both are entirely your fault.",
                side: .right, cta: nil, wide: false,
                formation: .lines, showPaths: true, pulse: true,
                selected: [], grouped: [], mode: .inOut
            ),
            // 04 · PATHS — shape the route, stagger timing, flag collisions
            OBPage(
                eyebrow: "TRAFFIC CONTROL · 04 / 06",
                title: [TitleRun("Bend paths before heads "),
                        TitleRun("collide.", accent: true)],
                body: "Drag a handle to curve an athlete's route around the pile-up. The instant two paths " +
                "fight over the same square foot, the app waves a red flag — so the crash happens " +
                "here, on a screen, instead of live in front of every parent with their phone out.",
                side: .left, cta: nil, wide: false,
                formation: .openingV, showPaths: true, pulse: false,
                selected: demo.ids([1, 3]), grouped: [], mode: .paths
            ),
            // 05 · FLOW / STEP — two ways to preview, real play engine
            OBPage(
                eyebrow: "SHOWTIME · 05 / 06",
                title: [TitleRun("Watch it run — "),
                        TitleRun("Flow or Step.", accent: true)],
                body: "Flow sweeps a smooth comet down every path. Step chops the move into one beat per " +
                "count, like counting it out on the mat. Press play and the real engine runs it at " +
                "real tempo — the late entrance waits its turn, collisions flash red, and it never " +
                "once asks for a water break.",
                side: .right, cta: nil, wide: false,
                formation: .openingV, showPaths: true, pulse: false,
                selected: [], grouped: [], mode: .flowStep
            ),
            // 06 · READY — closing, no price
            OBPage(
                eyebrow: "GO TIME · 06 / 06",
                title: [TitleRun("It all runs "),
                        TitleRun("offline.", accent: true)],
                body: "No account, no Wi-Fi, no spinning wheel of doom — the whole routine lives right on " +
                "this device and runs in a gym with worse signal than a parking garage. The only " +
                "formation missing is the one you haven't built yet. So go.",
                side: .center, cta: "Hit the mat", wide: true,
                formation: .closer, showPaths: false, pulse: false,
                selected: [], grouped: [], mode: .still
            )
        ]
    }()
}

#Preview {
    OnboardingView()
}
