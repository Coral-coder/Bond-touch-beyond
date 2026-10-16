import SwiftUI

/// A translucent frosted card used throughout the app.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner)
                .stroke(Theme.cardStroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
    }
}
