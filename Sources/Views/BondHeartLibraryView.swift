import PhotosUI
import SwiftUI

/// All saved heartbeats, newest first.
struct HeartLibraryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HeartLibraryList(library: model.heartLibrary)
            .navigationTitle("Library")
    }
}

private struct HeartLibraryList: View {
    @ObservedObject var library: HeartLibrary

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if library.items.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("All heartbeats in one place").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                            Text("Add heartbeats by recording or request one from your loved ones.")
                                .font(.footnote).foregroundStyle(Theme.subtitle)
                        }
                    }
                }
                ForEach(library.items) { hb in
                    NavigationLink {
                        HeartbeatDetailView(id: hb.id).screenBackground().navigationBarTitleDisplayMode(.inline)
                    } label: {
                        GlassCard(padding: 14) {
                            HStack(spacing: 12) {
                                if hb.hasPhoto, let img = library.photo(hb.id) {
                                    HeartPhoto(image: img).frame(width: 40, height: 40)
                                } else {
                                    HeartGlyph(colorRGB: hb.colorRGB, size: 28)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hb.title).font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                                    Text("\(hb.bpm) BPM · \(hb.createdAt.formatted(date: .abbreviated, time: .omitted))\(hb.isSelf ? "" : " · received")")
                                        .font(.caption).foregroundStyle(Theme.subtitle)
                                }
                                Spacer()
                                if library.wornID == hb.id {
                                    Text("Wearing").font(Theme.font(12, .bold)).foregroundStyle(Theme.onAccent)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Theme.accent))
                                }
                                Image(systemName: "chevron.right").foregroundStyle(Theme.subtitle).font(.footnote)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }
}

/// One heartbeat: replay it (EKG + beep + phone vibration), wear it on the pendant, send it
/// to a partner's bracelet, share it by email, edit its name / colour / memory, delete it.
struct HeartbeatDetailView: View {
    @EnvironmentObject var model: AppModel
    let id: UUID
    var body: some View {
        HeartbeatDetail(id: id, library: model.heartLibrary, pendant: model.pendant)
    }
}

