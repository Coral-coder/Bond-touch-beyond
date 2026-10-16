import SwiftUI

/// Bracelet pairing / connection status. Scans for the Bond Touch vendor service and
/// shows the connection state; the actual BLE work is in `BraceletManager`.
struct ConnectView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(tint)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Button {
                model.bracelet.startScanning()
            } label: {
                Label("Scan for bracelet", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.braceletState == .scanning || model.braceletState == .connecting)

            Text("Wake your bracelet and keep it close. Models: BOND, Bond More, BOND 4, BOND MINI.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var title: String {
        switch model.braceletState {
        case .connected: return "Bracelet connected"
        case .scanning: return "Searching…"
        case .connecting: return "Connecting…"
        case .bluetoothOff: return "Bluetooth is off"
        case .disconnected: return "Not connected"
        }
    }
    private var detail: String {
        switch model.braceletState {
        case .connected: return "Your bracelet is ready to send and receive touches."
        case .scanning, .connecting: return "Looking for your Bond Touch bracelet nearby."
        case .bluetoothOff: return "Turn on Bluetooth to connect your bracelet."
        case .disconnected: return "Tap scan to look for your bracelet."
        }
    }
    private var icon: String {
        switch model.braceletState {
        case .connected: return "antenna.radiowaves.left.and.right"
        case .bluetoothOff: return "antenna.radiowaves.left.and.right.slash"
        default: return "dot.radiowaves.left.and.right"
        }
    }
    private var tint: Color {
        switch model.braceletState {
        case .connected: return .green
        case .bluetoothOff: return .red
        default: return .orange
        }
    }
}
