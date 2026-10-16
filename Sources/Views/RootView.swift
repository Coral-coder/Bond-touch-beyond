import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    var body: some View {
        Group {
            if !store.profile.isComplete {
                OnboardingView()
            } else if model.partners.isEmpty {
                NavigationStack {
                    PairingView().navigationTitle("Beyond Touch")
                }
                .safeAreaInset(edge: .bottom) { statusBar }
            } else {
                TabView {
                    NavigationStack { BondView().navigationTitle("Touch") }
                        .tabItem { Label("Touch", systemImage: "hand.tap.fill") }
                    NavigationStack { ChatView().navigationTitle("Chat") }
                        .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }
                    NavigationStack { HeartView().navigationTitle("Heartbeat") }
                        .tabItem { Label("Heartbeat", systemImage: "waveform.path.ecg") }
                    NavigationStack { PeopleView().navigationTitle("People") }
                        .tabItem { Label("People", systemImage: "person.2.fill") }
                    NavigationStack { MoreView().navigationTitle("More") }
                        .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                }
            }
        }
    }

    private var statusBar: some View {
        Text(model.statusLine)
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(8).background(.ultraThinMaterial)
    }
}

/// "More" groups the secondary screens so the tab bar stays to five items.
struct MoreView: View {
    var body: some View {
        List {
            NavigationLink { MeaningsView().navigationTitle("Meanings") } label: {
                Label("Meanings", systemImage: "heart.text.square.fill")
            }
            NavigationLink { HistoryView().navigationTitle("History") } label: {
                Label("History", systemImage: "clock.fill")
            }
            NavigationLink { ConnectView().navigationTitle("Bracelet") } label: {
                Label("Bracelet", systemImage: "dot.radiowaves.left.and.right")
            }
            NavigationLink { SettingsView().navigationTitle("Settings") } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}
