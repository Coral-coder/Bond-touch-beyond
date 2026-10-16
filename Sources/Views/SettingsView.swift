import SwiftUI

/// Settings skeleton mirroring the original's device/user sections. No account tier or
/// billing — every feature is free.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section("Bracelet") {
                LabeledContent("Connection", value: connectionText)
                VStack(alignment: .leading) {
                    Text("Vibration strength: \(Int(store.vibrationStrength))")
                    Slider(value: $store.vibrationStrength, in: 0...255, step: 5)
                }
                Toggle("Do Not Disturb", isOn: $store.doNotDisturb)
            }
            Section("Partner") {
                LabeledContent("Selected partner", value: model.selectedPartner?.displayName ?? "—")
                LabeledContent("Partners", value: "\(model.partners.count)")
            }
            Section {
                Toggle("Use legacy Firebase", isOn: $store.useLegacyFirebase)
                if store.useLegacyFirebase {
                    TextField("Database URL (https://…firebaseio.com)", text: $store.firebaseDatabaseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Auth token (optional)", text: $store.firebaseAuthToken)
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(testing || store.firebaseDatabaseURL.isEmpty)
                    if let testResult { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Legacy data")
            } footer: {
                Text("Experimental. Beyond Touch uses iCloud by default. The original Firebase project only accepts the original app, so unless its owner registers this app (\(AppConfig.bundleID)) or you provide a working database URL and token, the connection will be rejected.")
            }
            Section("About") {
                LabeledContent("Relay", value: store.useLegacyFirebase ? "iCloud + legacy Firebase" : "iCloud (CloudKit)")
                LabeledContent("Telemetry", value: "None")
                LabeledContent("Protocol", value: "Bond Touch v3 BLE")
            }
        }
    }

    @MainActor private func runTest() async {
        guard let client = store.legacyFirebase else { testResult = "Enable and enter a URL first."; return }
        testing = true; testResult = nil
        let result = await client.testConnection()
        testing = false
        switch result {
        case .ok: testResult = "✅ Connected — this app can read the database."
        case .rejected: testResult = "⛔️ Reached Firebase, but it rejected this app (auth / rules / App Check). Only the project owner can allow \(AppConfig.bundleID)."
        case .unreachable(let why): testResult = "⚠️ Couldn't reach it: \(why)"
        }
    }

    private var connectionText: String {
        switch model.braceletState {
        case .connected: return "Connected"
        case .scanning, .connecting: return "Searching…"
        case .bluetoothOff: return "Bluetooth off"
        case .disconnected: return "Not connected"
        }
    }
}
