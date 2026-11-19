import LocalAuthentication
import SwiftUI

// MARK: - Navigation state

enum VFDTab: String, CaseIterable {
    case home, us, touches, map, chat, settings

    var label: String {
        switch self {
        case .home: return "HOME"
        case .us: return "US"
        case .touches: return "TOUCH"
        case .map: return "MAP"
        case .chat: return "CHAT"
        case .settings: return "SET"
        }
    }

    var icon: [String] {
        switch self {
        case .home: return [".....#.....", "....#.#....", "...#...#...", "..#.....#..", ".#########.", ".#.......#.", ".#..###..#.", ".#..#.#..#.", ".#..#.#..#.", ".####.####."]
        case .us: return [".##.....##.", "#..#...#..#", "#...#.#...#", "#....#....#", "#...#.#...#", ".#..#.#..#.", "..#..#..#..", "...#...#...", "....#.#....", ".....#....."]
        case .touches: return ["...#####...", "..#.....#..", ".#..###..#.", "#..#...#..#", "#..#.#.#..#", "#..#...#..#", ".#..###..#.", "..#.....#..", "...#####...", "..........."]
        case .map: return ["...#####...", "..##...##..", ".##..#..##.", ".##.###.##.", ".##..#..##.", "..##...##..", "...##.##...", "....###....", ".....#.....", "..........."]
        case .chat: return [".#########.", "#.........#", "#.........#", "#..#.#.#..#", "#.........#", "#.........#", ".####.####.", "....#.#....", "...#.......", ".#........."]
        case .settings: return ["....###....", ".#.#####.#.", "..#######..", ".###...###.", "####...####", "####...####", ".###...###.", "..#######..", ".#.#####.#.", "....###...."]
        }
    }
}

/// A screen pushed on top of a tab (with "< BACK").
enum VFDPage: Hashable {
    case stand, themes
}

/// Screens not drawn on the grid yet open in a sheet, in the normal UI.
enum VFDSheet: Identifiable {
    case people, compose, part(String), meanings, map, privateSpace, chat, settings, whatsNew
    var id: String {
        switch self {
        case .part(let p): return "part." + p
        default: return String(describing: self)
        }
    }
}

struct VFDPrompt {
    let title: String
    let placeholder: String
    let action: String
    let done: (String) -> Void
}

struct VFDFlash: Equatable {
    let text: String
    let alarm: Bool
    let id = UUID()
}

@MainActor
final class VFDUI: ObservableObject {
    @Published var tab: VFDTab = .home
    @Published var stack: [VFDPage] = []
    /// Scroll position of each screen, in rows (nil: the screen's default).
    @Published var scrolls: [String: Int] = [:]
    @Published var sheet: VFDSheet?
    @Published var prompt: VFDPrompt?
    @Published var promptText = ""
    @Published var flash: VFDFlash?
    /// Private Space unlocked for the chat (locks again when the app goes to the background).
    @Published var chatUnlocked = false

    /// From the last frame: the tap rectangles, the scrolling content's height and the
    /// rows it shows.
    var hits: [VFDHit] = []
    var contentHeight = 0
    var viewport = 0

    var page: VFDPage? { stack.last }
    var pageKey: String { page.map { "\($0)" } ?? tab.rawValue }

    var maxScroll: Int { max(0, contentHeight - viewport) }
    var scroll: Int { min(scrolls[pageKey] ?? 0, maxScroll) }
    func setScroll(_ v: Int) { scrolls[pageKey] = max(0, min(v, maxScroll)) }

    func select(_ t: VFDTab) {
        if t == tab && stack.isEmpty { setScroll(0) }   // a second tap goes back to the top
        tab = t; stack = []
    }
    func push(_ p: VFDPage) { stack.append(p); scrolls["\(p)"] = 0 }
    func pop() { if !stack.isEmpty { stack.removeLast() } }

    /// A banner at the top for a moment ("TOUCH SENT ♥").
    func say(_ text: String, alarm: Bool = false) {
        let f = VFDFlash(text: text, alarm: alarm)
        flash = f
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.flash == f { self.flash = nil }
        }
    }

    func ask(_ title: String, placeholder: String = "", action: String = "Send", done: @escaping (String) -> Void) {
        promptText = ""
        prompt = VFDPrompt(title: title, placeholder: placeholder, action: action, done: done)
    }
}

// MARK: - The root

