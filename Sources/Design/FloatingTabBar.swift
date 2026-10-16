import SwiftUI

enum AppTab: CaseIterable {
    case home, touches, map, chat, settings

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .touches: return "book.fill"
        case .map: return "location.fill"
        case .chat: return "message.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// The floating pill tab bar at the bottom of the app.
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selection == tab ? Theme.accent : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule().fill(selection == tab ? Color.white.opacity(0.14) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .background(Theme.bgTop.opacity(0.5))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
}
