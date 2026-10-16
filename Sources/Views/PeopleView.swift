import SwiftUI

/// The partners list: who you're bonded with, their presence, and a way to add more.
struct PeopleView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(model.partners) { partner in
                    Button {
                        model.selectedPartnerID = partner.id
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color(rgbInt: partner.colorRGB)).frame(width: 32, height: 32)
                                if partner.online {
                                    Circle().fill(.green).frame(width: 10, height: 10)
                                        .overlay(Circle().stroke(.background, lineWidth: 2))
                                        .offset(x: 12, y: 12)
                                }
                            }
                            VStack(alignment: .leading) {
                                Text(partner.displayName)
                                Text(presenceText(partner)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if partner.id == model.selectedPartnerID {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                NavigationLink {
                    PairingView().navigationTitle("Add partner")
                } label: {
                    Label("Add a partner", systemImage: "person.badge.plus")
                }
            }
        }
    }

    private func presenceText(_ p: Partner) -> String {
        if p.online { return "Online now" }
        if let seen = p.lastSeen {
            return "Last seen " + seen.formatted(.relative(presentation: .named))
        }
        return "Offline"
    }
}
