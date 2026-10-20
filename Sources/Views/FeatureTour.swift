import SwiftUI

/// A short, skippable tour of the app's main features. Shown once after onboarding (and once
/// to existing users on the first launch of a build that has it), and again from
/// Settings → Feature tour.
struct FeatureTour: View {
    /// Set once the tour has been finished or skipped, so it isn't shown automatically again.
    static let seenKey = "walkthroughSeen"

    var onDone: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let icon: String, title: String, text: String
        var id: String { title }
    }

    private let pages: [Page] = [
        Page(icon: "hand.tap.fill", title: "Send a touch",
             text: "Tap and slide on the touch bar on Home — the touch is sent when the timer runs out. Save the ones you love as meanings in your Touch Language."),
        Page(icon: "applewatch", title: "Bracelet & Apple Watch",
             text: "Pair your Bond Touch bracelet under Settings → My Bond Touch Bracelet. When it disconnects, your Apple Watch can stand in and play every touch on your wrist."),
        Page(icon: "heart.fill", title: "Heartbeats",
             text: "Record your heartbeat with your phone's camera, or with a Bond Heart, and send it. Your partner sees it beat live, and every one is kept in your library."),
        Page(icon: "heart.circle.fill", title: "Us",
             text: "The Us tab is for the two of you: special dates, shared to-dos and notes, games to play together, and your Touch Language."),
        Page(icon: "lock.shield.fill", title: "Private chat",
             text: "Chat lives in Private Space, behind its lock, and is end-to-end encrypted. Message notifications never include what was said."),
        Page(icon: "map.fill", title: "Map & places",
             text: "See where your partners are on the Map, and save places. When you arrive at one, they feel a touch saying so."),
        Page(icon: "face.smiling", title: "Stress & mood",
             text: "Check in with how you feel and share it quietly. Your partners only get a notification when you're stressed or overwhelmed."),
        Page(icon: "paintpalette.fill", title: "Make it yours",
             text: "Pick a look under Settings → Theme and arrange Home under Settings → Layout. Choose what reaches you in Settings → Notifications."),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            ThemeBackdrop().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !isLast {
                        Button("Skip", action: onDone)
                            .font(Theme.font(16, .semibold))
                            .foregroundStyle(Theme.subtitle)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                    }
                }
                .frame(height: 48)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                        card(p).tag(i).padding(.horizontal, 20)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                dots.padding(.vertical, 18)

                Button(isLast ? "Done" : "Next") {
                    if isLast { onDone() } else { withAnimation { page += 1 } }
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .modifier(ThemeFonts())
        .preferredColorScheme(Theme.colorScheme)
        .tint(Theme.accent)
    }

    private func card(_ p: Page) -> some View {
        VStack(spacing: 20) {
            Image(systemName: p.icon)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(height: 80)
            Text(p.title)
                .font(Theme.font(26, .heavy)).foregroundStyle(Theme.title)
                .multilineTextAlignment(.center)
            Text(p.text)
                .font(Theme.font(16)).foregroundStyle(Theme.subtitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glass(cornerRadius: Theme.cardCorner)
        .accessibilityElement(children: .combine)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Theme.accent : Theme.subtitle.opacity(0.35))
                    .frame(width: i == page ? 20 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
        .accessibilityHidden(true)
    }
}

/// Settings → Feature tour: opens the tour again.
struct FeatureTourRow: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            GlassCard(padding: 20) {
                HStack(spacing: 14) {
                    Text("Feature tour").foregroundStyle(Theme.title)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.subtitle).font(.footnote)
                }
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showing) {
            FeatureTour { showing = false }
        }
    }
}
