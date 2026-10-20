import Combine
import SwiftUI
import UIKit

/// The home-screen widget (see `Widget/` and `Sources/Shared`). The app keeps a snapshot in
/// the App Group — the selected partner (name, colour, photo thumbnail) and their first 10
/// meanings, favourites first, each with a rendered image of its touch — and runs the sends
/// the widget asks for: from its iOS 17 buttons (`SendMeaningIntent`, run in this process),
/// from the widget's queue, or from a `bondtouchbeyond://send` link (iOS 16).
extension AppModel {
    /// Rewrites the snapshot when partners, the selection, meanings or photos change.
    func startWidgetSync() {
        let changes: [AnyPublisher<Void, Never>] = [
            $cloudPartners.map { _ in () }.eraseToAnyPublisher(),
            $legacyPartners.map { _ in () }.eraseToAnyPublisher(),
            $selectedPartnerID.map { _ in () }.eraseToAnyPublisher(),
            $legacyMeanings.map { _ in () }.eraseToAnyPublisher(),
            $partnerPhotos.map { _ in () }.eraseToAnyPublisher(),
            store.$meanings.map { _ in () }.eraseToAnyPublisher(),
            $history.map { _ in () }.eraseToAnyPublisher(),
            together.$spaces.map { _ in () }.eraseToAnyPublisher(),
            $partnerWeather.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in Task { @MainActor in self?.writeWidgetSnapshot() } }
            .store(in: &widgetWatch)
        // The widget pings us after queueing a send (only if iOS ran its copy of the intent).
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            Task { @MainActor in await AppModel.shared?.processWidgetRequests() }
        }, WidgetShared.requestNotification as CFString, nil, .deliverImmediately)
        Task { await processWidgetRequests() }
    }

    /// The stable id a meaning has in the widget: its server id for an original-app partner
    /// (the local UUID is new on every sync), else its UUID.
    private func widgetID(_ m: TouchMeaning) -> String { m.serverID ?? m.id.uuidString }

    func writeWidgetSnapshot() {
        var snapshot = WidgetSnapshot(partner: nil, meanings: [])
        snapshot.units = Units.choice
        if let partner = selectedPartner ?? partners.first {
            snapshot.partner = .init(id: partner.id, name: partner.displayName, colorRGB: partner.colorRGB,
                                     photo: widgetThumbnail(bondID: partner.id))
            if let t = history.last(where: { $0.bondID == partner.id && !isMine($0) }) {
                snapshot.lastTouch = .init(from: partner.displayName, pattern: t.pattern, generation: t.generation,
                                           colorRGB: t.colorRGB, endColorRGB: t.endColorRGB,
                                           label: t.meaningLabel, emoji: t.meaningEmoji, bpm: t.heartbeatBPM, at: t.sentAt)
            }
            snapshot.weather = weather(for: partner)
            if Feature.stress.isOn, let m = partner.presence?.mood {
                snapshot.mood = .init(emoji: m.emoji.isEmpty ? Stress.face(m.stress).emoji : m.emoji,
                                      label: m.label.isEmpty ? Stress.face(m.stress).label : m.label,
                                      energy: m.battery, stress: m.stress, at: m.at)
            }
            let space = together.space(partner.id)
            let next = space.dates.filter { !$0.deleted }.min { $0.daysUntil() < $1.daysUntil() }
            if space.togetherSince != nil || next != nil {
                snapshot.together = .init(since: space.togetherSince, nextTitle: next?.title, nextDate: next?.next(),
                                          nextIsBirthday: next?.kind == .birthday)
            }
            let list = meanings(for: partner.bond)
            let ordered = list.filter { $0.favourite == true } + list.filter { $0.favourite != true }
            snapshot.meanings = ordered.prefix(WidgetShared.maxMeanings).map { m in
                WidgetSnapshot.Meaning(id: widgetID(m), label: m.label, emoji: m.emoji,
                                       colorRGB: m.colorRGB, endColorRGB: m.endColorRGB,
                                       pattern: m.pattern, generation: m.touchGeneration,
                                       serverID: m.serverID, favourite: m.favourite == true)
            }
        }
        guard WidgetShared.save(snapshot) else { return }
        WidgetShared.reloadWidget()
    }

    /// A small JPEG of the partner's photo for the widgets, re-encoded only when it changes.
    private func widgetThumbnail(bondID: String) -> Data? {
        guard let photo = photo(forBond: bondID) else { return nil }
        let key = "\(bondID)#\(ObjectIdentifier(photo).hashValue)"
        if let cached = widgetPhotoData[key] { return cached }
        guard let data = Self.profileJPEG(photo, side: 96) else { return nil }
        widgetPhotoData = [key: data]
        return data
    }

    // MARK: - Sending

    /// A widget button's send, run by `SendMeaningIntent` in this process (possibly with the
    /// app just launched in the background for it).
    static func runWidgetSend(_ request: WidgetSendRequest) async {
        var waited = 0
        while AppModel.shared == nil, waited < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        guard let model = AppModel.shared else {
            WidgetShared.setStatus(.failed, for: request.meaningID)
            WidgetShared.reloadWidget()
            return
        }
        await model.sendFromWidget(request)
    }

    /// Sends a meaning the widget asked for and reports Sending, then Sent / Failed, back to
    /// it. Finishes starting up first if the app was launched just for this.
    @discardableResult
    func sendFromWidget(_ request: WidgetSendRequest) async -> Bool {
        WidgetShared.setStatus(.sending, for: request.meaningID)
        WidgetShared.reloadWidget()
        if !ready { await bootstrap() }
        // Original-app partners only appear after the first sync with their backend.
        if !partners.contains(where: { $0.id == request.bondID }), legacySignedIn { await legacySyncOnce() }
        var sent = false
        if let partner = partners.first(where: { $0.id == request.bondID }),
           let meaning = widgetMeaning(request.meaningID, bond: partner.bond) {
            NetLog.shared.log(.send, "Widget: send \"\(meaning.label)\" → \(partner.displayName)")
            sent = await sendMeaning(meaning, toBondID: partner.id)
        } else {
            NetLog.shared.log(.fail, "Widget: that partner or meaning is no longer here")
        }
        WidgetShared.setStatus(sent ? .sent : .failed, for: request.meaningID)
        WidgetShared.reloadWidget()
        return sent
    }

    /// The meaning by its widget id: the loaded one, else the copy in the snapshot (the
    /// original backend's meanings load only after the first sync).
    private func widgetMeaning(_ id: String, bond: Bond) -> TouchMeaning? {
        if let live = meanings(for: bond).first(where: { widgetID($0) == id }) { return live }
        guard let snapshot = WidgetShared.loadSnapshot(), snapshot.partner?.id == bond.id,
              let m = snapshot.meanings.first(where: { $0.id == id }) else { return nil }
        var meaning = TouchMeaning(id: UUID(uuidString: m.id) ?? UUID(), label: m.label, emoji: m.emoji,
                                   colorRGB: m.colorRGB, endColorRGB: m.endColorRGB, pattern: m.pattern,
                                   serverID: m.serverID, generation: m.generation)
        meaning.favourite = m.favourite
        return meaning
    }

    /// Sends what the widget queued (when iOS ran its copy of the intent), dropping — and
    /// showing failed — anything too old to still be wanted.
    func processWidgetRequests() async {
        for request in WidgetShared.takeRequests() {
            if Date().timeIntervalSince(request.at) > WidgetShared.requestLifetime {
                WidgetShared.setStatus(.failed, for: request.meaningID)
                WidgetShared.reloadWidget()
                continue
            }
            await sendFromWidget(request)
        }
    }
}
