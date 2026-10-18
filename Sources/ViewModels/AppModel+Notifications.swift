import Foundation
import UIKit
import UserNotifications

/// The phone's own rich touch notification — the same one a partner's push becomes — for a
/// touch that reached the app without a push showing it: picked up from iCloud, or from a
/// partner on the original app. It mirrors to the Apple Watch, which draws the touch and
/// plays its rhythm. Plays the app's chime and vibrates — never the default beep.
extension AppModel {
    func notifyTouch(_ touch: TouchMessage) async {
        guard let partner = partners.first(where: { $0.id == touch.bondID }) else { return }
        let center = UNUserNotificationCenter.current()
        // Same identifier as the partner's push for this bond (its collapse id), so if that
        // push's notification is already showing for this touch, this doesn't add a second.
        let locator = partner.bond.legacy ? nil : BondCrypto.locator(forCode: partner.id)
        let id = locator.map { "t-\($0.prefix(16))" } ?? "l-\(touch.id.uuidString)"
        let delivered = await center.deliveredNotifications()
        if delivered.contains(where: { n in
            n.request.identifier == id && abs(n.date.timeIntervalSince(touch.sentAt)) < 120
        }) { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = TouchNotification.category
        if let bpm = touch.heartbeatBPM {
            content.title = "\(partner.displayName)'s heartbeat"
            content.body = "💓 \(bpm) BPM"
        } else if let label = touch.meaningLabel {
            content.title = "\(partner.displayName) touched you"
            content.body = [touch.meaningEmoji, label].compactMap { $0 }.joined(separator: " ")
        } else {
            content.title = "\(partner.displayName) touched you"
            content.body = "❤️"
        }
        var info = TouchNotification.userInfo(touch, bondID: partner.id)
        if let locator { info["bl"] = locator }
        content.userInfo = info
        // The app's chime (a kiss and a soft bell), with the vibration that comes with it.
        content.sound = UNNotificationSound(named: UNNotificationSoundName(TouchNotification.sound))
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        if let file = TouchNotification.imageFile(touch),
           let attachment = try? UNNotificationAttachment(identifier: "touch", url: file,
                                                          options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]) {
            content.attachments = [attachment]
        }
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
