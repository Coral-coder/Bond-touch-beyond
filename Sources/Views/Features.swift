import SwiftUI

/// Parts of the app that can be switched off in Settings → Features (all on by default).
enum Feature: String, CaseIterable, Identifiable {
    case us, dates, likes, todos, notes, whiteboard, games, stress, radar, weather
    var id: String { rawValue }
    var key: String { "feature.\(rawValue)" }
    var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    var title: String {
        switch self {
        case .us: return "Us tab"
        case .dates: return "Special dates & reminders"
        case .likes: return "What we like"
        case .todos: return "Shared to-dos"
        case .notes: return "Shared notes"
        case .whiteboard: return "Whiteboard"
        case .games: return "Games"
        case .stress: return "Stress & mood"
        case .radar: return "R.A.D.A.R. check-ins"
        case .weather: return "Their weather"
        }
    }

    var icon: String {
        switch self {
        case .us: return "heart.circle.fill"
        case .dates: return "calendar"
        case .likes: return "sparkles"
        case .todos: return "checklist"
        case .notes: return "note.text"
        case .whiteboard: return "scribble.variable"
        case .games: return "gamecontroller.fill"
        case .stress: return "face.smiling"
        case .radar: return "dot.radiowaves.left.and.right"
        case .weather: return "cloud.sun.fill"
        }
    }
}

/// Settings → Features: switch parts of the app on and off, folded away until tapped.
struct FeaturesCard: View {
    @AppStorage("featuresOpen") private var open = false
    @State private var tick = 0

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
                } label: {
                    HStack {
                        Text("Features").foregroundStyle(Theme.title)
                        Spacer()
                        Text("\(Feature.allCases.filter(\.isOn).count) of \(Feature.allCases.count) on")
                            .font(.subheadline).foregroundStyle(Theme.subtitle)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.subtitle)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    ForEach(Feature.allCases) { f in
                        Toggle(isOn: Binding(get: { _ = tick; return f.isOn },
                                             set: { UserDefaults.standard.set($0, forKey: f.key); tick += 1 })) {
                            Label(f.title, systemImage: f.icon).foregroundStyle(Theme.title)
                        }
                        .tint(Theme.accent)
                    }
                }
            }
        }
    }
}
