import Foundation

extension AppModel {
    /// What partners see: your latest mood (from the last 24 hours, as long as their phones
    /// show it) and battery. A logged mood is shared even without Health readings.
    func myMoodShare() -> MoodShare? {
        let recent = battery.entries.last.flatMap { Date().timeIntervalSince($0.at) < 24 * 3600 ? $0 : nil }
        guard Feature.stress.isOn, let level = battery.battery ?? recent?.energy else { return nil }
        let bodyLevel = level < 20 ? "low" : "ok"
        let face = Stress.face(100 - level)
        var share = MoodShare(emoji: recent?.emoji ?? face.emoji, label: recent?.label ?? face.label,
                              battery: level, level: recent?.level ?? bodyLevel, at: recent?.at ?? Date())
        share.series = battery.series.suffix(60).map { [$0.at.timeIntervalSince1970.rounded(), ($0.hrv * 10).rounded() / 10, $0.stress.rounded()] }
        return share
    }

    /// Logs how you're feeling: shared quietly at once; if you're stressed or overwhelmed,
    /// every partner also gets a gentle notification.
    func logMood(_ entry: MoodEntry) async {
        battery.log(entry)
        await publishPresence(force: true)
        if entry.level == "stressed" || entry.level == "overwhelmed" {
            await alertPartnersForCare("is feeling \(entry.label.lowercased()) \(entry.emoji) — a gentle touch might help 💛")
        }
    }

    /// Whether the body battery is due a re-read (every 30 minutes).
    var batteryReadDue: Bool { Feature.stress.isOn && Date().timeIntervalSince(lastBatteryRead) > 30 * 60 }

    /// Re-reads the body battery every 30 minutes; a sharp drop to very low tells partners
    /// (at most every 6 hours).
    func refreshBatteryIfDue() async {
        guard batteryReadDue else { return }
        lastBatteryRead = Date()
        await battery.refresh()
        if let b = battery.bodyBattery, b < 15 {
            await alertPartnersForCare("is running on empty 🪫 — some love would help 💛")
        }
    }

    private func alertPartnersForCare(_ text: String) async {
        guard Feature.stress.isOn, UserDefaults.standard.object(forKey: "shareMood") as? Bool ?? true,
              Date().timeIntervalSince(lastCareAlert) > (text.contains("🪫") ? 6 * 3600 : 60) else { return }
        lastCareAlert = Date()
        let me = store.profile.name.isEmpty ? "Your partner" : store.profile.name
        for p in cloudPartners {
            await pushPartner(bondID: p.id, title: "💛 \(me)", body: "\(me) \(text)", group: "c", sound: "default")
        }
    }
}
