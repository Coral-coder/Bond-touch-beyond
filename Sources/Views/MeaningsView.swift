import SwiftUI

/// "Touch Language" — saved touches you can send with one tap. Each is a tap rhythm with a
/// name and a two-stop colour gradient (start → end), as in the original app. Tap Send to
/// play it on your partner's bracelet.
struct MeaningsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showAdd = false
    @State private var pendingDelete: TouchMeaning?
    @State private var editing: TouchMeaning?

    /// Favourites first, as the original library.
    private var sorted: [TouchMeaning] {
        model.currentMeanings.enumerated()
            .sorted { ($0.element.favourite == true ? 0 : 1, $0.offset) < ($1.element.favourite == true ? 0 : 1, $1.offset) }
            .map(\.element)
    }

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

                    ForEach(sorted) { meaning in
                        meaningCard(meaning)
                            .contextMenu {
                                Button { editing = meaning } label: { Label("Edit", systemImage: "pencil") }
                                Button { toggleFavourite(meaning) } label: {
                                    Label(meaning.favourite == true ? "Remove from favourites" : "Favourite",
                                          systemImage: meaning.favourite == true ? "star.slash" : "star")
                                }
                                Button(role: .destructive) {
                                    pendingDelete = meaning
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 20)
            }
        }
        .fullScreenCover(isPresented: $showAdd) { ComposeTouchView(mode: .createMeaning) }
        .sheet(item: $editing) { m in
            EditMeaningSheet(meaning: m) { edited in Task { await model.updateMeaning(edited) } }
        }
        // As the original: confirm, since a meaning is shared with the partner.
        .confirmationDialog("Delete \"\(pendingDelete?.label ?? "meaning")\"?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let m = pendingDelete { Task { await model.deleteMeaning(m) } }
                pendingDelete = nil
            }
        } message: {
            Text("This meaning will disappear for both of you.")
        }
    }

    @ViewBuilder private func meaningCard(_ meaning: TouchMeaning) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                // Replays the meaning on your own bracelet (or the phone, if it isn't connected).
                Button {
                    model.feel(TouchMessage(senderID: model.myUserID, pattern: meaning.pattern,
                                            generation: meaning.touchGeneration, colorRGB: meaning.colorRGB,
                                            endColorRGB: meaning.endColorRGB,
                                            meaningLabel: meaning.label, meaningEmoji: meaning.emoji))
                } label: {
                    Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(meaning.label) on your bracelet")
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(meaning.label).font(.headline).foregroundStyle(.white)
                        if meaning.isNew { newBadge }
                        Button { toggleFavourite(meaning) } label: {
                            Image(systemName: meaning.favourite == true ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(meaning.favourite == true ? Theme.amber : Theme.subtitle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(meaning.favourite == true ? "Remove \(meaning.label) from favourites" : "Favourite \(meaning.label)")
                    }
                    TouchViz(pattern: meaning.pattern, generation: meaning.touchGeneration,
                             colorRGB: meaning.colorRGB, endColorRGB: meaning.endColorRGB)
                }
                Spacer()
                Button {
                    Task { await model.sendMeaning(meaning) }
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

    private func toggleFavourite(_ meaning: TouchMeaning) {
        var m = meaning
        m.favourite = !(meaning.favourite ?? false)
        Task { await model.updateMeaning(m) }
    }

    private func clearNew(_ meaning: TouchMeaning) {
        model.markMeaningSeen(meaning)
    }
}

/// Rename a meaning (20 characters, as the original), change its emoji or its colours.
private struct EditMeaningSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meaning: TouchMeaning
    let onSave: (TouchMeaning) -> Void
    @State private var label = ""
    @State private var emoji = ""
    @State private var start: Color = .pink
    @State private var end: Color = .pink

    private static let maxName = 20
    private var trimmed: String { label.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $label)
                        .onChange(of: label) { if $0.count > Self.maxName { label = String($0.prefix(Self.maxName)) } }
                    TextField("Emoji", text: $emoji)
                        .onChange(of: emoji) { if $0.count > 2 { emoji = String($0.prefix(2)) } }
                } footer: { Text("\(label.count)/\(Self.maxName)") }
                Section("Colours") {
                    ColorPicker("Start", selection: $start, supportsOpacity: false)
                    ColorPicker("End", selection: $end, supportsOpacity: false)
                    TouchViz(pattern: meaning.pattern, generation: meaning.touchGeneration,
                             colorRGB: start.rgbInt, endColorRGB: end.rgbInt)
                }
            }
            .navigationTitle("Edit touch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var m = meaning
                        m.label = trimmed
                        m.emoji = emoji
                        m.colorRGB = start.rgbInt
                        m.endColorRGB = end.rgbInt
                        onSave(m)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
        .onAppear {
            label = meaning.label; emoji = meaning.emoji
            start = Color(rgbInt: meaning.colorRGB); end = Color(rgbInt: meaning.endColorRGB)
        }
        .preferredColorScheme(.dark)
    }
}
