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
        .tint(Theme.teal)
    }

    @ViewBuilder private var content: some View {
        if !store.profile.isComplete {
            OnboardingView()
        } else if model.partners.isEmpty {
            NavigationStack { PairingView().navigationTitle("Bond Touch Beyond") }
                .safeAreaInset(edge: .bottom) {
                    Text(model.statusLine).font(.footnote).foregroundStyle(Theme.subtitle)
                        .frame(maxWidth: .infinity).padding(8)
                }
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
