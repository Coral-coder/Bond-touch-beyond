import SwiftUI

/// Prompts from the bracelet itself, as the original shows them: a bracelet in setup mode
/// waits for a double tap to pair with this phone.
struct BraceletPromptBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Inner(bracelet: model.bracelet)
    }

    private struct Inner: View {
        @ObservedObject var bracelet: BraceletManager

        var body: some View {
            if bracelet.needsSetupTap, bracelet.state != .disconnected {
                HStack(spacing: 12) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Double-tap the flashing bracelet").font(Theme.font(15, .heavy)).foregroundStyle(.white)
                        Text("That pairs it with this phone.").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    }
                    Spacer()
                }
                .padding(14)
                .glass(cornerRadius: 22)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
