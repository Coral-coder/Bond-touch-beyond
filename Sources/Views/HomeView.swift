import SwiftUI

/// The home screen — "Hello, this is us": the two partners with their status, and a feed of
/// recent touches rendered as glowing strokes.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showHeart = false
    @State private var showPeople = false
    @State private var editingGreeting = false
    @State private var greetingDraft = ""

    private var partner: Partner? { model.selectedPartner }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        greetingDraft = store.greeting(for: model.selectedPartnerID)
                        editingGreeting = true
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text(store.greeting(for: model.selectedPartnerID))
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.mutedHeadline)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.subtitle)
                                .padding(.top, 8)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    pairRow

                    ForEach(model.history.reversed()) { touch in
                        touchCard(touch)
                    }
                    Color.clear.frame(height: 90) // room for the floating tab bar
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showHeart) {
            NavigationStack { HeartView().navigationTitle("Heartbeat") }
        }
        .sheet(isPresented: $showPeople) {
            NavigationStack { PeopleView().navigationTitle("People") }
        }
        .sheet(isPresented: $editingGreeting) {
            GreetingEditor(text: $greetingDraft) {
                store.setGreeting(greetingDraft, for: model.selectedPartnerID)
            }
            .presentationDetents([.height(240)])
        }
    }

    private var topBar: some View {
        HStack {
            Button { showHeart = true } label: {
                Image(systemName: "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            Spacer()
            PartnerBar()
            Spacer()
            Button { showPeople = true } label: {
                Image(systemName: "person.2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var pairRow: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 8) {
                AvatarRing(name: store.profile.name.isEmpty ? "Me" : store.profile.name,
                           ringColor: Color(rgbInt: store.profile.colorRGB), size: 120)
                Text(store.profile.name.isEmpty ? "Me" : store.profile.name)
                    .font(.headline).foregroundStyle(.white)
                Text(statusText).font(.caption).foregroundStyle(Theme.subtitle)
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "heart.text.square")
                .font(.system(size: 26)).foregroundStyle(Theme.teal)
                .padding(.top, 44)

            VStack(spacing: 8) {
                AvatarRing(name: partner?.displayName ?? "Partner",
                           ringColor: Color(rgbInt: partner?.colorRGB ?? 0xAEE63C), size: 120)
                Text(partner?.displayName ?? "Partner")
                    .font(.headline).foregroundStyle(.white)
                Text(partner?.online == true ? "Online" : "Offline")
                    .font(.caption).foregroundStyle(Theme.subtitle)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }

    private var statusText: String {
        switch model.braceletState {
        case .connected: return "Connected"
        case .scanning, .connecting: return "Connecting…"
        case .bluetoothOff: return "Bluetooth off"
        case .disconnected: return "Not connected"
        }
    }

    @ViewBuilder private func touchCard(_ touch: TouchMessage) -> some View {
        let mine = touch.senderID == model.myUserID
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            GlassCard {
                HStack {
                    if mine { Spacer() }
                    TouchViz(pattern: touch.pattern, colorRGB: touch.colorRGB)
                    if !mine { Spacer() }
                }
            }
            Text("\(mine ? "Sent" : "Received") \(touch.sentAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2).foregroundStyle(Theme.subtitle)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

/// Small sheet to edit the per-partner home greeting.
private struct GreetingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var text: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("This greeting shows at the top of Home for this partner.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Greeting", text: $text, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.roundedBorder)
                Spacer()
            }
            .padding()
            .navigationTitle("Greeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                }
            }
        }
    }
}
