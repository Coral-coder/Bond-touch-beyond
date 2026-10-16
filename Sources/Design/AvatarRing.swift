import SwiftUI

/// A circular avatar with a glowing colored ring, as on the home screen. Renders the
/// person's initial on a tinted disc (no photo yet — profile photos can be added later).
struct AvatarRing: View {
    let name: String
    let ringColor: Color
    var size: CGFloat = 120

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [ringColor.opacity(0.35), Theme.bgTop],
                                     center: .center, startRadius: 2, endRadius: size / 2))
            Text(initial.isEmpty ? "•" : initial)
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(ringColor, lineWidth: 4))
        .shadow(color: ringColor.opacity(0.7), radius: 12)
    }
}
