import SwiftUI

/// First-run profile setup — name and signature colour. Mirrors the original's profile
/// setup (minus the account/login, which iCloud handles implicitly).
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var name = ""
    @State private var color: Color = .pink

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "heart.circle.fill").font(.system(size: 84)).foregroundStyle(.pink)
            Text("Welcome to Beyond Touch").font(.title2.bold())
            Text("Stay close with a partner — send a touch, a message, or your heartbeat to their bracelet.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)

            VStack(spacing: 16) {
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                ColorPicker("Your colour", selection: $color)
            }
            .padding(.horizontal)

            Spacer()
            Button {
                var p = store.profile
                p.name = name.trimmingCharacters(in: .whitespaces)
                p.colorRGB = color.rgbInt
                store.profile = p
                Task { await model.publishProfile() }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            name = store.profile.name
            color = Color(rgbInt: store.profile.colorRGB)
        }
    }
}
