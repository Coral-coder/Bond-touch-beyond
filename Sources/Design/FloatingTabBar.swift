import SwiftUI

enum AppTab: CaseIterable {
    case home, us, touches, chat, map, settings

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .us: return "heart.circle.fill"
        case .touches: return "hand.tap.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .map: return "map.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .us: return "Us"
        case .touches: return "Language"
        case .chat: return "Chat"
        case .map: return "Map"
        case .settings: return "Settings"
        }
    }
}

/// The floating glass tab bar at the bottom of the app.
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon).font(.system(size: 19, weight: .semibold))
                        Text(tab.title).font(Theme.font(10, .bold))
                    }
                    .foregroundStyle(selection == tab ? Theme.title : Theme.subtitle.opacity(0.8))
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Capsule().fill(selection == tab ? Theme.ink.opacity(0.16) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .glass(Capsule())
        .padding(.horizontal, 16)
    }
}
