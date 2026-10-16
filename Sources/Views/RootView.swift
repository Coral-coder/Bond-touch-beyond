import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @EnvironmentObject var recovery: FirmwareRecovery
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .overlay(alignment: .top) { RecoveryBanner().padding(.top, 60) }
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
