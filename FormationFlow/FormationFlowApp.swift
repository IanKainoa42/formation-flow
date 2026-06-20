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
// A six-screen first-launch intro recreated from the design handoff
// (`design_handoff_formationflow_onboarding/`). Each screen layers a floating
// marketing card over a live, dimmed `FloorCanvasView` driven by a bundled demo
// `Routine`. iPad floats the card left/right over the hero floor; iPhone puts
// the court up top and the copy in a bottom sheet.
//
// New view file by design — `Models.swift`, `FloorGridView.swift`, and
// `FormationHomeView.swift` are frozen (see CLAUDE.md). This reuses the public
// `FloorCanvasView` renderer + the `RenderedAthlete` / `TransitionPathRenderItem`
// interface without touching any locked file.

// MARK: - Theme

private enum OB {
    // Surface / chrome (dark "courtside")
    static let bg = Color(hex: 0x0A0C0F)
    static let card = Color(hex: 0x101318)
    static let bar = Color(hex: 0x0E1217)
    static let barBorder = Color.white.opacity(0.09)
    static let tile = Color.white.opacity(0.05)
    static let txt = Color(hex: 0xF5F5F7)
    static let txtDim = Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.60)
    static let txtFaint = Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.30)

    // Accent — delivered curated mix ships on pink (#FF375F).
    static let accent = Color(hex: 0xFF375F)
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
private enum PulseMode { case none, flow, steps }

private struct OBPage: Identifiable {
    let id = UUID()
    let eyebrow: String
    let title: [TitleRun]
    let body: String
    let side: CardSide
    let cta: String?
    let wide: Bool

    // Surface
    let formation: OnboardingDemo.FormationKind
    let showPaths: Bool
    let pulse: PulseMode
    let selected: Set<UUID>
    let grouped: [Set<UUID>]

    // Chrome
    let barTitle: String
    let strip: [StripItem]
    let stripSelected: Int?
    let actionRow: ActionRow
    let transport: TransportMode
    let pill: String?
    let showPro: Bool
    let showMoveDelay: Bool
}

