import LocalAuthentication
import SwiftUI

/// Private Space — a passcode/biometric-locked space for the couple, with a purple theme
/// distinct from the main app. Strings and flow follow the original (setup → create
/// passcode → repeat → enter; unlock by passcode or biometrics). The encrypted shared
/// chat and gallery are relayed over iCloud.
struct PrivateSpaceView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    enum Phase { case intro, create, confirm, locked, unlocked }
    @State private var phase: Phase = .locked
    @State private var entry = ""
    @State private var firstCode = ""
    @State private var error: String?
    @State private var section: Section = .chat

    private static let purpleTop = Color(rgbInt: 0x7A3B9E)
    private static let purpleBottom = Color(rgbInt: 0xC8558F)
    private var background: some View {
        LinearGradient(colors: [Self.purpleTop, Self.purpleBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            background
            switch phase {
            case .intro:     introView
            case .create:    passcodeEntry(title: "Create passcode",
                                           subtitle: "You'll need this every time you enter Private Space.")
            case .confirm:   passcodeEntry(title: "Repeat Passcode", subtitle: nil)
            case .locked:    passcodeEntry(title: lockTitle, subtitle: nil, allowBiometrics: true)
            case .unlocked:  unlockedView
            }
        }
        .navigationTitle("Private Space")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: begin)
        // Locks again whenever the app leaves the screen.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if store.hasPrivateSpace { entry = ""; phase = .locked }
        }
        // As the original: a double tap on your own (connected) bracelet unlocks it.
        .onChange(of: model.braceletDoubleTaps) { _ in
            guard phase == .locked else { return }
            entry = ""; error = nil
            phase = .unlocked
        }
    }

    private var lockTitle: String {
        model.braceletState == .connected ? "Enter passcode or\ndouble-tap your bracelet" : "Enter passcode"
    }

    private func begin() {
        if !store.hasPrivateSpace { phase = .intro }
        else { phase = .locked; tryBiometrics() }
    }

    // MARK: Intro / setup

    private var introView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill").font(.system(size: 64)).foregroundStyle(.white)
            Text("Welcome to Private Space!").font(.title2.bold()).foregroundStyle(.white)
            Text("This is a safe space just for you two. ❤️ Use it to share messages and photos privately.")
                .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 6) {
                Text("Cool features of Private Space:").font(.subheadline.bold()).foregroundStyle(.white)
                Text("∙ Encrypted private chat\n∙ Shared gallery for you and your partner\n∙ Unlock secret photos with your Bond Touch")
                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
            }
            .padding().background(Color.white.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            Spacer()
            Button { phase = .create; entry = "" } label: {
                Text("Setup").font(.headline).frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
                    .background(.white).foregroundStyle(Self.purpleTop)
                    .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Metric.buttonMargin)
        .padding(.top, Metric.buttonMargin)
        // Clear of the floating tab bar, so Setup is never under it.
        .padding(.bottom, 104)
    }

    // MARK: Passcode entry

    private func passcodeEntry(title: String, subtitle: String?, allowBiometrics: Bool = false) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 18) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().stroke(.white, lineWidth: 2).frame(width: 18, height: 18)
                        .background(Circle().fill(i < entry.count ? Color.white : .clear))
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.white) }
            Spacer(minLength: 12)
            keypad(allowBiometrics: allowBiometrics)
        }
        .padding(.horizontal, Metric.buttonMargin)
        .padding(.top, Metric.buttonMargin)
        // Clear of the floating tab bar, so the bottom row (Face ID, 0, delete) is reachable.
        .padding(.bottom, 104)
    }

    private func keypad(allowBiometrics: Bool) -> some View {
        let keys = ["1","2","3","4","5","6","7","8","9","", "0", "<"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
            ForEach(keys, id: \.self) { key in
                if key.isEmpty {
                    if allowBiometrics {
                        Button { tryBiometrics() } label: { keyLabel(Image(systemName: "faceid")) }
                    } else { Color.clear.frame(height: 64) }
                } else if key == "<" {
                    Button { if !entry.isEmpty { entry.removeLast() } } label: { keyLabel(Image(systemName: "delete.left")) }
                } else {
                    Button { tap(key) } label: { keyLabel(Text(key).font(.title.weight(.medium))) }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func keyLabel<V: View>(_ content: V) -> some View {
        content.frame(maxWidth: .infinity).frame(height: 64)
            .background(Circle().fill(Color.white.opacity(0.12)).frame(width: 64, height: 64))
    }

    private func tap(_ digit: String) {
        guard entry.count < 4 else { return }
        entry += digit
        error = nil
        if entry.count == 4 { submit() }
    }

    private func submit() {
        switch phase {
        case .create:
            firstCode = entry; entry = ""; phase = .confirm
        case .confirm:
            if entry == firstCode {
                store.setPrivateSpacePasscode(entry); entry = ""; phase = .unlocked
            } else {
                entry = ""; firstCode = ""; error = "Uh-oh, passcodes didn't match. Just try again."; phase = .create
            }
        case .locked:
            if store.checkPrivateSpacePasscode(entry) { entry = ""; phase = .unlocked }
            else { entry = ""; error = "Wrong passcode. Try again." }
        default:
            break
        }
    }

    private func tryBiometrics() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Unlock Private Space") { ok, _ in
            if ok { DispatchQueue.main.async { phase = .unlocked } }
        }
    }

    // MARK: Unlocked

    private var unlockedView: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Encrypted · kept for 72 hours", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button { phase = .locked } label: {
                    Image(systemName: "lock").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .accessibilityLabel("Lock Private Space")
            }
            .padding(.horizontal, 16)
            Picker("", selection: $section) {
                Text("Chat").tag(Section.chat)
                Text("Gallery").tag(Section.gallery)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            // Kept out of screenshots and screen recordings, as the original.
            ScreenshotShield {
                Group {
                    switch section {
                    case .chat: ChatView()
                    case .gallery: PrivateGallery()
                    }
                }
                .environmentObject(model)
                .environmentObject(store)
                .environment(\.colorScheme, .dark)
                .tint(Theme.accent)
            }
        }
        .padding(.top, 8)
        // A screenshot is still possible of the parts outside the shield (and on iOS versions
        // where it can't hide anything): tell the partner, as the original does.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            Task { await model.sendChatText("📸 Took a screenshot of Private Space") }
        }
    }

    enum Section { case chat, gallery }
}

