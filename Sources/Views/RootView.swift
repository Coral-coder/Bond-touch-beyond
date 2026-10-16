import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack {
            Theme.background
            content
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    @ViewBuilder private var content: some View {
        // The original app gates on a complete profile, not on having a partner — the
        // dashboard is shown either way (it offers "Add a partner" when there is none).
        if !store.profile.isComplete {
            OnboardingView()
        } else {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case .home: HomeView()
                    case .touches: MeaningsView()
                    case .map: MapTabView()
                    case .chat: ChatView()
                    case .settings: NavigationStack { SettingsView() }
                    }
                }
                FloatingTabBar(selection: $tab).padding(.bottom, 6)
            }
        }
    }
}