private struct StripItem { let name: String; let kind: OnboardingDemo.FormationKind }
private enum ActionRow { case none, roster, paths }
private enum TransportMode { case none, flow, steps }

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

                // Skip — sits just under the top bar so it clears the decorative
                // bar icons (the back chevron / arrow / ••• are non-interactive).
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
                .padding(.top, isPhone ? 54 : 64)
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
    let isPhone: Bool
    let page: Int
    let pageCount: Int
    let advance: () -> Void
    let dismiss: () -> Void

    var body: some View {
        if isPhone {
            phoneLayout
        } else {
            padLayout
        }
    }

    // iPad: hero floor, card floats left/right/center, chrome overlaid.
    private var padLayout: some View {
        ZStack {
            DemoFloor(spec: spec)
            scrim
            chromeOverlay
            HStack {
                if spec.side != .left { Spacer(minLength: 0) }
                introCard(maxWidth: spec.wide ? 470 : 432)
                if spec.side != .right { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 28)
        }
    }

    // iPhone: court up top, copy as a bottom sheet.
    private var phoneLayout: some View {
        GeometryReader { geo in
            let courtH = min(geo.size.height * 0.40, geo.size.width * 56 / 72)
            ZStack(alignment: .top) {
                OB.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    phoneTopBar
                    ZStack {
                        DemoFloor(spec: spec)
                            .frame(height: courtH)
                            .clipped()
                        VStack {
                            HStack { phoneActionOverlay; Spacer() }
                            Spacer()
                        }
                        .padding(8)
                    }
                    .frame(height: courtH)
                    Spacer(minLength: 0)
                }
                VStack {
                    Spacer()
                    bottomSheet
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    // MARK: Scrim

    private var scrim: some View {
        Group {
            if spec.showPro || spec.side == .center {
                RadialGradient(
                    colors: [Color.black.opacity(0.10), Color.black.opacity(0.78)],
                    center: .center, startRadius: 60, endRadius: 620
                )
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.12), Color.black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Chrome (iPad)

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            padTopBar
            // Left-aligned action row / collision badge / multi-select pill.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    if spec.actionRow == .roster { rosterActionRow }
                    if spec.actionRow == .paths { pathsActionRow }
                    if let pill = spec.pill { selectPill(pill) }
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            Spacer()
            // Bottom: transport (03/04) or thumbnail strip (01/02/05/06).
            if spec.transport != .none {
                HStack { transportBar; Spacer() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else if !spec.strip.isEmpty {
                HStack { thumbnailStrip; Spacer() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .allowsHitTesting(false)
    }

    private var padTopBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text("Saved Formations")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OB.accent)

            iconTile("arrow.uturn.backward", accent: false)
            Text(spec.barTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(OB.txt)
            Spacer()
            wordmark
            Spacer()
            circleIcon("arrow.right")
            circleIcon("ellipsis")
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(OB.bar.opacity(0.72))
        .overlay(Rectangle().fill(OB.barBorder).frame(height: 1), alignment: .bottom)
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5)
                .fill(OB.accent)
                .frame(width: 18, height: 18)
                .overlay(Image(systemName: "scribble.variable").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
            Text("FORMATIONFLOW")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(OB.txt)
        }
    }

    // MARK: Chrome (iPhone)

    private var phoneTopBar: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Saved")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OB.accent)
            Spacer()
            Text(spec.barTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(OB.txt)
            Spacer()
            circleIcon("ellipsis")
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(OB.bar.opacity(0.72))
        .overlay(Rectangle().fill(OB.barBorder).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder private var phoneActionOverlay: some View {
        if let pill = spec.pill {
            selectPill(pill)
        } else if spec.actionRow == .paths {
            collisionBadge
        }
    }

    // MARK: Action rows

    private var rosterActionRow: some View {
        HStack(spacing: 8) {
            iconTile("plus", accent: true)
            iconTile("list.bullet", accent: false)
            iconTile("note.text", accent: false)
        }
    }

    private var pathsActionRow: some View {
        HStack(spacing: 8) {
            collisionBadge
            iconTile("eye", accent: true)
        }
    }

    private var collisionBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("1 · path")
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundStyle(OB.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(OB.accent.opacity(0.14)))
        .overlay(Capsule().stroke(OB.accent.opacity(0.5), lineWidth: 1))
    }

    private func selectPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(hex: 0x4DA3FF))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(hex: 0x4DA3FF).opacity(0.14)))
            .overlay(Capsule().stroke(Color(hex: 0x4DA3FF).opacity(0.5), lineWidth: 1))
    }

    // MARK: Transport

    private var transportBar: some View {
        HStack(spacing: 12) {
            // Flow | Steps segmented
            HStack(spacing: 0) {
                segment("FLOW", on: spec.transport == .flow)
                segment("STEPS", on: spec.transport == .steps)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(OB.tile))

            HStack(spacing: 8) {
                Image(systemName: "backward.end.fill").foregroundStyle(OB.txtDim)
                Image(systemName: spec.pulse == .flow ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(OB.accent))
                Image(systemName: "forward.end.fill").foregroundStyle(OB.txtDim)
            }
            .font(.system(size: 13, weight: .bold))

            Text("3.4").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(OB.txt)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 3)
                Capsule().fill(OB.accent).frame(width: 150, height: 3)
                Circle().fill(.white).frame(width: 11, height: 11).offset(x: 150)
            }
            .frame(width: 200)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(OB.bar.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OB.barBorder, lineWidth: 1))
    }

    private func segment(_ label: String, on: Bool) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(on ? .white : OB.txtDim)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? OB.accent : .clear))
    }

    // MARK: Thumbnail strip

    private var thumbnailStrip: some View {
        HStack(spacing: 10) {
            ForEach(Array(spec.strip.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 5) {
                    DemoFloor.thumbnail(kind: item.kind, index: index)
                        .frame(width: 50, height: 38)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.4)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(spec.stripSelected == index ? stripColor(index) : OB.barBorder,
                                        lineWidth: spec.stripSelected == index ? 2 : 1)
                        )
                    Text(item.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(spec.stripSelected == index ? OB.txt : OB.txtDim)
                        .frame(width: 50)
                }
            }
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .foregroundStyle(OB.txtFaint)
                    .frame(width: 50, height: 38)
                    .overlay(Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(OB.txtDim))
                Text("Add").font(.system(size: 11, weight: .medium)).foregroundStyle(OB.txtDim)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(OB.bar.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(OB.barBorder, lineWidth: 1))
    }

    private func stripColor(_ index: Int) -> Color {
        [OB.accent, Color(hex: 0xFF9F0A), Color(hex: 0xFFD60A),
         Color(hex: 0x30D158), Color(hex: 0x0A84FF), Color(hex: 0xBF5AF2)][index % 6]
    }

    // MARK: Intro card

    private func introCard(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            cardContent
        }
        .padding(32)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(OB.card.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.6), radius: 40, x: 0, y: 30)
    }

    @ViewBuilder private var cardContent: some View {
        eyebrowView
        titleView(size: 34)
        bodyView(size: 14.5)
        if spec.showMoveDelay { moveDelayControl }
        if spec.showPro { proList }
        HStack(alignment: .center) {
            pageDots
            Spacer()
            if let cta = spec.cta { ctaButton(cta) }
        }
        .padding(.top, 4)
    }

    private var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(OB.txtFaint).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
            eyebrowView
            titleView(size: 25)
            bodyView(size: 13.5)
            if spec.showMoveDelay { moveDelayControl }
            if spec.showPro { proList }
            pageDots
            if let cta = spec.cta {
                ctaButton(cta).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 34)
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
        Button(action: spec.cta == "Get started" ? advance : dismiss) {
            HStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                if text == "Get started" {
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .frame(maxWidth: spec.showPro ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 12).fill(OB.accent))
            .shadow(color: OB.accent.opacity(0.55), radius: 14, x: 0, y: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(true)
    }

    // MARK: Move-delay control (screen 04)

    private var moveDelayControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MOVE DELAY")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(OB.txtDim)
                Spacer()
                Text("·2 ct")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(OB.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                    Capsule().fill(OB.accent).frame(width: geo.size.width * 0.28, height: 4)
                    Circle().fill(.white).frame(width: 13, height: 13)
                        .offset(x: geo.size.width * 0.28 - 6)
                }
            }
            .frame(height: 14)
            HStack(spacing: 8) {
                delayPill("Smooth", style: .on)
                delayPill("Sharp", style: .off)
                delayPill("+ Waypoint", style: .accent)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(OB.barBorder, lineWidth: 1))
    }

    private enum PillStyle { case on, off, accent }
    private func delayPill(_ text: String, style: PillStyle) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(style == .off ? OB.txtDim : .white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(maxWidth: style == .accent ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(style == .accent ? OB.accent : (style == .on ? OB.tile : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(style == .off ? OB.barBorder : .clear, lineWidth: 1)
            )
    }

    // MARK: Pro list (screen 06)

    private var proList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("FORMATIONFLOW\nPRO")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(OB.accent)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("$4.99").font(.system(size: 17, weight: .bold)).foregroundStyle(OB.txt)
                    Text("once").font(.system(size: 12)).foregroundStyle(OB.txtDim)
                }
            }
            .padding(.bottom, 12)
            proRow("Unlimited formations", "Free caps at 2")
            proRow("Every athlete role", "Free is base only")
            proRow("Full-routine playback", "Scrub end to end")
            proRow("Waypoints & timing", "Bend + stagger paths", last: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OB.barBorder, lineWidth: 1))
    }

    private func proRow(_ title: String, _ sub: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OB.accent)
                    .padding(.top, 2)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(OB.txt)
                Spacer()
                Text(sub).font(.system(size: 12)).foregroundStyle(OB.txtDim)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 9)
            if !last { Divider().overlay(OB.barBorder) }
        }
    }

    // MARK: Small chrome atoms

    private func iconTile(_ name: String, accent: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(accent ? .white : OB.txtDim)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(accent ? OB.accent : OB.tile))
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OB.accent)
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(OB.accent.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Demo floor (live, non-interactive FloorCanvasView)

private struct DemoFloor: View {
    let spec: OBPage

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CourtConstants.width
            let courtH = CourtConstants.height * cell
            let yOffset = max(0, (geo.size.height - courtH) / 2)
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
                startFormationColor: OB.accent,
                endFormationColor: Color(hex: 0x0A84FF),
                formationColor: OB.accent,
                useRoleColors: true,
                showPathPulse: spec.pulse == .flow,
                transitionCounts: 8,
                showCountSteps: spec.pulse == .steps
            )
        }
        .allowsHitTesting(false)
    }

    /// A tiny static court used in the bottom thumbnail strip.
    static func thumbnail(kind: OnboardingDemo.FormationKind, index: Int) -> some View {
        GeometryReader { geo in
            let cell = geo.size.width / CourtConstants.width
            let yOffset = max(0, (geo.size.height - CourtConstants.height * cell) / 2)
            FloorCanvasView(
                athletes: OnboardingDemo.shared.athletes(for: kind),
                cellSize: cell,
                offset: CGPoint(x: 0, y: yOffset),
                formationColor: TransitionEndpointMarkerRenderItem.rainbowColor(forIndex: index),
                useRoleColors: false
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Bundled demo routine (background surface only)

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
        // one carries a move delay (the "·2 ct" stagger shown on screen 04).
        var built: [TransitionPathRenderItem] = []
        for (i, member) in roster.enumerated() {
            let start = vPositions[i]
            let end = linePositions[i]
            var waypoints: [PathWaypoint] = []
            var delay: CGFloat = 0
            if i == 1 { // A2 — bends + staggers
                waypoints = [PathWaypoint(position: CGPoint(x: (start.x + end.x) / 2 - 5,
                                                            y: (start.y + end.y) / 2 - 4),
                                          isSmooth: true)]
                delay = 2
            } else if i == 3 { // A4 — bends
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

    // Convenience id lookups for selection sets.
    func id(_ index: Int) -> UUID { roster[index].id }
    func ids(_ indices: [Int]) -> Set<UUID> { Set(indices.map { roster[$0].id }) }
}

// MARK: - Page content (delivered curated voice mix 01-A·02-B·03-A·04-A·05-B·06-A)

private enum OnboardingContent {
    static let pages: [OBPage] = {
        let demo = OnboardingDemo.shared
        let strip3 = [
            StripItem(name: "Opening V", kind: .openingV),
            StripItem(name: "Lines", kind: .lines),
            StripItem(name: "Pyramid", kind: .pyramid)
        ]
        let strip4 = strip3 + [StripItem(name: "Closer", kind: .closer)]

        return [
            // 01 · Welcome (A)
            OBPage(
                eyebrow: "WELCOME · 01 / 06",
                title: [TitleRun("Your full team shows up "),
                        TitleRun("the day before", accent: true),
                        TitleRun(" competition.")],
                body: "Cool. Plan the entire routine here instead — place every athlete, map every transition, press play. The mat is for cleaning it up, not figuring it out.",
                side: .right, cta: "Get started", wide: false,
                formation: .openingV, showPaths: false, pulse: .none,
                selected: [], grouped: [],
                barTitle: "Opening V", strip: strip3, stripSelected: 0,
                actionRow: .none, transport: .none, pill: nil, showPro: false, showMoveDelay: false
            ),
            // 02 · Roster (B)
            OBPage(
                eyebrow: "ROSTER · 02 / 06",
                title: [TitleRun("Assign roles. Avoid "),
                        TitleRun("reunions mid-mat.", accent: true)],
                body: "Build your roster once and drop athletes onto a scaled floor. Each role gets its own color, so you're never squinting at sixteen identical dots wondering which one is the flyer.",
                side: .left, cta: nil, wide: false,
                formation: .openingV, showPaths: false, pulse: .none,
                selected: demo.ids([0]), grouped: [],
                barTitle: "Opening V", strip: strip3, stripSelected: 0,
                actionRow: .roster, transport: .none, pill: nil, showPro: false, showMoveDelay: false
            ),
            // 03 · Transitions (A, Flow)
            OBPage(
                eyebrow: "TRANSITIONS · 03 / 06",
                title: [TitleRun("Press play. Watch the chaos "),
                        TitleRun("resolve itself.", accent: true)],
                body: "Animate the move between any two formations in real time. Flow mode pulses the paths; Steps mode counts out the footwork. Either way you see it before they walk it.",
                side: .left, cta: nil, wide: false,
                formation: .openingV, showPaths: true, pulse: .flow,
                selected: [], grouped: [],
                barTitle: "V → Lines", strip: [], stripSelected: nil,
                actionRow: .none, transport: .flow, pill: nil, showPro: false, showMoveDelay: false
            ),
            // 04 · Paths (A, Steps)
            OBPage(
                eyebrow: "PATHS · 04 / 06",
                title: [TitleRun("Two athletes, one spot, "),
                        TitleRun("zero collisions.", accent: true)],
                body: "Bend any path with waypoints — smooth or sharp — and stagger entrances with a move delay measured in 8-counts. The app flags crossings before they become a pile-up.",
                side: .right, cta: nil, wide: false,
                formation: .openingV, showPaths: true, pulse: .steps,
                selected: demo.ids([1, 3]), grouped: [],
                barTitle: "V → Lines", strip: [], stripSelected: nil,
                actionRow: .paths, transport: .steps, pill: nil, showPro: false, showMoveDelay: true
            ),
            // 05 · Routine (B)
            OBPage(
                eyebrow: "ROUTINE · 05 / 06",
                title: [TitleRun("One routine. Every formation. "),
                        TitleRun("Scrubbable.", accent: true)],
                body: "Link formations into a sequence and preview the whole thing front to back. Grab a stunt group and move all four at once — your thumbs will thank you.",
                side: .right, cta: nil, wide: false,
                formation: .lines, showPaths: false, pulse: .none,
                selected: demo.ids([5, 6, 7, 8]), grouped: [demo.ids([5, 6, 7, 8])],
                barTitle: "Lines", strip: strip4, stripSelected: 1,
                actionRow: .none, transport: .none,
                pill: "4 selected · stunt group", showPro: false, showMoveDelay: false
            ),
            // 06 · Ready / Pro (A)
            OBPage(
                eyebrow: "READY · 06 / 06",
                title: [TitleRun("No team, no signal, "),
                        TitleRun("no excuses.", accent: true)],
                body: "Everything lives on your device — works on the mat with zero bars, stays private, no account. Go Pro for unlimited formations, every role, and full-routine playback. Four hours a week. Don't spend them on a transition you could've solved at home.",
                side: .center, cta: "now let your imagination be.", wide: true,
                formation: .openingV, showPaths: false, pulse: .none,
                selected: [], grouped: [],
                barTitle: "Opening V", strip: [], stripSelected: nil,
                actionRow: .none, transport: .none, pill: nil, showPro: true, showMoveDelay: false
            )
        ]
    }()
}

#Preview {
    OnboardingView()
}
