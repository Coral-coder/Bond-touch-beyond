import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.bond == nil {
                    PairingView()
                } else {
                    BondView()
                }
            }
            .navigationTitle("Bond Touch Beyond")
            .safeAreaInset(edge: .bottom) {
                Text(model.statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.ultraThinMaterial)
            }
        }
    }
}
