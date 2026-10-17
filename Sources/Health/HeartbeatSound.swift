import AVFoundation
import Foundation

/// The heart-monitor beep: one short tone on every beat's spike, timed to the on-screen EKG.
/// Uses the ambient audio category, so it mixes with music and respects the silent switch.
@MainActor
final class HeartbeatSound {
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var nextBeat = Date.distantFuture
    private var endAt = Date.distantPast
    private var period = 1.0

    /// Beeps on each beat at `bpm` for `seconds`, starting from `start` (the EKG's start).
    func play(bpm: Int, seconds: Double, start: Date = Date()) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if player == nil { player = try? AVAudioPlayer(data: Self.beep) }
        player?.prepareToPlay()
        period = EKG.period(bpm: bpm)
        endAt = start.addingTimeInterval(seconds)
        nextBeat = start.addingTimeInterval(EKG.spikeAt)
        let t = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()
        if now >= endAt { stop(); return }
        guard now >= nextBeat else { return }
        player?.currentTime = 0
        player?.play()
        nextBeat = nextBeat.addingTimeInterval(period)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// A 90 ms 960 Hz tone with soft edges, as a 16-bit mono WAV.
    private static let beep: Data = {
        let rate = 44_100, count = rate * 90 / 1000
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let edge = min(1, Double(i) / 220, Double(count - i) / 660)
            let v = sin(2 * .pi * 960 * t) * 0.45 * edge
            var s = Int16(v * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); u32(36 + pcm.count)
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        wav.append(contentsOf: Array("data".utf8)); u32(pcm.count)
        wav.append(pcm)
        return wav
    }()
}
