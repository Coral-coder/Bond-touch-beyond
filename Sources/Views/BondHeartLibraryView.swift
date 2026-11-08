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
                            Text("Add heartbeats by recording them.")
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
/// to a partner's bracelet, edit its name / colour / memory, delete it.
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
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var loaded = false
    @State private var playStart: Date?
    @State private var message: String?
    @State private var busy = false
    @State private var confirmDelete = false

    var body: some View {
        if let hb = library.item(id) {
            content(hb)
                .onAppear { load(hb) }
                .onDisappear { commit(); stop() }
                .confirmationDialog("Delete heartbeat?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete heartbeat", role: .destructive) {
                        stop()
                        library.delete(id)
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
        photo = hb.hasPhoto ? library.photo(hb.id) : nil
        // Let the initial values settle before onChange starts saving.
        DispatchQueue.main.async { loaded = true }
    }

    /// Saves edits.
    private func commit() {
        guard loaded, var hb = library.item(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let changed = hb.name != trimmed || hb.colorRGB != colorRGB || hb.memory != memory
        guard changed else { return }
        if !trimmed.isEmpty { hb.name = trimmed }
        hb.colorRGB = colorRGB
        hb.memory = memory
        library.upsert(hb)
    }

    private func play(_ hb: SavedHeartbeat) {
        let start = Date()
        playStart = start
        let seconds = min(20, max(5, hb.seconds))
        model.haptics.playHeartbeat(bpm: hb.bpm, seconds: seconds)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if playStart == start { playStart = nil }
        }
    }

    private func stop() {
        playStart = nil
        model.haptics.stop()
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        message = nil
        Task { await work(); busy = false }
    }
}
