import CloudKit
import SwiftUI

struct PairingView: View {
    @EnvironmentObject var model: AppModel
    @State private var displayName = ""
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.pink)
            Text("Pair with one person. Touches you send go to their bracelet, and theirs to yours — relayed privately through iCloud.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TextField("Your name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            Button {
                Task {
                    await model.createBond(displayName: displayName.isEmpty ? "Me" : displayName)
                    showShare = model.pendingShare != nil
                }
            } label: {
                Label("Create a bond & invite", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Your partner joins by opening the invite you send them. No account, no server — just your two iCloud accounts.")
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
