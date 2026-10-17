import PhotosUI
import SwiftUI

/// Record a heartbeat: a fingertip over the camera and flash for 15 seconds (or the latest
/// Apple Watch reading), then name it, give it a colour and a memory, and keep it.
struct RecordHeartbeatView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var recorder = PulseRecorder()
    @State private var recorded: Recorded?
    @State private var watchBusy = false
    @State private var watchError: String?

    struct Recorded: Equatable {
        let intervals: [Int]
        let source: SavedHeartbeat.Source
        let date: Date
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let recorded {
                    CustomizeHeartbeatView(recorded: recorded) {
                        self.recorded = nil
                    }
                } else {
                    recording
                }
            }
            .padding(20)
        }
        .navigationTitle("Record heartbeat")
        .onDisappear { recorder.stop() }
        .onChange(of: recorder.phase) { phase in
            if case .done(let intervals) = phase {
                recorded = Recorded(intervals: intervals, source: .camera, date: Date())
            }
        }
    }

    @ViewBuilder private var recording: some View {
        switch recorder.phase {
        case .waitingForFinger, .recording:
            live
        default:
            instructions
        }
    }

    private var instructions: some View {
        VStack(spacing: 18) {
            HeartGlyph(colorRGB: EKG.colorRGB, size: 90, bpm: 64).padding(.top, 10)
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Capturing your heartbeat").font(Theme.font(18, .heavy)).foregroundStyle(.white)
                    Text("We do so by detecting your blood flow using your phone’s flashlight. Just place your finger over it and over your camera at the same time, and stay still for 15 seconds.")
                        .font(.footnote).foregroundStyle(Theme.subtitle)
                }
            }
            if case .failed(let message) = recorder.phase {
                Text(message).font(.footnote).foregroundStyle(Theme.amber).multilineTextAlignment(.center)
            }
            if recorder.phase == .denied {
                VStack(spacing: 8) {
                    Text("Camera permission required to record your heart beat.")
                        .font(.footnote).foregroundStyle(Theme.amber)
                    Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                        .font(Theme.font(15, .bold)).foregroundStyle(Theme.accent)
                }
            }
            Button("Start recording") { Task { await recorder.start() } }
                .buttonStyle(AccentButtonStyle())
            Button {
                Task { await fromWatch() }
            } label: {
                if watchBusy { ProgressView().tint(.white) } else { Label("Use Apple Watch instead", systemImage: "applewatch") }
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(watchBusy)
            if let watchError {
                Text(watchError).font(.footnote).foregroundStyle(Theme.amber).multilineTextAlignment(.center)
            }
            Text("Apple Watch: its latest beat-to-beat recording from Health (taken with heart-rate-variability readings or an ECG), or else your latest heart rate as an even rhythm.")
                .font(.caption).foregroundStyle(Theme.subtitle).multilineTextAlignment(.center)
        }
    }

    private var live: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 8)
                Circle().trim(from: 0, to: recorder.progress)
                    .stroke(Theme.pink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: recorder.progress)
                VStack(spacing: 4) {
                    HeartGlyph(colorRGB: EKG.colorRGB, size: 64, bpm: recorder.liveBPM)
                    Text("\(Int(recorder.progress * 100)) %").font(Theme.font(15, .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 200, height: 200)

            Text(recorder.phase == .recording ? "Recording…" : "Place your finger")
                .font(Theme.font(20, .heavy)).foregroundStyle(.white)
            Text(recorder.phase == .recording
                 ? "Keep covering your camera with your finger, keep it still and press lightly."
                 : "Cover the camera and the flash on the back of your phone with your fingertip.")
                .font(.footnote).foregroundStyle(Theme.subtitle).multilineTextAlignment(.center)

            if recorder.phase == .recording {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(recorder.liveBPM.map { "\($0)" } ?? "--")
                                .font(Theme.font(30, .heavy)).foregroundStyle(.white).monospacedDigit()
                            Text("BPM").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                            Spacer()
                            Text("\(recorder.beats) beats").font(.caption).foregroundStyle(Theme.subtitle)
                        }
                        EKGView(bpm: recorder.liveBPM ?? 70, colorRGB: EKG.colorRGB, start: recorder.startedAt)
                            .frame(height: 80)
                        PulseWave(values: recorder.wave).frame(height: 44)
                    }
                }
            }
            Button("Cancel") { recorder.stop() }
                .buttonStyle(GlassButtonStyle(height: 44))
        }
    }

    private func fromWatch() async {
        watchBusy = true
        watchError = nil
        if let r = await WatchHeartbeat.latest(heart: model.heart) {
            recorded = Recorded(intervals: r.intervals, source: r.beatToBeat ? .watch : .heartRate, date: r.date)
        } else {
            watchError = "No heart data from Apple Watch. Wear it (or take an ECG / let it measure heart-rate variability), allow Health access, then try again."
        }
        watchBusy = false
    }
}