/// The shared gallery: every photo in the chat with this partner, newest first, each with the
/// time it has left (photos go after 72 hours, as the original). Tap one to see it full size.
private struct PrivateGallery: View {
    @EnvironmentObject var model: AppModel
    @State private var open: ChatMessage?

    private var photos: [ChatMessage] {
        model.chatMessages(for: model.selectedPartnerID).filter { $0.kind == .image && $0.imageFile != nil }.reversed()
    }

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(.white)
                    Text("Shared gallery").font(.headline).foregroundStyle(.white)
                    Text("Photos you send each other in Private Space show here for 72 hours.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(32)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                    ForEach(photos) { msg in
                        Button { open = msg } label: { tile(msg) }.buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .fullScreenCover(item: $open) { msg in PhotoViewer(message: msg) }
    }

    private func tile(_ msg: ChatMessage) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let file = msg.imageFile, let image = UIImage(contentsOfFile: ChatArchive.imageURL(file).path) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                Text(timeLeft(msg)).font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.5))).padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Photo, \(timeLeft(msg))")
    }

    private func timeLeft(_ msg: ChatMessage) -> String {
        let left = max(0, ChatArchive.lifetime - Date().timeIntervalSince(msg.sentAt))
        let hours = Int(left / 3600)
        return hours >= 1 ? "\(hours)h left" : "\(max(1, Int(left / 60)))m left"
    }
}

private struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let file = message.imageFile, let image = UIImage(contentsOfFile: ChatArchive.imageURL(file).path) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.85))
            }
            .padding()
            .accessibilityLabel("Close")
        }
    }
}
