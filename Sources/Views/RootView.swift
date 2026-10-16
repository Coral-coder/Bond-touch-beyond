import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.bond == nil {
                NavigationStack {
                    PairingView().navigationTitle("Bond Touch Beyond")
                }
            } else {
                TabView {
                    NavigationStack { BondView().navigationTitle("Touch") }
                        .tabItem { Label("Touch", systemImage: "hand.tap.fill") }
                    NavigationStack { MeaningsView().navigationTitle("Meanings") }
                        .tabItem { Label("Meanings", systemImage: "heart.text.square.fill") }
                    NavigationStack { HeartView().navigationTitle("Heartbeat") }
                        .tabItem { Label("Heartbeat", systemImage: "waveform.path.ecg") }
                    NavigationStack { HistoryView().navigationTitle("History") }
                        .tabItem { Label("History", systemImage: "clock.fill") }
                    NavigationStack { SettingsView().navigationTitle("Settings") }
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.bond == nil {
                Text(model.statusLine)
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(8).background(.ultraThinMaterial)
            }
        }
    }
}
