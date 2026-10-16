import CloudKit
import SwiftUI

/// Create a bond and invite a partner. Used when the user has no partners yet, and from
/// the People screen to add another.
struct PairingView: View {
    @EnvironmentObject var model: AppModel
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.pink)
            Text("Pair with someone. Touches, messages and your heartbeat are relayed privately through iCloud — no account, no server.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await model.createBond()
                    showShare = model.pendingShare != nil
                }
            } label: {
                Label("Create a bond & invite", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Your partner joins by opening the invite you send them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .sheet(isPresented: $showShare) {
            if let share = model.pendingShare {
                CloudShareSheet(share: share, container: CKContainer(identifier: "iCloud.com.coralcoder.bondtouchbeyond"))
            }
        }
    }
}
