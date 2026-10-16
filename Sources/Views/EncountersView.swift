import SwiftUI

/// Encounters — a shared countdown to the next time the partners meet, as in the original
/// app. Set a date and the dashboard shows the days remaining; clear it to remove.
struct EncountersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: LocalStore
    let bondID: String?

    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    private var daysLeft: Int? {
        guard let saved = store.nextMeeting(for: bondID) else { return nil }
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                         to: cal.startOfDay(for: saved)).day ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let days = daysLeft {
                        VStack(spacing: 6) {
                            Text(days == 0 ? "Today" : "\(days)")
                                .font(.system(size: 64, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.accent)
                            Text(days == 0 ? "You meet today" : "days until you meet again")
                                .foregroundStyle(Theme.subtitle)
                        }
                        .padding(.top, 10)
                    } else {
                        Text("When are your next encounters?")
                            .font(.title3.weight(.semibold)).foregroundStyle(.white)
                            .multilineTextAlignment(.center).padding(.top, 10)
                    }

                    GlassCard {
                        DatePicker("Next encounter", selection: $date, in: Date()...,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(Theme.accent)
                            .colorScheme(.dark)
                    }

                    Button {
                        store.setNextMeeting(date, for: bondID); dismiss()
                    } label: {
                        Text(daysLeft == nil ? "Set next encounter" : "Update date")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.accent).foregroundStyle(Theme.bgBottom)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                    }
                    .buttonStyle(.plain)

                    if daysLeft != nil {
                        Button(role: .destructive) {
                            store.setNextMeeting(nil, for: bondID); dismiss()
                        } label: {
                            Text("Remove").foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Encounters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { if let saved = store.nextMeeting(for: bondID) { date = saved } }
        }
    }
}
