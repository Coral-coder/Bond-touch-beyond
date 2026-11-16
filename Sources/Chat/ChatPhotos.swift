import CryptoKit
import SwiftUI
import UIKit

/// Photos in Private Space, kept encrypted on this phone. Each file is sealed with AES-GCM
/// under a key that lives only in this device's Keychain (never in a backup, never synced),
/// on top of iOS file protection, and the folder is left out of iCloud backups. In transit
/// they are already sealed end to end with the bond's key, like every message.
enum ChatVault {
    private static let service = "BondTouchBeyond.chatvault"
    private static let account = "media-key"
    private static var cached: SymmetricKey?

    /// The device key: made once, kept in the Keychain for this device only.
    static var key: SymmetricKey {
        if let cached { return cached }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        var out: CFTypeRef?
        var read = query
        read[kSecReturnData as String] = true
        if SecItemCopyMatching(read as CFDictionary, &out) == errSecSuccess, let data = out as? Data, data.count == 32 {
            let k = SymmetricKey(data: data)
            cached = k
            return k
        }
        let k = SymmetricKey(size: .bits256)
        var add = query
        add[kSecValueData as String] = k.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(query as CFDictionary)
        SecItemAdd(add as CFDictionary, nil)
        cached = k
        return k
    }

    static func seal(_ data: Data) -> Data? { try? AES.GCM.seal(data, using: key).combined }

    static func open(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

/// Getting a photo ready to send: small enough to travel in one sealed message.
enum ChatPhoto {
    /// iCloud and Firebase both cap a record near 1 MB, and the sealed message carries the
    /// photo as text (a third bigger), so the JPEG must stay under this.
    static let maxBytes = 540_000

    /// Scales the photo down (longest side 1600, then smaller) and lowers the quality until
    /// it fits. Returns nil only if it can't be drawn at all.
    static func prepare(_ image: UIImage) -> Data? {
        for side in [1600.0, 1280, 1024, 800, 640] as [CGFloat] {
            let scaled = resized(image, longest: side)
            for quality in [0.72, 0.6, 0.5, 0.4] as [CGFloat] {
                if let data = scaled.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
            }
        }
        return resized(image, longest: 480).jpegData(compressionQuality: 0.4)
    }

    private static func resized(_ image: UIImage, longest: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let scale = min(1, longest / max(w, h, 1))
        let size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// How long a photo can be looked at once opened; 0 means no limit (it still goes after 72 hours).
    static let timers = [3, 5, 10, 30, 60, 0]

    static func timerTitle(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "No limit"
        case 60: return "1 min"
        default: return "\(seconds) s"
        }
    }
}

extension ChatMessage {
    /// A photo with a view timer.
    var isTimed: Bool { kind == .image && (viewSeconds ?? 0) > 0 }

    /// Seconds left to look at a timed photo: the full time until it's first opened.
    func viewTimeLeft(now: Date = Date()) -> Double {
        let total = Double(viewSeconds ?? 0)
        guard let openedAt else { return total }
        return max(0, total - now.timeIntervalSince(openedAt))
    }
}

/// Choose how long the photo can be viewed, then send. Shown after picking a photo.
struct PhotoSendSheet: View {
    let image: UIImage
    let partnerName: String
    let onSend: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("chatPhotoTimer") private var seconds = 10

    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 8) {
                Label("How long \(partnerName) can view it", systemImage: "timer")
                    .font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                HStack(spacing: 6) {
                    ForEach(ChatPhoto.timers, id: \.self) { t in
                        Button { seconds = t } label: {
                            Text(ChatPhoto.timerTitle(t))
                                .font(Theme.font(13, .bold))
                                .foregroundStyle(seconds == t ? Theme.onAccent : Theme.title)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(Capsule().fill(seconds == t ? Theme.accent : Theme.ink.opacity(0.1)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(seconds == t ? .isSelected : [])
                    }
                }
                Text(seconds == 0
                     ? "It stays in the chat for 72 hours, then it's deleted from both phones."
                     : "The timer starts when it's opened. When it ends, the photo is deleted from that phone. You're told if a screenshot is taken.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(Theme.ink.opacity(0.1)))
                    .buttonStyle(.plain)
                Button { onSend(seconds); dismiss() } label: {
                    Label("Send", systemImage: "lock.fill")
                }
                .buttonStyle(AccentButtonStyle(height: 50))
            }
            Label("Encrypted end to end, and on both phones", systemImage: "lock.shield.fill")
                .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
        }
        .padding(20)
        .screenBackground()
    }
}

/// A photo full screen. A timed one counts down and closes when its time is up; it is hidden
/// while the screen is being recorded or the app isn't in front, and a screenshot is reported
/// to the sender.
struct ChatPhotoViewer: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let message: ChatMessage
    @State private var image: UIImage?
    @State private var captured = UIScreen.main.isCaptured

    private var current: ChatMessage { model.chatMessage(message.id, bondID: message.bondID) ?? message }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if captured || scenePhase != .active {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill").font(.system(size: Theme.s(34)))
                    Text(captured ? "Hidden while the screen is being recorded" : "Hidden")
                        .font(Theme.font(15, .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                if current.isTimed {
                    TimelineView(.periodic(from: .now, by: 0.1)) { tl in
                        let left = current.viewTimeLeft(now: tl.date)
                        let total = Double(max(1, current.viewSeconds ?? 1))
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                                Circle().trim(from: 0, to: left / total)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 26, height: 26)
                            Text("\(Int(left.rounded(.up))) s").font(Theme.font(15, .heavy)).foregroundStyle(.white)
                        }
                        .onChange(of: left <= 0) { done in if done { dismiss() } }
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: Theme.s(30))).foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityLabel("Close")
            }
            .padding()
        }
        .onAppear {
            image = current.imageFile.flatMap(ChatArchive.image)
            model.openChatPhoto(current)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            captured = UIScreen.main.isCaptured
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            model.reportPhotoScreenshot(current)
        }
        .statusBarHidden()
    }
}

/// A timed photo in the chat or gallery before it's opened: locked, with its time.
struct TimedPhotoTile: View {
    let message: ChatMessage

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let left = message.viewTimeLeft(now: tl.date)
            VStack(spacing: 6) {
                Image(systemName: message.openedAt == nil ? "lock.fill" : "timer")
                    .font(.system(size: Theme.s(22), weight: .semibold))
                Text(message.openedAt == nil ? "Tap to view" : "View again")
                    .font(Theme.font(14, .heavy))
                Text(message.openedAt == nil ? ChatPhoto.timerTitle(message.viewSeconds ?? 0)
                                             : "\(Int(left.rounded(.up))) s left")
                    .font(Theme.font(12)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(width: 150, height: 130)
            .background(RoundedRectangle(cornerRadius: 18).fill(
                LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accentDeep.opacity(0.4)],
                               startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.35), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timed photo, \(ChatPhoto.timerTitle(message.viewSeconds ?? 0)). Tap to view")
    }
}
