import SwiftUI

/// The home screen — "Hello, this is us": the two partners with their status, and a feed of
/// recent touches rendered as glowing strokes.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showHeart = false
    @State private var showPeople = false
    @State private var showEncounters = false
    @State private var editingGreeting = false
    @State private var greetingDraft = ""

    private var partner: Partner? { model.selectedPartner }

    private var daysToNextMeeting: Int? {
        guard let date = store.nextMeeting(for: model.selectedPartnerID) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        return max(0, days)
    }

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
        .sheet(isPresented: $showEncounters) {
            EncountersView(bondID: model.selectedPartnerID)
        }
        .sheet(isPresented: $editingGreeting) {
            GreetingEditor(text: $greetingDraft) {
                model.setGreeting(greetingDraft, for: model.selectedPartnerID)
            }
            .presentationDetents([.height(240)])
        }
    }

    private var topBar: some View {
        HStack {
            Button { showHeart = true } label: {
                Image(systemName: "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            Spacer()
            PartnerBar()
            Spacer()
            Button { showPeople = true } label: {
                Image(systemName: "person.2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
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

            Button { showEncounters = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 24)).foregroundStyle(Theme.accent)
                    if let days = daysToNextMeeting {
                        Text(days == 0 ? "Today" : "\(days)d")
                            .font(.caption2.bold()).foregroundStyle(Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 40)

            if let partner {
                VStack(spacing: 8) {
                    AvatarRing(name: partner.displayName,
                               ringColor: Color(rgbInt: partner.colorRGB), size: 120)
                    Text(partner.displayName)
                        .font(.headline).foregroundStyle(.white)
                    Text(partner.online ? "Online" : "Offline")
                        .font(.caption).foregroundStyle(Theme.subtitle)
                }
                .frame(maxWidth: .infinity)
            } else {
                Button { showPeople = true } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                .foregroundStyle(Theme.subtitle).frame(width: 120, height: 120)
                            Image(systemName: "plus").font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text("Add a partner").font(.headline).foregroundStyle(.white)
                        Text("Not connected").font(.caption).foregroundStyle(Theme.subtitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
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
        VStack(alignment: .trailing, spacing: 6) {
            GlassCard {
                HStack(spacing: 12) {
                    TouchViz(pattern: touch.pattern, colorRGB: touch.colorRGB, endColorRGB: touch.endColorRGB)
                    Spacer(minLength: 8)
                    Button { model.bracelet.play(touch) } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.subtitle)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 4) {
                Text("\(mine ? "Last sent" : "Received") \(touch.sentAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(Theme.subtitle)
                if mine {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(Theme.subtitle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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
