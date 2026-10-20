import SwiftUI

/// A circular avatar with a glowing coloured ring: the person's photo when there is one,
/// otherwise their initial on a tinted disc.
struct AvatarRing: View {
    let name: String
    let ringColor: Color
    var size: CGFloat = 120
    var photo: UIImage? = nil
    var ringWidth: CGFloat? = nil

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Circle().fill(LinearGradient(colors: [ringColor.opacity(0.85), ringColor.opacity(0.45)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(initial.isEmpty ? "•" : initial)
                    .font(Theme.font(size * 0.4, .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: max(2, size * 0.035)))
        .overlay(Circle().stroke(ringColor, lineWidth: max(ringWidth ?? size * 0.03, 0.5))
            .padding(-max(3, size * 0.05))
            .opacity(ringWidth == 0 ? 0 : 1))
        .shadow(color: ringColor.opacity(0.55), radius: size * 0.1)
    }
}

/// The app-wide background: the aero sky, or — when a partner with a photo is selected and
/// the photo background is on for them — their photo, softly blurred, under a soft scrim.
struct AppBackground: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    var body: some View {
        ZStack {
            ThemeBackdrop()
            if let photo = model.backgroundPhoto {
                GeometryReader { geo in
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: store.backgroundSoftness, opaque: true)
                        .scaleEffect(1.08)
                        .clipped()
                }
                LinearGradient(colors: [Theme.bgBottom.opacity(0.25), Theme.bgBottom.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                // Bubble and Raindrop keep their bubbles and drops over the photo.
                switch Theme.style {
                case .bubble: BubbleParticles()
                case .raindrop: RainParticles()
                default: EmptyView()
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: model.selectedPartnerID)
    }
}
