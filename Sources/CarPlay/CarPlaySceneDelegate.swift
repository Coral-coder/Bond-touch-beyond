import CarPlay
import Combine
import UIKit

/// Tells the CarPlay screen that what it lists has changed (a kiss or a touch came in).
enum CarPlayActivity {
    static let didChange = Notification.Name("CarPlayActivityDidChange")
    static func changed() { NotificationCenter.default.post(name: didChange, object: nil) }
}

/// Bond Touch Beyond on CarPlay (a communication app): the kisses, touches and heartbeats your
/// partners sent, newest first, and your partners. Tap one to kiss back, send a touch or send
/// your heartbeat — all one tap, nothing to read while driving. The notifications themselves
/// come through as communication notifications, which CarPlay shows and Siri reads out.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interface: CPInterfaceController?
    private var list: CPListTemplate?
    private var watchers: Set<AnyCancellable> = []

    private var model: AppModel? { AppModel.shared }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        let list = CPListTemplate(title: "Bond Touch", sections: sections())
        list.emptyViewTitleVariants = ["Nothing yet"]
        list.emptyViewSubtitleVariants = ["Kisses and touches from your partners show up here."]
        self.list = list
        interfaceController.setRootTemplate(list, animated: false, completion: nil)

        NotificationCenter.default.publisher(for: CarPlayActivity.didChange)
            .merge(with: model?.$history.map { _ in Notification(name: CarPlayActivity.didChange) }.eraseToAnyPublisher()
                   ?? Empty<Notification, Never>().eraseToAnyPublisher())
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &watchers)
        if let model, !model.ready { Task { await model.bootstrap(); self.refresh() } }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        interface = nil
        list = nil
        watchers.removeAll()
    }

    private func refresh() { list?.updateSections(sections()) }

    // MARK: - The list

    private struct Moment {
        let bondID: String, name: String, line: String, at: Date
    }

    private func moments() -> [Moment] {
        guard let model else { return [] }
        let names = Dictionary(model.partners.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        var out = model.receivedKisses.prefix(15).map { Moment(bondID: $0.bondID, name: $0.name, line: "kissed you 💋", at: $0.at) }
        for t in model.history.suffix(60) where !model.isMine(t) {
            let line: String
            if let bpm = t.heartbeatBPM { line = "💓 heartbeat · \(bpm) BPM" }
            else if let label = t.meaningLabel { line = "touched you · \([t.meaningEmoji, label].compactMap { $0 }.joined(separator: " "))" }
            else { line = "sent you a touch ❤️" }
            out.append(Moment(bondID: t.bondID, name: names[t.bondID] ?? "Partner", line: line, at: t.sentAt))
        }
        return Array(out.sorted { $0.at > $1.at }.prefix(12))
    }

    private func sections() -> [CPListSection] {
        guard let model else { return [] }
        let recent = moments().map { m -> CPListItem in
            let ago = m.at.formatted(.relative(presentation: .named))
            let item = CPListItem(text: m.name, detailText: "\(m.line) · \(ago)", image: photo(m.bondID))
            item.handler = { [weak self] _, done in self?.answer(bondID: m.bondID, name: m.name, line: m.line); done() }
            return item
        }
        let partners = model.partners.map { p -> CPListItem in
            let item = CPListItem(text: p.displayName, detailText: "Send a kiss or a touch", image: photo(p.id))
            item.handler = { [weak self] _, done in self?.answer(bondID: p.id, name: p.displayName, line: nil); done() }
            return item
        }
        var out: [CPListSection] = []
        if !recent.isEmpty { out.append(CPListSection(items: recent, header: "Recent", sectionIndexTitle: nil)) }
        if !partners.isEmpty { out.append(CPListSection(items: partners, header: "Your partners", sectionIndexTitle: nil)) }
        return out
    }

    private func photo(_ bondID: String) -> UIImage? {
        guard let image = model?.photo(forBond: bondID) else { return nil }
        let size = CGSize(width: 88, height: 88)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
    }

    // MARK: - Answering

    /// One screen, three big buttons: Kiss back, Send a touch, Send my heartbeat.
    private func answer(bondID: String, name: String, line: String?) {
        let items = [CPInformationItem(title: name, detail: line ?? "Thinking of \(name)?")]
        func button(_ title: String, _ done: String, _ send: @escaping (AppModel) async -> Bool) -> CPTextButton {
            CPTextButton(title: title, textStyle: .normal) { [weak self] _ in
                guard let self, let model = self.model else { return }
                Task { @MainActor in
                    let ok = await send(model)
                    self.interface?.popToRootTemplate(animated: true, completion: nil)
                    let alert = CPAlertTemplate(titleVariants: [ok ? done : "Couldn't send. Try again in a moment."],
                                                actions: [CPAlertAction(title: "OK", style: .default) { [weak self] _ in
                                                    self?.interface?.dismissTemplate(animated: true, completion: nil)
                                                }])
                    self.interface?.presentTemplate(alert, animated: true, completion: nil)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if self.interface?.presentedTemplate === alert { self.interface?.dismissTemplate(animated: true, completion: nil) }
                }
            }
        }
        let template = CPInformationTemplate(title: name, layout: .leading, items: items, actions: [
            button("💋 Kiss back", "Kiss sent to \(name) 💋") { await $0.sendKiss(toBondID: bondID) },
            button("❤️ Send a touch", "Touch sent to \(name) ❤️") { await $0.sendQuickTouch(toBondID: bondID) },
            button("💓 My heartbeat", "Heartbeat sent to \(name) 💓") { model in
                model.selectedPartnerID = bondID
                return await model.sendHeartbeat() != nil
            },
        ])
        interface?.pushTemplate(template, animated: true, completion: nil)
    }
}
