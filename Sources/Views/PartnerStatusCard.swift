import SwiftUI

/// The live status panel on a partner's card: their phone's battery, their bracelet
/// (connected, battery, last connected), when their app last checked in, how fast they're
/// moving, and a ticking timer since their last location update. Everything comes from the
/// partner's encrypted presence snapshot; times re-render every second.
struct PartnerStatusCard: View {
    let partner: Partner

    private var p: PresenceInfo? { partner.presence }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 0) {
                Text("STATUS").font(Theme.font(11, .heavy)).tracking(1.2).foregroundStyle(Theme.subtitle)
                    .padding(.bottom, 6)
                row(icon: phoneIcon, tint: phoneTint, title: "Phone", value: phoneText)
                divider
                row(icon: braceletIcon, tint: braceletTint, title: "Bracelet", value: braceletText(now))
                divider
                row(icon: "clock.fill", tint: partner.online ? Theme.lime : Theme.subtitle,
                    title: "Last check-in", value: checkInText(now))
                if let movement = movementText(now) {
                    divider
                    row(icon: movementIcon(now), tint: Theme.accent, title: "Moving", value: movement)
                }
                divider
                row(icon: "location.fill", tint: p?.locationAt == nil ? Theme.subtitle : Theme.accent,
                    title: "Location update", value: locationText(now))
            }
            .padding(16)
            .glass(cornerRadius: 22)
        }
    }

    // MARK: - Rows

    private var divider: some View { Divider().overlay(Theme.ink.opacity(0.12)) }

    private func row(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 26)
            Text(title).font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
            Spacer(minLength: 8)
            Text(value).font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
                .multilineTextAlignment(.trailing).monospacedDigit()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Phone battery

    private var phoneText: String {
        guard let level = p?.phoneBattery else { return "—" }
        let percent = "\(Int((level * 100).rounded()))%"
        return p?.phoneCharging == true ? "\(percent) · charging" : percent
    }

    private var phoneIcon: String {
        guard let level = p?.phoneBattery else { return "battery.0" }
        if p?.phoneCharging == true { return "battery.100.bolt" }
        return Self.batterySymbol(level)
    }

    private var phoneTint: Color {
        guard let level = p?.phoneBattery else { return Theme.subtitle }
        if p?.phoneCharging == true { return Theme.lime }
        return level <= 0.2 ? Theme.danger : Theme.title
    }

    // MARK: - Bracelet

    private var braceletConnected: Bool { p?.bracelet == true }

    private func braceletText(_ now: Date) -> String {
        let battery = p?.braceletBattery.map { "\($0)%" }
        if braceletConnected { return ["Connected", battery].compactMap { $0 }.joined(separator: " · ") }
        guard let last = p?.braceletLastConnected else { return p?.bracelet == nil ? "—" : "Not connected" }
        return "Last connected \(Self.elapsed(from: last, to: now)) ago"
    }

    private var braceletIcon: String {
        braceletConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
    }

    private var braceletTint: Color {
        guard braceletConnected else { return Theme.subtitle }
        if let battery = p?.braceletBattery, battery <= 20 { return Theme.danger }
        return Theme.lime
    }

    // MARK: - Check-in

    private func checkInText(_ now: Date) -> String {
        guard let seen = partner.lastSeen else { return partner.online ? "Online" : "—" }
        let ago = now.timeIntervalSince(seen)
        if partner.online, ago < 120 { return "Online now" }
        return "\(Self.elapsed(from: seen, to: now)) ago"
    }

    // MARK: - Movement

    /// Speed from a location fix in the last 5 minutes; nil when there's no fresh location.
    private func freshSpeed(_ now: Date) -> Double? {
        guard let at = p?.locationAt, now.timeIntervalSince(at) < 300, let speed = p?.speed, speed >= 0 else { return nil }
        return speed
    }

    private func movementText(_ now: Date) -> String? {
        guard let speed = freshSpeed(now) else { return nil }
        if speed < 0.5 { return "Not moving" }
        return "\(Self.activity(speed)) · \(Self.speedFormatter.string(from: Measurement(value: speed, unit: UnitSpeed.metersPerSecond)))"
    }

    private func movementIcon(_ now: Date) -> String {
        guard let speed = freshSpeed(now) else { return "figure.stand" }
        switch speed {
        case ..<0.5: return "figure.stand"
        case ..<2.5: return "figure.walk"
        case ..<7: return "figure.run"
        default: return "car.fill"
        }
    }

    private static func activity(_ speed: Double) -> String {
        switch speed {
        case ..<2.5: return "Walking"
        case ..<7: return "Running / cycling"
        default: return "Driving"
        }
    }

    // MARK: - Location timer

    private func locationText(_ now: Date) -> String {
        guard let at = p?.locationAt else { return "None yet" }
        return "\(Self.elapsed(from: at, to: now)) ago"
    }

    // MARK: - Formatting

    /// A compact live duration: "12s", "2m 14s", "1h 3m", "2d 4h".
    static func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        switch s {
        case ..<60: return "\(s)s"
        case ..<3600: return "\(s / 60)m \(s % 60)s"
        case ..<86_400: return "\(s / 3600)h \((s % 3600) / 60)m"
        default: return "\(s / 86_400)d \((s % 86_400) / 3600)h"
        }
    }

    private static func batterySymbol(_ level: Double) -> String {
        switch level {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }

    /// Speed in the user's local unit (mph or km/h), no decimals.
    private static let speedFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitStyle = .medium
        f.numberFormatter.maximumFractionDigits = 0
        return f
    }()
}
