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
                        row("iOS bundle id (X-Ios-Bundle-Identifier)", BondBackend.iosBundleId)
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

                    section("My database") {
                        if store.firebaseAuthToken.isEmpty {
                            Text("Sign in under Settings → Bond Touch account to read your database.")
                                .font(.footnote).foregroundStyle(Theme.subtitle)
                        } else {
                            NavigationLink {
                                DataDumpView(bearer: store.firebaseAuthToken)
                            } label: {
                                Text("Load everything in my database")
                                    .font(.headline).frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
                                    .background(Theme.accent).foregroundStyle(Theme.bgBottom)
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

/// Shows everything the signed-in account can read from the original Bond Touch database
/// (api.bond-touch.com) as a collapsible, colour-coded JSON tree — one section per endpoint,
/// with an editor (PUT) on the endpoints that accept writes.
private struct DataDumpView: View {
    let bearer: String
    @State private var items: [BondBackend.Fetched] = []
    @State private var loading = true

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
                            .listRowBackground(Color.white.opacity(0.04))
                    } else {
                        Text(item.pretty)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                            .textSelection(.enabled)
                            .listRowBackground(Color.white.opacity(0.04))
                    }
                    if item.editable {
                        NavigationLink {
                            EndpointEditorView(path: item.path, initial: item.pretty, bearer: bearer)
                        } label: {
                            Label("Edit (PUT)", systemImage: "pencil").foregroundStyle(Theme.accent)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
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
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        items = await BondBackend.dumpAccountStructured(bearer: bearer)
        loading = false
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
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(8).background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            Button { Task { await save() } } label: {
                HStack { if busy { ProgressView().tint(Theme.bgBottom) }; Text("Save (PUT)").font(.headline) }
                    .frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
                    .background(Theme.accent).foregroundStyle(Theme.bgBottom)
                    .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            }
            .buttonStyle(.plain).disabled(busy)
            if !result.isEmpty {
                ScrollView {
                    Text(result).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
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
