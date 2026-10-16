import SwiftUI
import UniformTypeIdentifiers

/// Banner shown on every screen while a bracelet needs, gets or finished a firmware repair.
struct RecoveryBanner: View {
    @EnvironmentObject var recovery: FirmwareRecovery
    @EnvironmentObject var model: AppModel
    @State private var importing = false

    var body: some View {
        Group {
            switch recovery.phase {
            case .idle:
                EmptyView()
            case .needsFirmware(let m):
                card(icon: "exclamationmark.triangle.fill", tint: Theme.amber,
                     title: "\(m.title) is stuck in update mode",
                     detail: "Import its official firmware file once and it will be repaired automatically.") {
                    Button("Import firmware") { importing = true }
                        .buttonStyle(AccentButtonStyle(height: 40))
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
                    if case .success(let url) = result {
                        do { try recovery.importFirmware(from: url, model: m) }
                        catch { recovery.importError = "That file isn't a bracelet firmware package." }
                    }
                }
            case .flashing(let m, let progress):
                card(icon: "arrow.triangle.2.circlepath", tint: Theme.accent,
                     title: "Repairing your \(m.title)… \(progress)%",
                     detail: "Keep the phone next to the bracelet. This takes about a minute.") {
                    ProgressView(value: Double(progress), total: 100).tint(Theme.accent)
                }
            case .done(let m):
                card(icon: "checkmark.seal.fill", tint: Theme.lime,
                     title: "\(m.title) repaired",
                     detail: "It restarted with its official firmware and will reconnect on its own.") {
                    Button("OK") { recovery.dismiss() }.buttonStyle(GlassButtonStyle(height: 40))
                }
            case .failed(let m, let message):
                card(icon: "xmark.octagon.fill", tint: Theme.danger,
                     title: "Couldn't repair the \(m.title)",
                     detail: message + " Put the bracelet on its charger, keep it close, and try again.") {
                    HStack(spacing: 10) {
                        Button("Try again") {
                            if let d = model.bracelet.dfuDevice { recovery.recover(d) }
                        }
                        .buttonStyle(AccentButtonStyle(height: 40))
                        Button("Close") { recovery.dismiss() }.buttonStyle(GlassButtonStyle(height: 40))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35), value: recovery.phase)
    }

    private func card<Actions: View>(icon: String, tint: Color, title: String, detail: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint).font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(15, .heavy)).foregroundStyle(.white)
                    Text(detail).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            actions()
        }
        .padding(14)
        .glass(cornerRadius: 22)
        .padding(.horizontal, 16)
    }
}

/// Settings → Bracelet firmware: the imported recovery firmware per model.
struct FirmwareSettingsView: View {
    @EnvironmentObject var recovery: FirmwareRecovery
    @State private var importModel: BraceletModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("If a bracelet ever gets stuck in update mode, the app repairs it automatically with its official firmware, built into the app. You can also import a newer official file.")
                    .font(Theme.font(14)).foregroundStyle(Theme.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(BraceletModel.allCases) { m in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(Theme.font(16, .bold)).foregroundStyle(.white)
                            Text(recovery.installed[m] ?? (recovery.hasBuiltIn(m) ? "Built in — repairs automatically" : "No firmware"))
                                .font(Theme.font(12)).foregroundStyle(Theme.subtitle).lineLimit(1)
                        }
                        Spacer()
                        Button(recovery.installed[m] == nil ? "Import" : "Replace") { importModel = m }
                            .font(Theme.font(14, .heavy)).foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .padding(14).glass(cornerRadius: 20)
                }
                if let error = recovery.importError {
                    Text(error).font(Theme.font(13)).foregroundStyle(Theme.danger)
                }
            }
            .padding(20)
        }
        .navigationTitle("Bracelet firmware")
        .fileImporter(isPresented: Binding(get: { importModel != nil }, set: { if !$0 { importModel = nil } }),
                      allowedContentTypes: [.zip]) { result in
            guard let m = importModel, case .success(let url) = result else { importModel = nil; return }
            do { try recovery.importFirmware(from: url, model: m); recovery.importError = nil }
            catch { recovery.importError = "That file isn't a bracelet firmware package." }
            importModel = nil
        }
    }
}
