import Intents
import UserNotifications

/// Turns a partner's touch push into a rich notification before iOS shows it: decrypts the
/// touch it carries (with the bond code the app keeps in the shared Keychain), names its
/// meaning, attaches a picture of the touch, and gives it the TOUCH category — so the banner
/// shows the touch, a long press replays it, and the Apple Watch shows and plays it.
/// If anything is missing, the push is shown as it came.
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var best: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        handler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content); return
        }
        best = content
        let info = request.content.userInfo
        guard let locator = info["bl"] as? String, let b64 = info["bt"] as? String, let sealed = Data(base64Encoded: b64),
              let code = SharedBonds.codes().first(where: { BondCrypto.locator(forCode: $0) == locator }),
              let touch = BondCrypto.open(TouchMessage.self, from: sealed, code: code) else {
            contentHandler(Self.fromPartner(content)); return
        }
        content.categoryIdentifier = TouchNotification.category
        content.userInfo = info.merging(TouchNotification.userInfo(touch, bondID: code)) { $1 }
        if let label = touch.meaningLabel, touch.heartbeatBPM == nil {
            content.body = [touch.meaningEmoji, label].compactMap { $0 }.joined(separator: " ")
        }
        if let file = TouchNotification.imageFile(touch),
           let attachment = try? UNNotificationAttachment(identifier: "touch", url: file,
                                                          options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]) {
            content.attachments = [attachment]
        }
        contentHandler(Self.fromPartner(content))
    }

    /// The notification as a message from the partner (a communication notification): their
    /// name at the top, the app's icon as a badge, and what they did — "kissed you! 💋",
    /// "touched you ❤️". Siri can announce it (AirPods, CarPlay) and CarPlay shows it on the
    /// car's screen. Anything it can't do, it leaves the notification as it was.
    static func fromPartner(_ content: UNMutableNotificationContent) -> UNNotificationContent {
        let info = content.userInfo
        guard let name = info["sn"] as? String, !name.isEmpty, let locator = info["bl"] as? String else { return content }
        // "Sam kissed you! 💋" / "Sam's heartbeat" → "kissed you! 💋" / "heartbeat", then the body.
        // (A title that isn't about them, like "Us", gives way to the body.)
        var said = content.title.hasPrefix(name) ? String(content.title.dropFirst(name.count)) : ""
        if said.hasPrefix("'s ") { said = String(said.dropFirst(3)) }
        said = said.trimmingCharacters(in: .whitespaces)
        let body = content.body.trimmingCharacters(in: .whitespaces)
        if said.isEmpty { said = body } else if !body.isEmpty, !said.contains(body) {
            said += body.count <= 2 ? " \(body)" : " · \(body)"
        }
        content.body = said
        let handle = INPersonHandle(value: locator, type: .unknown)
        let sender = INPerson(personHandle: handle, nameComponents: nil, displayName: name, image: nil,
                              contactIdentifier: nil, customIdentifier: locator)
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: said,
                                         speakableGroupName: nil, conversationIdentifier: locator,
                                         serviceName: nil, sender: sender, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        return (try? content.updating(from: intent)) ?? content
    }

    override func serviceExtensionTimeWillExpire() {
        if let handler, let best { handler(best) }
    }
}