private struct HeartbeatDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @ObservedObject var library: HeartLibrary
    @ObservedObject var pendant: HeartPendant

    @State private var name = ""
    @State private var colorRGB = EKG.colorRGB
    @State private var memory = ""
    @State private var emails: [String] = []
    @State private var newEmail = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var loaded = false
    @State private var playStart: Date?
    @State private var sound = HeartbeatSound()
    @State private var message: String?
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var sharing = false

    var body: some View {
        if let hb = library.item(id) {
            content(hb)
                .onAppear { load(hb) }
                .onDisappear { commit(); stop() }
                .sheet(isPresented: $sharing) { HeartShareSheet(heartbeat: hb) }
                .confirmationDialog("Delete heartbeat?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete heartbeat", role: .destructive) {
                        stop()
                        library.delete(id)
                        if model.legacySignedIn { Task { await model.heartSync() } }
                        dismiss()
                    }
                } message: {
                    Text(library.wornID == id
                         ? "You're currently wearing this heartbeat. If you delete it, it will be lost forever and you need to pick another one to wear."
                         : hb.isSelf ? "You will have to record it again." : "\(hb.name)'s heartbeat will be lost forever.")
                }
        } else {
            Text("This heartbeat was deleted.").foregroundStyle(Theme.subtitle)
        }
    }

    private func content(_ hb: SavedHeartbeat) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header(hb)
                replayCard(hb)
                actions(hb)
                editCard(hb)
                Button("Delete heartbeat") { confirmDelete = true }
                    .font(Theme.font(15, .bold)).foregroundStyle(Theme.danger)
                    .padding(.top, 4)
                Color.clear.frame(height: 12)
            }
            .padding(20)
        }
        .navigationTitle(hb.title)
    }

    private func header(_ hb: SavedHeartbeat) -> some View {
        VStack(spacing: 8) {
            if let photo {
                HeartPhoto(image: photo).frame(width: 150, height: 150)
            } else {
                HeartGlyph(colorRGB: colorRGB, size: 80, bpm: playStart == nil ? nil : hb.bpm)
            }
            Text(hb.title).font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
            Text("Recorded on \(hb.createdAt.formatted(date: .long, time: .shortened))")
                .font(.caption).foregroundStyle(Theme.subtitle)
            if !hb.isSelf, let by = hb.createdBy, !by.isEmpty {
                Text("Received from: \(by)").font(.caption).foregroundStyle(Theme.subtitle)
            }
            if !hb.memory.isEmpty {
                Text(hb.memory).font(.footnote).foregroundStyle(Theme.title).multilineTextAlignment(.center)
            }
        }
    }

    private func replayCard(_ hb: SavedHeartbeat) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(hb.bpm)").font(Theme.font(28, .heavy)).foregroundStyle(Theme.title).monospacedDigit()
                    Text("BPM").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                    Spacer()
                    Text("\(hb.intervals.count) beats · \(Int(hb.seconds.rounded())) s").font(.caption).foregroundStyle(Theme.subtitle)
                }
                EKGView(bpm: hb.bpm, colorRGB: colorRGB, start: playStart).frame(height: 80)
                Button(playStart == nil ? "Feel the heartbeat" : "Stop") { playStart == nil ? play(hb) : stop() }
                    .buttonStyle(GlassButtonStyle(height: 40))
            }
        }
    }

    private func actions(_ hb: SavedHeartbeat) -> some View {
        VStack(spacing: 10) {
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.title).multilineTextAlignment(.center)
            }
            Button {
                commit()
                run {
                    do {
                        try await model.wearHeartbeat(library.item(id) ?? hb)
                        message = "Heartbeat worn successfully!"
                    } catch { message = error.localizedDescription }
                }
            } label: {
                Label(library.wornID == id ? "Wear again" : "Wear on my Heart", systemImage: "heart.circle")
            }
            .buttonStyle(AccentButtonStyle(height: 46))
            .disabled(busy || !pendant.state.isUsable)

            if !model.partners.isEmpty {
                Menu {
                    ForEach(model.partners) { p in
                        Button(p.displayName) {
                            run {
                                let ok = await model.sendSavedHeartbeat(library.item(id) ?? hb, toBondID: p.id)
                                message = ok ? "Sent to \(p.displayName)'s bracelet." : (model.statusLine.isEmpty ? "Couldn't send it." : model.statusLine)
                            }
                        }
                    }
                } label: {
                    Label("Send to a partner's bracelet", systemImage: "paperplane")
                        .font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .glass(Capsule())
                }
                .disabled(busy)
            }
            if model.legacySignedIn {
                Button { commit(); sharing = true } label: {
                    Label("Share by email", systemImage: "envelope")
                }
                .buttonStyle(GlassButtonStyle(height: 46))
            }
        }
    }

    private func editCard(_ hb: SavedHeartbeat) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Name").font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit { commit() }
                Text("Color").font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                Text("This color will light up on the Heart when the heartbeat is felt.")
                    .font(.caption).foregroundStyle(Theme.subtitle)
                HeartColorRow(colorRGB: $colorRGB)
                Text("Memory").font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                TextField("A memory (optional)", text: $memory, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                HeartPhotoPicker(item: $photoItem, image: $photo)
                if model.legacySignedIn {
                    Text("Heartbeat count").font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                    Text("Choose who can see this heartbeat count (up to 3).")
                        .font(.caption).foregroundStyle(Theme.subtitle)
                    ForEach(emails, id: \.self) { e in
                        HStack {
                            Text(e).font(.footnote).foregroundStyle(Theme.title)
                            Spacer()
                            Button { emails.removeAll { $0 == e }; commit() } label: { Image(systemName: "xmark.circle.fill") }
                                .foregroundStyle(Theme.subtitle)
                        }
                    }
                    if emails.count < 3 {
                        HStack {
                            TextField("name@email.com", text: $newEmail)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Add") {
                                let e = newEmail.trimmingCharacters(in: .whitespaces).lowercased()
                                if e.contains("@"), !emails.contains(e) { emails.append(e); newEmail = ""; commit() }
                            }
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .onChange(of: colorRGB) { _ in commit() }
        .onChange(of: photo) { newPhoto in
            guard loaded else { return }
            library.setPhoto(newPhoto, for: id)
        }
    }

    // MARK: Actions

    private func load(_ hb: SavedHeartbeat) {
        guard !loaded else { return }
        name = hb.name
        colorRGB = hb.colorRGB
        memory = hb.memory
        emails = hb.emails
        photo = hb.hasPhoto ? library.photo(hb.id) : nil
        // Let the initial values settle before onChange starts saving.
        DispatchQueue.main.async { loaded = true }
    }

    /// Saves edits (marked for upload if the heartbeat is on the Bond Touch account).
    private func commit() {
        guard loaded, var hb = library.item(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let changed = hb.name != trimmed || hb.colorRGB != colorRGB || hb.memory != memory || hb.emails != emails
        guard changed else { return }
        if !trimmed.isEmpty { hb.name = trimmed }
        hb.colorRGB = colorRGB
        hb.memory = memory
        hb.emails = emails
        if hb.serverID != nil { hb.dirty = true }
        library.upsert(hb)
    }

    private func play(_ hb: SavedHeartbeat) {
        let start = Date()
        playStart = start
        let seconds = min(20, max(5, hb.seconds))
        sound.play(bpm: hb.bpm, seconds: seconds, start: start)
        model.haptics.playHeartbeat(bpm: hb.bpm, seconds: seconds)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if playStart == start { playStart = nil }
        }
    }

    private func stop() {
        playStart = nil
        sound.stop()
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        message = nil
        Task { await work(); busy = false }
    }
}

/// Share a heartbeat with someone by their Bond Touch account email.
struct HeartShareSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let heartbeat: SavedHeartbeat
    @State private var email = ""
    @State private var note = ""
    @State private var busy = false
    @State private var result: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HeartGlyph(colorRGB: heartbeat.colorRGB, size: 60, bpm: heartbeat.bpm)
                    if sent {
                        Text("Heartbeat sent!").font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                        Text("Once received, your loved one will be able to save it within their library!")
                            .font(.footnote).foregroundStyle(Theme.subtitle).multilineTextAlignment(.center)
                        Button("Got it!") { dismiss() }.buttonStyle(AccentButtonStyle())
                    } else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Who do you want to send it to?").font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                                TextField("name@email.com", text: $email)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                                Text("Make it personal").font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                                Text("Add a lovely message if you want, it’s totally optional.")
                                    .font(.caption).foregroundStyle(Theme.subtitle)
                                TextField("Message", text: $note, axis: .vertical)
                                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                            }
                        }
                        if let result { Text(result).font(.footnote).foregroundStyle(Theme.amber) }
                        Button {
                            busy = true
                            Task {
                                let e = email.trimmingCharacters(in: .whitespaces)
                                result = await model.shareHeartbeat(model.heartLibrary.item(heartbeat.id) ?? heartbeat,
                                                                    toEmail: e, message: note)
                                sent = result == nil
                                busy = false
                            }
                        } label: {
                            if busy { ProgressView().tint(Theme.onAccent) } else { Text("Send heartbeat") }
                        }
                        .buttonStyle(AccentButtonStyle())
                        .disabled(busy || !email.contains("@"))
                        Text("It's uploaded to your Bond Touch account to be shared. A memory photo can't be shared from this app (the original servers only let their own app use photo storage).")
                            .font(.caption).foregroundStyle(Theme.subtitle).multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Share heartbeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// Heartbeats shared with you, requests for your heartbeat, and asking someone for theirs —
