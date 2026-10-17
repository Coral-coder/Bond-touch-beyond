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
        guard WidgetShared.directory != nil else { return }
        var snapshot = WidgetSnapshot(partner: nil, meanings: [])
        if let partner = selectedPartner ?? partners.first {
            snapshot.partner = .init(id: partner.id, name: partner.displayName, colorRGB: partner.colorRGB,
                                     photoFile: widgetThumbnail(bondID: partner.id))
            let list = meanings(for: partner.bond)
            let ordered = list.filter { $0.favourite == true } + list.filter { $0.favourite != true }
            snapshot.meanings = ordered.prefix(WidgetShared.maxMeanings).map { m in
                WidgetSnapshot.Meaning(id: widgetID(m), label: m.label, emoji: m.emoji,
                                       colorRGB: m.colorRGB, endColorRGB: m.endColorRGB,
                                       pattern: m.pattern, generation: m.touchGeneration,
                                       serverID: m.serverID, favourite: m.favourite == true,
                                       imageFile: widgetTouchImage(m))
            }
        }
        guard WidgetShared.save(snapshot) else { return }
        var keep = Set(snapshot.meanings.compactMap(\.imageFile))
        if let photo = snapshot.partner?.photoFile { keep.insert(photo) }
        WidgetShared.removeFiles(except: keep)
        WidgetShared.reloadWidget()
    }

    /// A 160 px JPEG of the partner's photo, named by its content so a new photo reloads the
    /// widget. Re-encoded only when the photo itself changes.
    private func widgetThumbnail(bondID: String) -> String? {
        guard let photo = photo(forBond: bondID) else { return nil }
        let key = "\(bondID)#\(ObjectIdentifier(photo).hashValue)"
        if let cached = widgetPhotoCache[key], WidgetShared.fileExists(cached) { return cached }
        guard let data = Self.profileJPEG(photo, side: 160) else { return nil }
        let name = "photo-\(WidgetShared.fileKey(data.base64EncodedString())).jpg"
        WidgetShared.write(data, named: name)
        widgetPhotoCache = [key: name]
        return name
    }

    /// The touch drawn as in the app (TouchViz), as a PNG named by the touch and its colours.
    private func widgetTouchImage(_ m: TouchMeaning) -> String? {
        let name = "touch-\(WidgetShared.fileKey("\(m.touchGeneration)|\(m.colorRGB)|\(m.endColorRGB)|\(m.pattern)")).png"
        if WidgetShared.fileExists(name) { return name }
        let view = TouchViz(pattern: m.pattern, generation: m.touchGeneration, colorRGB: m.colorRGB,
                            endColorRGB: m.endColorRGB, height: 36)
            .frame(width: 220, height: 36)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return nil }
        WidgetShared.write(data, named: name)
        return name
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