/// The app in Amber VFD: one full-screen pixel matrix with its own header and tab bar.
@MainActor
struct VFDRootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @StateObject private var ui = VFDUI()
    @Environment(\.displayScale) private var displayScale
    @AppStorage(ThemeTints.key) private var themeTints = ""
    @State private var dragStart: Int?
    @State private var dragging = false

    private var colors: VFDPalette.Colors { VFDPalette.current(tint: ThemeTints.tint(for: .vfd, in: themeTints)) }

    var body: some View {
        GeometryReader { geo in
            let m = VFDMetrics(size: geo.size, safe: geo.safeAreaInsets, scale: displayScale)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VFDDisplay(buffer: render(m, now: timeline.date), metrics: m, colors: colors)
            }
            .contentShape(Rectangle())
            .gesture(drag(m))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Constellation, \(ui.tab.label.lowercased())")
        }
        .ignoresSafeArea()
        .sheet(item: $ui.sheet) { sheet in
            NavigationStack { sheetView(sheet).screenBackground() }
        }
        .alert(ui.prompt?.title ?? "", isPresented: Binding(get: { ui.prompt != nil }, set: { if !$0 { ui.prompt = nil } }),
               presenting: ui.prompt) { prompt in
            TextField(prompt.placeholder, text: $ui.promptText)
            Button("Cancel", role: .cancel) {}
            Button(prompt.action) {
                let text = ui.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { prompt.done(text) }
            }
        }
        .onAppear { open(model.route) }
        .onChange(of: model.route) { open($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            ui.chatUnlocked = false
        }
        // As in Private Space: a double tap on your own bracelet unlocks the chat.
        .onChange(of: model.braceletDoubleTaps) { _ in
            if ui.tab == .chat, store.hasPrivateSpace { ui.chatUnlocked = true }
        }
    }

    private func render(_ m: VFDMetrics, now: Date) -> VFDBuffer {
        let buffer = VFDBuffer(cols: m.cols, rows: m.rows)
        VFDScreens(model: model, store: store, ui: ui, m: m, b: buffer, now: now).draw()
        ui.hits = buffer.hits
        return buffer
    }

    /// A tap runs the topmost tap rectangle under it; a vertical drag scrolls in whole cells.
    private func drag(_ m: VFDMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !dragging, abs(v.translation.height) > 8 || abs(v.translation.width) > 8 {
                    dragging = true; dragStart = ui.scroll
                }
                if dragging, let start = dragStart {
                    ui.setScroll(start - Int((v.translation.height / m.pitch).rounded()))
                }
            }
            .onEnded { v in
                defer { dragging = false; dragStart = nil }
                guard !dragging else { return }
                let (c, r) = m.cell(at: v.location)
                if let hit = ui.hits.last(where: { $0.contains(c, r) }) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    hit.action()
                }
            }
    }

    /// A tapped notification: the tab (and screen) it's about.
    private func open(_ route: AppRoute?) {
        guard let route else { return }
        switch route {
        case .home: ui.select(.home)
        case .chat: ui.select(.chat)
        case .us(let part):
            ui.select(Feature.us.isOn ? .us : .home)
            if part == "stand" { ui.push(.stand) }
            else if let part { ui.sheet = .part(part) }
        case .bracelet: ui.select(.settings); ui.sheet = .settings
        case .map: ui.select(.map)
        }
        model.route = nil
    }

    @ViewBuilder private func sheetView(_ sheet: VFDSheet) -> some View {
        switch sheet {
        case .people: PeopleView()
        case .compose: ComposeTouchView()
        case .meanings: MeaningsView()
        case .map: MapTabView()
        case .privateSpace: PrivateSpaceView()
        case .chat: ChatView()
        case .settings: SettingsView()
        case .whatsNew: WhatsNewView()
        case .part(let id): Self.part(id)
        }
    }

    /// The parts of Us, by tile id (as on the Us screen).
    @ViewBuilder static func part(_ id: String) -> some View {
        switch id {
        case "language": MeaningsView()
        case "todos": TodoListView()
        case "notes": SharedNotesView()
        case "whiteboard": WhiteboardView()
        case "games": GamesView()
        case "stress": BatteryView()
        case "question": QuestionOfDayView()
        case "jar": AppreciationJarView()
        case "love": LoveLanguageView()
        case "roulette": DateRouletteView()
        case "memories": MemoryLaneView()
        case "agreements": AgreementsView()
        case "repair": RepairView()
        case "stand": WhereWeStandView()
        case "radar": RadarView()
        case "polycal": PolyCalendarView()
        case "metamours": MetamoursView()
        case "dates": SpecialDatesView()
        case "likes": UsProfilesView()
        default: TogetherView()
        }
    }
}

// MARK: - Unlocking the chat

enum VFDUnlock {
    /// Face ID / Touch ID (or the phone's passcode) for Private Space.
    @MainActor static func unlock(_ ui: VFDUI) {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            ui.sheet = .privateSpace
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Private Space") { ok, _ in
            Task { @MainActor in if ok { ui.chatUnlocked = true } }
        }
    }
}
