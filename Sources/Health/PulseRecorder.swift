import AVFoundation
import Foundation
import HealthKit

/// Records a heartbeat with the camera, as the original Bond Heart app does: a fingertip
/// over the back camera and the flash (torch on), and the colour of each frame follows the
/// blood pulsing through it (photoplethysmography). The original averages the hue of 600
/// frames (~20 s); this averages the red channel over ~15 s, finds each pulse and keeps the
/// intervals between them — the same thing the pendant beats (`SavedHeartbeat.intervals`).
@MainActor
final class PulseRecorder: ObservableObject {
    enum Phase: Equatable {
        case idle
        case denied
        /// Camera running; waiting for a fingertip to cover the lens.
        case waitingForFinger
        case recording
        case done([Int])
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// 0…1 through the recording.
    @Published private(set) var progress: Double = 0
    @Published private(set) var liveBPM: Int?
    /// Intervals found so far.
    @Published private(set) var beats = 0
    /// The last ~3 s of the pulse signal, -1…1, for the live trace.
    @Published private(set) var wave: [Double] = []
    /// When the recording (finger on) started — the live EKG's start.
    @Published private(set) var startedAt = Date()

    /// Seconds of steady signal to record.
    let duration: Double = 15
    /// Seconds after the finger goes on before samples count (exposure settles).
    private let warmup: Double = 1.5

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "BondTouchBeyond.pulse")
    private let sink = FrameSink()
    private var device: AVCaptureDevice?
    private var configured = false

    // Signal state.
    private var times: [Double] = []
    private var raw: [Double] = []
    private var highpass: [Double] = []
    private var filtered: [Double] = []
    private var coveredSince: Double?
    private var uncoveredSince: Double?
    private var lastPeak: Double?
    private var intervals: [Int] = []
    private var useGreen: Bool?
    private var lastT: Double = 0

    deinit {
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    func start() async {
        reset()
        guard await AVCaptureDevice.requestAccess(for: .video) else { phase = .denied; return }
        if !configured {
            guard configure() else { phase = .failed("The camera isn't available."); return }
        }
        phase = .waitingForFinger
        sink.onFrame = { [weak self] t, r, g, b in
            Task { @MainActor in self?.ingest(t: t, r: r, g: g, b: b) }
        }
        let session = self.session
        queue.async {
            if !session.isRunning { session.startRunning() }
            Task { @MainActor [weak self] in self?.torch(true) }
        }
    }

    func stop() {
        sink.onFrame = nil
        torch(false)
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
        if phase == .recording || phase == .waitingForFinger { phase = .idle }
    }

    private func reset() {
        times = []; raw = []; highpass = []; filtered = []; wave = []
        coveredSince = nil; uncoveredSince = nil; lastPeak = nil
        intervals = []; useGreen = nil; lastT = 0
        progress = 0; liveBPM = nil; beats = 0
    }

    private func configure() -> Bool {
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam) else { return false }
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .low
        guard session.canAddInput(input) else { session.commitConfiguration(); return false }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(sink, queue: queue)
        guard session.canAddOutput(out) else { session.commitConfiguration(); return false }
        session.addOutput(out)
        session.commitConfiguration()
        // A steady 30 fps (an unsupported rate would raise, so check first).
        let fps30 = cam.activeFormat.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && 30 <= $0.maxFrameRate }
        if fps30, (try? cam.lockForConfiguration()) != nil {
            cam.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            cam.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            cam.unlockForConfiguration()
        }
        device = cam
        configured = true
        return true
    }

    private func torch(_ on: Bool) {
        guard let cam = device, cam.hasTorch else { return }
        do {
            try cam.lockForConfiguration()
            if on { try cam.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { cam.torchMode = .off }
            cam.unlockForConfiguration()
        } catch {
            NetLog.shared.log(.fail, "Heart recording: torch", error.localizedDescription)
        }
    }

    // MARK: - Signal

    private func ingest(t: Double, r: Double, g: Double, b: Double) {
        guard phase == .waitingForFinger || phase == .recording, t > lastT else { return }
        lastT = t
        // A fingertip over the lens with the torch on fills the frame with bright red.
        let covered = r > 80 && r > g * 1.8 && r > b * 1.8
        if !covered {
            if uncoveredSince == nil { uncoveredSince = t }
            // More than half a second off the lens: start over.
            if let u = uncoveredSince, t - u > 0.5, coveredSince != nil {
                reset()
                phase = .waitingForFinger
            }
            return
        }
        uncoveredSince = nil
        if coveredSince == nil {
            coveredSince = t
            phase = .recording
            startedAt = Date()
        }
        guard let since = coveredSince else { return }
        let elapsed = t - since
        progress = min(1, max(0, (elapsed - warmup) / duration))
        guard elapsed >= warmup else { return }

        // Red saturates on some phones with the torch on; the green channel then carries
        // the pulse. Chosen once, so the signal doesn't jump.
        if useGreen == nil { useGreen = r > 245 }
        let v = (useGreen ?? false) ? g : r
        times.append(t)
        raw.append(v)

        // Detrend (minus the mean of the last second), smooth (mean of 4 ≈ 130 ms), and
        // invert: the frame darkens as blood arrives, so a pulse is a peak of -brightness.
        let n = raw.count
        let base = raw.suffix(30).reduce(0, +) / Double(min(30, n))
        highpass.append(v - base)
        let last4 = highpass.suffix(4)
        filtered.append(-last4.reduce(0, +) / Double(last4.count))
        detectPeak()

        let recent = Array(filtered.suffix(90))
        let peak = max(0.0001, recent.map { abs($0) }.max() ?? 1)
        wave = recent.map { $0 / peak }

        if elapsed - warmup >= duration { finish() }
    }

    /// A pulse: a local maximum (over ±3 frames ≈ 100 ms) above 40 % of the recent
    /// amplitude, at least 300 ms after the last one (≤ 200 BPM).
    private func detectPeak() {
        let n = filtered.count
        guard n >= 7 else { return }
        let k = n - 4
        let x = filtered[k]
        guard x > 0 else { return }
        for j in (k - 3)...(k + 3) where j != k && filtered[j] > x { return }
        let amp = filtered.suffix(60).map { abs($0) }.max() ?? 0
        guard x > 0.4 * amp else { return }
        let t = times[k]
        if let last = lastPeak {
            let ms = Int(((t - last) * 1000).rounded())
            if ms < 300 { return }
            if ms <= 1600 {
                let med = median(intervals.suffix(8))
                if med == nil || (Double(ms) > 0.6 * med! && Double(ms) < 1.6 * med!) {
                    intervals.append(ms)
                    beats = intervals.count
                    if let m = median(intervals.suffix(8)) { liveBPM = Int((60_000 / m).rounded()) }
                }
            }
        }
        lastPeak = t
    }

    private func median<C: Collection>(_ values: C) -> Double? where C.Element == Int {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? Double(s[s.count / 2]) : Double(s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private func finish() {
        stop()
        // Drop outliers more than 25 % off the median (a missed or doubled beat).
        let clean: [Int]
        if let m = median(intervals) { clean = intervals.filter { abs(Double($0) - m) <= 0.25 * m } } else { clean = [] }
        if clean.count >= 8 {
            phase = .done(clean)
        } else {
            phase = .failed("Uh-oh! Trouble recording your heartbeat. Cover the camera and the flash with your fingertip, press lightly and keep still.")
        }
    }
}

/// Averages each camera frame's colour (centre half, every 4th pixel). Runs on the capture
/// queue.
private final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((Double, Double, Double, Double) -> Void)?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let onFrame, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var r = 0, g = 0, b = 0, n = 0
        var y = h / 4
        while y < h * 3 / 4 {
            let row = p + y * rowBytes
            var x = w / 4
            while x < w * 3 / 4 {
                let px = row + x * 4          // BGRA
                b += Int(px[0]); g += Int(px[1]); r += Int(px[2])
                n += 1
                x += 4
            }
            y += 4
        }
        guard n > 0 else { return }
        onFrame(t, Double(r) / Double(n), Double(g) / Double(n), Double(b) / Double(n))
    }
}

