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
        .padding(Metric.buttonMargin)
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
            Spacer()
            keypad(allowBiometrics: allowBiometrics)
        }
        .padding(Metric.buttonMargin)
    }

    private func keypad(allowBiometrics: Bool) -> some View {
        let keys = ["1","2","3","4","5","6","7","8","9","", "0", "<"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 18) {
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
        VStack(spacing: 16) {
            HStack {
                Label("Encrypted · messages kept for 72 hours", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                galleryCard
                Spacer()
            }
        }
        .padding(Metric.buttonMargin)
    }

    private var galleryCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(.white)
            Text("Shared gallery").font(.headline).foregroundStyle(.white)
            Text("Photos you share here stay just between you two.")
                .font(.footnote).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24)
        .background(Color.white.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: Metric.cornerLarge))
    }
}
