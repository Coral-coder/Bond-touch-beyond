import SwiftUI

/// Optional legacy Firebase backend (experimental). CloudKit is the default.
struct LegacyDataView: View {
    @EnvironmentObject var store: LocalStore
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Toggle("Use legacy Firebase", isOn: $store.useLegacyFirebase).tint(Theme.accent)
                if store.useLegacyFirebase {
                    TextField("Database URL (https://…firebaseio.com)", text: $store.firebaseDatabaseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Auth token (optional)", text: $store.firebaseAuthToken)
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack { Text("Test connection"); if testing { Spacer(); ProgressView() } }
                    }
                    .disabled(testing || store.firebaseDatabaseURL.isEmpty)
                    if let testResult { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                }
            } footer: {
                Text("Experimental. Bond Touch Beyond uses iCloud by default. The original Firebase project only accepts the original app, so unless its owner registers this app (\(AppConfig.bundleID)) or you provide a working database URL and token, the connection will be rejected.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Legacy data")
    }

    @MainActor private func runTest() async {
        guard let client = store.legacyFirebase else { testResult = "Enable and enter a URL first."; return }
        testing = true; testResult = nil
        let result = await client.testConnection()
        testing = false
        switch result {
        case .ok: testResult = "✅ Connected — this app can read the database."
        case .rejected: testResult = "⛔️ Reached Firebase, but it rejected this app. Only the project owner can allow \(AppConfig.bundleID)."
        case .unreachable(let why): testResult = "⚠️ Couldn't reach it: \(why)"
        }
    }
}