/// through the original Bond Touch account (the original's received / waiting screens).
struct HeartSharedView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HeartShared(library: model.heartLibrary)
            .navigationTitle("Shared & requests")
    }
}

private struct HeartShared: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var library: HeartLibrary
    @State private var askEmail = ""
    @State private var message: String?
    @State private var busy = false
    @State private var rejecting: PendingHeartbeat?
    @State private var removing: HeartRequest?

    private var received: [HeartRequest] { library.requests.filter { model.isReceived($0) } }
    private var sent: [HeartRequest] { library.requests.filter { !model.isReceived($0) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !model.legacySignedIn {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Send & ask for a heartbeat").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                            Text("Heartbeat requests go through the original Bond Touch servers, which need a Bond Touch account (in the debug menu). You can still send a heartbeat to a partner's bracelet from the library.")
                                .font(.footnote).foregroundStyle(Theme.subtitle)
                        }
                    }
                } else {
                    if let message { Text(message).font(.footnote).foregroundStyle(Theme.title).multilineTextAlignment(.center) }
                    askCard
                    pendingSection
                    requestsSection
                    if library.pending.isEmpty && library.requests.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("All good").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                                Text("No requests to manage.").font(.footnote).foregroundStyle(Theme.subtitle)
                            }
                        }
                    }
                    if !library.syncStatus.isEmpty {
                        Text(library.syncStatus).font(.caption).foregroundStyle(Theme.amber)
                    } else if let at = library.lastSync {
                        Text("Updated \(at.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(Theme.subtitle)
                    }
                }
                Color.clear.frame(height: 12)
            }
            .padding(20)
        }
        .refreshable { await model.heartSync() }
        .task { await model.heartSync() }
        .confirmationDialog("Reject \(rejecting?.name ?? "")'s heartbeat?",
                            isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } }),
                            titleVisibility: .visible) {
            Button("Reject", role: .destructive) {
                if let p = rejecting { run { message = await model.rejectPending(p) } }
            }
        }
        .confirmationDialog(removing.map { model.isReceived($0) ? "Reject \($0.fromUserName)'s request?" : "Delete request?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button(removing.map { model.isReceived($0) ? "Reject" : "Delete" } ?? "Delete", role: .destructive) {
                if let r = removing { run { message = await model.deleteHeartRequest(r) } }
            }
        } message: {
            Text(removing.map { model.isReceived($0) ? "This request will be permanently deleted." : "You are about to delete your request. If you proceed, you will need to request it again." } ?? "")
        }
    }

    private var askCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ask for a heartbeat").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                Text("Whose heartbeat are you asking for? They’ll receive a request to record their heartbeat.")
                    .font(.caption).foregroundStyle(Theme.subtitle)
                HStack {
                    TextField("name@email.com", text: $askEmail)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Ask") {
                        let e = askEmail.trimmingCharacters(in: .whitespaces)
                        run {
                            if let err = await model.askForHeartbeat(email: e) { message = err }
                            else { message = "Request sent! Once they send you their heartbeat, you'll find it here."; askEmail = "" }
                        }
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(busy || !askEmail.contains("@"))
                }
            }
        }
    }

    @ViewBuilder private var pendingSection: some View {
        if !library.pending.isEmpty {
            sectionTitle("Pending (\(library.pending.count))")
            ForEach(library.pending) { p in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            HeartGlyph(colorRGB: p.colorRGB, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(p.name)’s heartbeat").font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                                Text("Received from: \(p.createdBy)").font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        }
                        if !p.message.isEmpty { Text(p.message).font(.footnote).foregroundStyle(Theme.title) }
                        if p.intervals.count > 1 {
                            EKGView(bpm: SavedHeartbeat(name: p.name, colorRGB: p.colorRGB, intervals: p.intervals).bpm,
                                    colorRGB: p.colorRGB).frame(height: 40)
                        }
                        HStack(spacing: 10) {
                            Button("Keep it") { run { message = await model.acceptPending(p) ?? "Saved to your library." } }
                                .buttonStyle(AccentButtonStyle(height: 40))
                            Button("Reject") { rejecting = p }
                                .buttonStyle(GlassButtonStyle(height: 40))
                        }
                        .disabled(busy)
                    }
                }
            }
        }
    }

    @ViewBuilder private var requestsSection: some View {
        if !received.isEmpty {
            sectionTitle("Asking for your heartbeat")
            ForEach(received) { r in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(r.fromUserName.isEmpty ? r.fromUser : r.fromUserName) is asking for your heartbeat")
                            .font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                        Text("Record a heartbeat or choose one from the library to send.")
                            .font(.caption).foregroundStyle(Theme.subtitle)
                        HStack(spacing: 10) {
                            Menu {
                                ForEach(library.items) { hb in
                                    Button(hb.title) { run { message = await model.answerRequest(r, with: hb) ?? "Heartbeat sent!" } }
                                }
                            } label: {
                                Text("Choose a heartbeat").font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                                    .frame(maxWidth: .infinity).frame(height: 40).glass(Capsule())
                            }
                            .disabled(library.items.isEmpty || busy)
                            Button("Reject") { removing = r }
                                .buttonStyle(GlassButtonStyle(height: 40))
                        }
                    }
                }
            }
        }
        if !sent.isEmpty {
            sectionTitle("Waiting")
            ForEach(sent) { r in
                GlassCard(padding: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pending request to:").font(.caption).foregroundStyle(Theme.subtitle)
                            Text(r.toUser).font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                        }
                        Spacer()
                        Button { removing = r } label: { Image(systemName: "trash") }
                            .foregroundStyle(Theme.subtitle)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(Theme.font(15, .heavy)).foregroundStyle(Theme.subtitle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        message = nil
        Task { await work(); busy = false }
    }
}
