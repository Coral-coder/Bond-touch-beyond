import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @EnvironmentObject var recovery: FirmwareRecovery
    @State private var tab: AppTab = {
        switch AppModel.demoArgument("-demoTab") {
        case "us": return .us
        case "touches": return .touches
        case "chat": return .chat
        case "map": return .map
        case "settings": return .settings
        default: return .home
        }
    }()
    /// The theme (Settings → Theme). Every screen reads its colours from `Theme`, so a change
    /// rebuilds the whole tree.
    @AppStorage("appStyle") private var appStyle = AppStyle.aero.rawValue
    @AppStorage("paperInk") private var paperInk = PaperInk.aqua.rawValue
    @AppStorage(ThemeTints.key) private var themeTints = ""
    @State private var keyboardUp = false
    @State private var showWhatsNew = false
    /// The feature tour has been seen (or skipped); until then it opens once the profile is set
    /// up, after What's new is closed.
    @AppStorage(FeatureTour.seenKey) private var walkthroughSeen = false

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .modifier(ThemeFonts())
        .id(appStyle + paperInk + themeTints)
        .overlay(alignment: .top) { RecoveryBanner().padding(.top, 60) }
        .overlay(alignment: .top) { BraceletPromptBanner().padding(.top, 60) }
        // A heartbeat arriving (or replayed): the live EKG, over whatever screen is open.
        .overlay(alignment: .top) {
            if let show = model.heartbeatShow {
                HeartbeatOverlay(show: show) { model.dismissHeartbeat() }
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.heartbeatShow)
        .confirmationDialog("Which bracelet is this firmware for?",
                            isPresented: Binding(get: { recovery.pendingImport != nil },
                                                 set: { if !$0 { recovery.pendingImport = nil } }),
                            titleVisibility: .visible) {
            ForEach(BraceletModel.allCases) { m in
                Button(m.title) {
                    if let url = recovery.pendingImport {
                        do { try recovery.importFirmware(from: url, model: m) }
                        catch { recovery.importError = "That file isn't a bracelet firmware package." }
                    }
                    recovery.pendingImport = nil
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { store.profile.isComplete && !walkthroughSeen && !showWhatsNew && !AppModel.isDemo },
                                              set: { if !$0 { walkthroughSeen = true } })) {
            FeatureTour { walkthroughSeen = true }
        }
        .preferredColorScheme(Theme.colorScheme)
        .tint(Theme.accent)
        .onAppear { if WhatsNew.check(existingUser: store.profile.isComplete) { showWhatsNew = true } }
        .sheet(isPresented: $showWhatsNew) {
            NavigationStack {
                WhatsNewView().screenBackground()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showWhatsNew = false } } }
            }
        }
    }

    @ViewBuilder private var content: some View {
        // The original app gates on a complete profile, not on having a partner — the
        // dashboard is shown either way (it offers "Add a partner" when there is none).
        if !store.profile.isComplete {
            OnboardingView()
        } else {
            ZStack(alignment: .bottom) {
                Group {
                    if AppModel.isDemo, let screen = AppModel.demoArgument("-demoScreen") {
                        DemoScreen(name: screen)
                    } else {
                        switch tab {
                        case .home: HomeRouter()
                        case .us: NavigationStack { TogetherView().screenBackground() }
                        case .touches: MeaningsView()
                        case .map: MapTabView()
                        // Chat lives inside Private Space, behind its lock, as the original.
                        case .chat: NavigationStack { PrivateSpaceView() }
                        case .settings: NavigationStack { SettingsView() }
                        }
                    }
                }
                // Every scroll view, list and form below gets an empty gap at the end of
                // its content, so the last row always scrolls up clear of the bar.
                .tabBarScrollGap()
                if !keyboardUp {
                    FloatingTabBar(selection: $tab).padding(.bottom, 6)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardUp = false
            }
        }
    }
}

/// One screen opened straight away in demo mode (`-demoScreen <name>`), for screenshots.
private struct DemoScreen: View {
    let name: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                switch name {
                case "chess": ChessView()
                case "battleship": BattleshipView()
                case "jar": AppreciationJarView()
                case "love": LoveLanguageView()
                case "roulette": DateRouletteView()
                case "question": QuestionOfDayView()
                case "agreements": AgreementsView()
                case "repair": RepairView()
                case "memories": MemoryLaneView()
                case "polycal": PolyCalendarView()
                case "metamours": MetamoursView()
                case "story": StoryTogetherView()
                case "wavelength": WavelengthView()
                case "chat": ChatView()
                case "games": GamesView()
                case "radar": RadarView()
                case "battery": BatteryView()
                case "pool": PoolView()
                case "checkers": CheckersView()
                case "backgammon": BackgammonView()
                case "whiteboard": WhiteboardView()
                case "todo": TodoListView()
                case "notes": SharedNotesView()
                case "likes": LikesView()
                case "dates": SpecialDatesView()
                case "compose": ComposeTouchView()
                case "draw": PatternDrawer(initial: AppModel.demoSlide, colorRGB: 0xEC5A89, endColorRGB: 0xB173DF) { _ in }
                case "partner": if let p = model.selectedPartner { PartnerDetailView(partnerID: p.id) }
                case "weather": if let p = model.selectedPartner { ScrollView { WeatherCard(partner: p).padding(16) } }
                case "homeCards": HomeCardsEditor()
                case "private": PrivateSpaceView()
                case "people": PeopleView()
                default: Text("Unknown screen \(name)")
                }
            }
            .screenBackground()
        }
    }
}