/// The raw pulse from the camera, as a line.
struct PulseWave: View {
    let values: [Double]
    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            var p = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                 y: size.height / 2 - CGFloat(v) * size.height * 0.45)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(Theme.subtitle.opacity(0.7)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

/// Name, colour and memory for a heartbeat just recorded, then save (and wear).
struct CustomizeHeartbeatView: View {
    @EnvironmentObject var model: AppModel
    let recorded: RecordHeartbeatView.Recorded
    var onRecordAgain: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorRGB = EKG.colorRGB
    @State private var memory = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var previewStart: Date?
    @State private var sound = HeartbeatSound()
    @State private var saved: SavedHeartbeat?
    @State private var message: String?
    @State private var busy = false

    private var draft: SavedHeartbeat {
        SavedHeartbeat(name: name.trimmingCharacters(in: .whitespaces), colorRGB: colorRGB, memory: memory,
                       intervals: recorded.intervals, createdAt: recorded.date, isSelf: true, source: recorded.source)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(saved == nil ? "Heartbeat recorded!" : "Heartbeat created")
                .font(Theme.font(22, .heavy)).foregroundStyle(.white)
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HeartGlyph(colorRGB: colorRGB, size: 30, bpm: draft.bpm)
                        Text("\(draft.bpm) BPM").font(Theme.font(20, .heavy)).foregroundStyle(.white)
                        Spacer()
                        Text("\(recorded.intervals.count) beats · \(Int(draft.seconds.rounded())) s")
                            .font(.caption).foregroundStyle(Theme.subtitle)
                    }
                    EKGView(bpm: draft.bpm, colorRGB: colorRGB, start: previewStart).frame(height: 70)
                    Button(previewStart == nil ? "Play" : "Stop") { togglePreview() }
                        .buttonStyle(GlassButtonStyle(height: 38))
                    if recorded.source == .heartRate {
                        Text("From your latest heart rate — an even rhythm, not beat-to-beat.")
                            .font(.caption).foregroundStyle(Theme.subtitle)
                    }
                }
            }

            if let saved {
                savedActions(saved)
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Who's in your heart?").font(Theme.font(16, .bold)).foregroundStyle(.white)
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text("Choose a color for your heartbeat. Don't worry, you can change it later!")
                            .font(.caption).foregroundStyle(Theme.subtitle)
                        HeartColorRow(colorRGB: $colorRGB)
                        Text("Make it personal").font(Theme.font(16, .bold)).foregroundStyle(.white)
                        TextField("A memory (optional)", text: $memory, axis: .vertical)
                            .lineLimit(2...5)
                            .textFieldStyle(.roundedBorder)
                        HeartPhotoPicker(item: $photoItem, image: $photo)
                    }
                }
                Button("Save to library") { save() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Record again") { stopPreview(); onRecordAgain() }
                    .buttonStyle(GlassButtonStyle(height: 44))
            }
        }
        .onDisappear { stopPreview() }
    }

    @ViewBuilder private func savedActions(_ hb: SavedHeartbeat) -> some View {
        VStack(spacing: 12) {
            if let message { Text(message).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center) }
            Button {
                busy = true
                Task {
                    do {
                        try await model.wearHeartbeat(hb)
                        message = "Heartbeat worn successfully!"
                    } catch { message = error.localizedDescription }
                    busy = false
                }
            } label: {
                if busy { ProgressView().tint(Theme.onAccent) } else { Text("Wear your heartbeat") }
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(busy || !model.pendant.state.isUsable)
            if !model.pendant.state.isUsable {
                Text("Connect your Heart to wear it — or wear it later from the library.")
                    .font(.caption).foregroundStyle(Theme.subtitle)
            }
            Button("Done") { dismiss() }
                .buttonStyle(GlassButtonStyle(height: 44))
        }
    }

    private func save() {
        stopPreview()
        let hb = draft
        model.heartLibrary.upsert(hb)
        if let photo { model.heartLibrary.setPhoto(photo, for: hb.id) }
        saved = model.heartLibrary.item(hb.id) ?? hb
    }

    private func togglePreview() {
        if previewStart != nil { stopPreview(); return }
        let start = Date()
        previewStart = start
        let seconds = min(20, max(5, draft.seconds))
        sound.play(bpm: draft.bpm, seconds: seconds, start: start)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if previewStart == start { previewStart = nil }
        }
    }

    private func stopPreview() {
        previewStart = nil
        sound.stop()
    }
}

/// The colour choices for a heartbeat, plus a free colour picker.
struct HeartColorRow: View {
    @Binding var colorRGB: Int
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(HeartPalette.colors, id: \.self) { c in
                    Button { colorRGB = c } label: {
                        Circle().fill(Color(rgbInt: c)).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.white, lineWidth: colorRGB == c ? 3 : 0))
                            .shadow(color: Color(rgbInt: c).opacity(0.6), radius: colorRGB == c ? 6 : 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour")
                }
                ColorPicker("", selection: Binding(get: { Color(rgbInt: colorRGB) }, set: { colorRGB = $0.rgbInt }),
                            supportsOpacity: false)
                    .labelsHidden()
            }
            .padding(.vertical, 4)
        }
    }
}

/// Picks a memory photo, shown in a heart.
struct HeartPhotoPicker: View {
    @Binding var item: PhotosPickerItem?
    @Binding var image: UIImage?
    var body: some View {
        HStack(spacing: 12) {
            if let image {
                HeartPhoto(image: image).frame(width: 64, height: 64)
            }
            PhotosPicker(selection: $item, matching: .images) {
                Label(image == nil ? "Upload a memory" : "Change photo", systemImage: "photo")
                    .font(Theme.font(15, .bold)).foregroundStyle(Theme.accent)
            }
            if image != nil {
                Button("Remove") { image = nil; item = nil }
                    .font(Theme.font(14, .bold)).foregroundStyle(Theme.danger)
            }
        }
        .onChange(of: item) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    image = ui
                }
            }
        }
    }
}

/// A memory photo clipped to a heart.
struct HeartPhoto: View {
    let image: UIImage
    var body: some View {
        Color.clear
            .overlay(Image(uiImage: image).resizable().scaledToFill())
            .clipped()
            .mask(Image(systemName: "heart.fill").resizable().scaledToFit())
            .accessibilityLabel("Memory photo")
    }
}
