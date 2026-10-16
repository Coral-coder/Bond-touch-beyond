import SwiftUI

/// "Touch Language" — saved touches you can send with one tap. Each is a tap rhythm with a
/// name and a two-stop colour gradient (start → end), as in the original app. Tap Send to
/// play it on your partner's bracelet.
struct MeaningsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(); PartnerBar(); Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Touch Language")
                            .font(Theme.font(32, .heavy))
                            .foregroundStyle(.white)
                        Spacer()
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 46, height: 46)
                                .glass(Circle())
                        }
                    }
                    .padding(.top, 8)

                    if model.currentMeanings.isEmpty {
                        Text("You can start adding touches to your Touch Language.")
                            .foregroundStyle(Theme.subtitle)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    ForEach(model.currentMeanings) { meaning in
                        meaningCard(meaning)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await model.deleteMeaning(meaning) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 20)
            }
        }
        .fullScreenCover(isPresented: $showAdd) { ComposeTouchView(mode: .createMeaning) }
    }

    @ViewBuilder private func meaningCard(_ meaning: TouchMeaning) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "play.circle").foregroundStyle(Theme.subtitle)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(meaning.label).font(.headline).foregroundStyle(.white)
                        if meaning.isNew { newBadge }
                    }
                    TouchViz(pattern: meaning.pattern, generation: meaning.touchGeneration,
                             colorRGB: meaning.colorRGB, endColorRGB: meaning.endColorRGB)
                }
                Spacer()
                Button {
                    Task {
                        await model.sendTouch(pattern: meaning.pattern,
                                              generation: meaning.touchGeneration,
                                              colorRGB: meaning.colorRGB,
                                              endColorRGB: meaning.endColorRGB)
                    }
                    clearNew(meaning)
                } label: {
                    Text("Send").font(Theme.font(15, .heavy)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var newBadge: some View {
        Text("New")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.bgBottom)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.85)))
    }

    private func clearNew(_ meaning: TouchMeaning) {
        guard let i = store.meanings.firstIndex(where: { $0.id == meaning.id }), store.meanings[i].isNew else { return }
        store.meanings[i].isNew = false
    }
}