/// A heartbeat from Apple Watch, the alternative to the camera: the latest beat-to-beat
/// series the Watch recorded (Health's heartbeat series, saved with heart-rate-variability
/// readings and ECGs), or — without one — the latest heart rate as an even rhythm.
enum WatchHeartbeat {
    struct Result {
        let intervals: [Int]
        let date: Date
        /// True when the intervals are real beat-to-beat timings, not an even rhythm.
        let beatToBeat: Bool
    }

    static func latest(heart: HeartRateService) async -> Result? {
        if let series = await latestSeries() { return series }
        await heart.requestAuthorization()
        guard let bpm = await heart.latestBPM(), bpm > 0 else { return nil }
        let ms = 60_000 / bpm
        return Result(intervals: Array(repeating: ms, count: 20), date: Date(), beatToBeat: false)
    }

    private static func latestSeries() async -> Result? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HKHealthStore()
        let type = HKSeriesType.heartbeat()
        guard let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        do { try await store.requestAuthorization(toShare: [], read: [type, hr]) } catch { return nil }
        let sample: HKHeartbeatSeriesSample? = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKHeartbeatSeriesSample)
            }
            store.execute(q)
        }
        guard let sample else { return nil }
        final class Collected { var beats: [(TimeInterval, Bool)] = []; var finished = false }
        let beats: [(TimeInterval, Bool)] = await withCheckedContinuation { cont in
            let box = Collected()
            let q = HKHeartbeatSeriesQuery(heartbeatSeries: sample) { _, sinceStart, precededByGap, done, error in
                guard !box.finished else { return }
                if error == nil { box.beats.append((sinceStart, precededByGap)) }
                if done || error != nil {
                    box.finished = true
                    cont.resume(returning: box.beats)
                }
            }
            store.execute(q)
        }
        var intervals: [Int] = []
        for i in beats.indices.dropFirst() where !beats[i].1 {
            let ms = Int(((beats[i].0 - beats[i - 1].0) * 1000).rounded())
            if (300...1600).contains(ms) { intervals.append(ms) }
        }
        guard intervals.count >= 8 else { return nil }
        return Result(intervals: intervals, date: sample.endDate, beatToBeat: true)
    }
}
