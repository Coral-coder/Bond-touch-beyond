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
            contentHandler(content); return
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
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let handler, let best { handler(best) }
    }
}
