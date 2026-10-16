import SwiftUI

/// Hidden diagnostics panel (tap the partner bar 5×). Shows exactly which backend the app
/// is reading from and writing to right now — the CloudKit relay and the original Firebase
/// project / Bond API, plus the signed-in account and the current bonds.
struct DebugView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @Environment(\.dismiss) private var dismiss

    private var legacyActive: Bool { store.useLegacyFirebase && !store.firebaseAuthToken.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Active data backend") {
                        row("Reads / writes", legacyActive ? "Original Firebase (bridge)" : "CloudKit (iCloud)")
                        row("CloudKit container", AppConfig.cloudContainerID)
                        row("My CloudKit user ID", model.myUserID.isEmpty ? "—" : model.myUserID)
                    }

                    section("Original Firebase / Bond API") {
                        row("Signed in", store.legacyEmail.isEmpty ? "No" : store.legacyEmail)
                        row("ID token present", store.firebaseAuthToken.isEmpty ? "No" : "Yes")
                        row("Bridge enabled", store.useLegacyFirebase ? "Yes" : "No")
                        row("Project", BondBackend.projectId)
                        row("Realtime Database", BondBackend.rtdbURL)
                        row("REST API", BondBackend.apiBase.absoluteString)
                        row("Storage bucket", BondBackend.storageBucket)
                        row("Firebase API key", BondBackend.apiKey)
                        row("Impersonated app", BondBackend.androidPackage)
                        row("Cert (X-Android-Cert)", BondBackend.androidCert)
                    }

                    section("Partners (\(model.partners.count))") {
                        if model.partners.isEmpty { row("—", "none") }
                        ForEach(model.partners) { p in
                            row(p.displayName, "\(p.online ? "online" : "offline") · zone \(p.bond.id)")
                        }
                    }

                    if !model.pendingBonds.isEmpty {
                        section("Pending invites (\(model.pendingBonds.count))") {
                            ForEach(model.pendingBonds) { b in row("Pending", b.id) }
                        }
                    }

                    section("Bracelet") {
                        row("State", "\(model.braceletState)")
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.subtitle)
            Text(value).font(.footnote.monospaced()).foregroundStyle(.white)
                .textSelection(.enabled)
        }
    }
}
