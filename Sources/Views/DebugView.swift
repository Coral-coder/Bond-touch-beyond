import SwiftUI

/// Hidden diagnostics panel (tap the partner bar 5×). Shows exactly which backend the app
/// is reading from and writing to right now — the CloudKit relay and the original Firebase
/// project / Bond API, plus the signed-in account and the current bonds.
struct DebugView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @ObservedObject private var netLog = NetLog.shared
    @AppStorage("showKissButton") private var showKissButton = false
    @AppStorage(Poly.modeKey) private var polyMode = Poly.Mode.auto.rawValue
    @Environment(\.dismiss) private var dismiss

    private var legacyActive: Bool { store.useLegacyFirebase && !store.firebaseAuthToken.isEmpty }

    private var tokenExpiryText: String {
        guard let exp = BondBackend.tokenExpiry(store.firebaseAuthToken) else { return "—" }
        return exp.formatted(date: .abbreviated, time: .standard)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Experimental") {
                        Toggle("Kiss button (next to the heartbeat)", isOn: $showKissButton)
                            .font(.footnote).tint(Theme.accent)
                        Picker("Polyamory features", selection: $polyMode) {
                            ForEach(Poly.Mode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        .font(.footnote).tint(Theme.accent)
                        Text("R.A.D.A.R., the poly calendar, and metamours & compersion. Automatic turns them on once you have two or more partners (now \(model.partners.count)) — currently \(Poly.isOn ? "on" : "off").")
                            .font(.caption2).foregroundStyle(Theme.subtitle)
                    }

                    section("Active data backend") {
                        row("Reads / writes", legacyActive ? "CloudKit (iCloud) + original Bond API, in parallel" : "CloudKit (iCloud)")
                        row("CloudKit container", AppConfig.cloudContainerID)
                        row("My CloudKit user ID", model.myUserID.isEmpty ? "—" : model.myUserID)
                    }

                    section("Original Firebase / Bond API") {
                        NavigationLink {
                            LegacyLoginView().screenBackground().navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack {
                                Text(store.legacyEmail.isEmpty ? "Sign in to a Bond Touch account" : "Bond Touch account")
                                    .font(.footnote.bold()).foregroundStyle(Theme.accent)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        }
                        row("Signed in", store.legacyEmail.isEmpty ? "No" : store.legacyEmail)
                        row("ID token present", store.firebaseAuthToken.isEmpty ? "No" : "Yes")
                        row("Bridge enabled", store.useLegacyFirebase ? "Yes" : "No")
                        row("Sync status", model.legacyStatus)
                        row("Chat", "iCloud · \(store.chatLinks.count) original-app partner(s) linked")
                        row("Firebase Storage", FirebaseStorage.appCheckBlocked
                            ? "Blocked by App Check (official app only)" : "No App Check block seen")
                        row("Last sync", model.legacyLastSync?.formatted(date: .omitted, time: .standard) ?? "—")
                        row("Token expires", tokenExpiryText)
                        row("Project", BondBackend.projectId)
                        row("Realtime Database", BondBackend.rtdbURL)
                        row("REST API", BondBackend.apiBase.absoluteString)
                        row("Storage bucket", BondBackend.storageBucket)
                        row("Firebase API key", BondBackend.apiKey)
                        row("iOS bundle id (X-Ios-Bundle-Identifier)", BondBackend.iosBundleId)
                    }

                    section("Partners (\(model.partners.count))") {
                        if model.partners.isEmpty { row("—", "none") }
                        ForEach(model.partners) { p in
                            row(p.displayName, "\(p.bond.legacy ? "Bond API" : "iCloud") · \(p.online ? "online" : "offline") · \(p.bond.legacy ? "bondId" : "zone") \(p.bond.id)")
                        }
                    }

                    if !model.pendingBonds.isEmpty {
                        section("Pending invites (\(model.pendingBonds.count))") {
                            ForEach(model.pendingBonds) { b in row(b.legacy ? "Pending (Bond API)" : "Pending (iCloud)", b.id) }
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
                                Text("Send a touch, or wait for one to arrive, and it shows here — which backend, and whether the server accepted it.")
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

                    section("My database") {
                        if store.firebaseAuthToken.isEmpty {
                            Text("Sign in above (Bond Touch account) to read your database.")
                                .font(.footnote).foregroundStyle(Theme.subtitle)
                        } else {
                            NavigationLink {
                                DataDumpView(bearer: store.firebaseAuthToken)
                            } label: {
                                Text("Load everything in my database")
                                    .font(.headline).frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
                                    .background(Theme.accent).foregroundStyle(Theme.onAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
                            }
                            .buttonStyle(.plain)
                        }
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

/// Shows everything the signed-in account can read from the original Bond Touch database
/// (api.bond-touch.com) as a collapsible, colour-coded JSON tree — one section per endpoint,
/// with an editor (PUT) on the endpoints that accept writes.
private struct DataDumpView: View {
    let bearer: String
    @State private var items: [BondBackend.Fetched] = []
    @State private var loading = true
    @State private var exportURL: URL?

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView().tint(Theme.accent); Spacer() }
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                Section {
                    if let json = item.json {
                        JSONNode(key: nil, value: json)
                            .listRowBackground(Theme.ink.opacity(0.04))
                    } else {
                        Text(item.pretty)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.title)
                            .textSelection(.enabled)
                            .listRowBackground(Theme.ink.opacity(0.04))
                    }
                    if item.editable {
                        NavigationLink {
                            EndpointEditorView(path: item.path, initial: item.pretty, bearer: bearer)
                        } label: {
                            Label("Edit (PUT)", systemImage: "pencil").foregroundStyle(Theme.accent)
                        }
                        .listRowBackground(Theme.ink.opacity(0.04))
                    }
                } header: {
                    Text("/\(item.path)  ·  HTTP \(item.status)")
                        .font(.caption.monospaced()).foregroundStyle(Theme.subtitle)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("My database")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading)
            }
            ToolbarItem(placement: .primaryAction) {
                if let exportURL {
                    ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Export database")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        items = await BondBackend.dumpAccountStructured(bearer: bearer)
        exportURL = writeExport(items)
        loading = false
    }

    /// Writes everything fetched to one pretty-printed JSON file for the share sheet
    /// (save to Files, AirDrop, mail…): `{ "exportedAt", "endpoints": { "/path": {status, body} } }`.
    private func writeExport(_ items: [BondBackend.Fetched]) -> URL? {
        var endpoints: [String: Any] = [:]
        for item in items {
            endpoints["/" + item.path] = ["status": item.status, "body": item.json ?? item.pretty]
        }
        let root: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "source": BondBackend.apiBase.absoluteString,
            "endpoints": endpoints
        ]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BondTouch-database-\(stamp).json")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

/// Raw JSON editor for one endpoint: edit the body and PUT it back.
private struct EndpointEditorView: View {
    let path: String
    let bearer: String
    @State private var text: String
    @State private var result = ""
    @State private var busy = false

    init(path: String, initial: String, bearer: String) {
        self.path = path
        self.bearer = bearer
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.title)
                .scrollContentBackground(.hidden)
                .padding(8).background(Theme.ink.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            Button { Task { await save() } } label: {
                HStack { if busy { ProgressView().tint(Theme.onAccent) }; Text("Save (PUT)").font(.headline) }
                    .frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
                    .background(Theme.accent).foregroundStyle(Theme.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            }
            .buttonStyle(.plain).disabled(busy)
            if !result.isEmpty {
                ScrollView {
                    Text(result).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.title)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            Spacer()
        }
        .padding(16)
        .screenBackground()
        .navigationTitle(path)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        busy = true; result = ""
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            result = "Invalid JSON — fix it before saving."; busy = false; return
        }
        result = await BondBackend.putRaw(path, body: data, bearer: bearer)
        busy = false
    }
}
