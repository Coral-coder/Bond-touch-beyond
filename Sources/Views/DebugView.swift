import SwiftUI

/// Hidden diagnostics panel (tap the partner bar 5×). Shows the backend the app reads from
/// and writes to (the CloudKit relay), the current bonds and the touch send / receive log.
struct DebugView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @ObservedObject private var netLog = NetLog.shared
    @AppStorage(Poly.modeKey) private var polyMode = Poly.Mode.auto.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Bracelet lights") {
                        NavigationLink { LightLabView() } label: {
                            Label("Light lab — light without vibrating, POV text", systemImage: "lightbulb.led.fill")
                                .font(.footnote)
                        }
                    }

                    section("Experimental") {
                        Picker("Polyamory features", selection: $polyMode) {
                            ForEach(Poly.Mode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        .font(.footnote).tint(Theme.accent)
                        Text("R.A.D.A.R., the poly calendar, and metamours & compersion. Automatic turns them on once you have two or more partners (now \(model.partners.count)) — currently \(Poly.isOn ? "on" : "off").")
                            .font(.caption2).foregroundStyle(Theme.subtitle)
                    }

                    section("Active data backend") {
                        row("Reads / writes", "CloudKit (iCloud)")
                        row("CloudKit container", AppConfig.cloudContainerID)
                        row("My CloudKit user ID", model.myUserID.isEmpty ? "—" : model.myUserID)
                    }

                    section("Partners (\(model.partners.count))") {
                        if model.partners.isEmpty { row("—", "none") }
                        ForEach(model.partners) { p in
                            row(p.displayName, "iCloud · \(p.online ? "online" : "offline") · zone \(p.bond.id)")
                        }
                    }

                    if !model.pendingBonds.isEmpty {
                        section("Pending invites (\(model.pendingBonds.count))") {
                            ForEach(model.pendingBonds) { b in row("Pending (iCloud)", b.id) }
                        }
                    }

                    section("Bracelet") {
                        row("State", "\(model.braceletState)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("TOUCH SEND / RECEIVE LOG").font(.caption.bold()).foregroundStyle(Theme.accent)
                            Spacer()
                            if !netLog.entries.isEmpty {
                                Button("Clear") { netLog.clear() }.font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if netLog.entries.isEmpty {
                                Text("Send a touch, or wait for one to arrive, and it shows here — and whether it went through.")
                                    .font(.footnote).foregroundStyle(Theme.subtitle)
                            }
                            ForEach(netLog.entries) { e in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(logIcon(e.kind))
                                        Text(e.title).font(.caption.bold()).foregroundStyle(Theme.title)
                                        Spacer()
                                        Text(e.at.formatted(date: .omitted, time: .standard))
                                            .font(.caption2).foregroundStyle(Theme.subtitle)
                                    }
                                    if !e.detail.isEmpty {
                                        Text(e.detail).font(.caption2.monospaced()).foregroundStyle(Theme.subtitle)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.ink.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
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
                .background(Theme.ink.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
        }
    }

    private func logIcon(_ kind: NetLog.Entry.Kind) -> String {
        switch kind {
        case .send: return "↗️"
        case .ok:   return "✅"
        case .fail: return "❌"
        case .recv: return "↘️"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.subtitle)
            Text(value).font(.footnote.monospaced()).foregroundStyle(Theme.title)
                .textSelection(.enabled)
        }
    }
}
