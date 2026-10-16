import SwiftUI

/// Settings skeleton mirroring the original's device/user sections. No account tier or
/// billing — every feature is free.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

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
            Section("About") {
                LabeledContent("Relay", value: "iCloud (CloudKit)")
                LabeledContent("Telemetry", value: "None")
                LabeledContent("Protocol", value: "Bond Touch v3 BLE")
            }
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
