import SwiftUI

/// Your profile: name, colour, and what you share about yourself (a line about you,
/// pronouns, birthday, the things you like). Every partner sees it; edits go out a moment
/// after you stop typing.
struct MyProfileView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var color: Color = .pink
    @State private var about = AboutMe()
    @State private var adding: AboutMe.AboutItem?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AvatarRing(name: store.profile.name, ringColor: Color(rgbInt: store.profile.colorRGB),
                               size: 64, photo: model.myPhoto)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name", text: $store.profile.name)
                            .font(Theme.font(20, .heavy))
                        TextField("Pronouns (optional)", text: $about.pronouns)
                            .font(Theme.font(14)).foregroundStyle(Theme.subtitle)
                    }
                }
                ColorPicker("Your colour", selection: $color, supportsOpacity: false)
                Toggle("Birthday", isOn: Binding(get: { about.birthday != nil },
                                                 set: { about.birthday = $0 ? (about.birthday ?? Date()) : nil }))
                if let birthday = about.birthday {
                    DatePicker("Date", selection: Binding(get: { birthday }, set: { about.birthday = $0 }),
                               displayedComponents: .date)
                }
            }

            Section {
                TextField("A little about you", text: $about.bio, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("About me")
            }

            Section {
                ForEach(about.items) { item in
                    Button { adding = item } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.label).font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
                            Spacer()
                            Text(item.value).font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .onDelete { about.items.remove(atOffsets: $0) }
                .onMove { about.items.move(fromOffsets: $0, toOffset: $1) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AboutMe.ideas.filter { idea in !about.items.contains { $0.label == idea } }, id: \.self) { idea in
                            Button(idea) { adding = AboutMe.AboutItem(label: idea, value: "") }
                                .font(Theme.font(12, .bold)).foregroundStyle(Theme.title)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Theme.ink.opacity(0.1)))
                                .buttonStyle(.plain)
                        }
                        Button { adding = AboutMe.AboutItem(label: "", value: "") } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                }
            } header: {
                Text("Things I like")
            } footer: {
                Text("Your partners see your profile. On Us, it sits side by side with theirs.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("My profile")
        .toolbar { EditButton() }
        .sheet(item: $adding) { item in
            AboutItemEditor(item: item) { saved in
                if let i = about.items.firstIndex(where: { $0.id == saved.id }) {
                    about.items[i] = saved
                } else {
                    about.items.append(saved)
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            color = Color(rgbInt: store.profile.colorRGB)
            about = store.profile.about ?? AboutMe()
            loaded = true
        }
        .onChange(of: color) {
            store.profile.colorRGB = $0.rgbInt
            model.bracelet.setUserColor($0.rgbInt)
        }
        .onChange(of: about) { if loaded { store.profile.about = $0 } }
        // Send once the edits settle (typing changes these on every key).
        .task(id: store.profile) {
            guard loaded else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await model.publishProfile()
        }
    }
}

/// Adds or edits one "thing I like".
private struct AboutItemEditor: View {
    @State var item: AboutMe.AboutItem
    let onSave: (AboutMe.AboutItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("What, e.g. Favourite flowers", text: $item.label)
                TextField("e.g. Peonies", text: $item.value, axis: .vertical)
            }
            .navigationTitle(item.value.isEmpty ? "Add" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(item); dismiss() }
                        .disabled(item.label.trimmingCharacters(in: .whitespaces).isEmpty
                                  && item.value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Someone's profile as a card: pronouns, birthday, their line about themselves and the things
/// they like. Shown on a partner's page.
struct AboutCard: View {
    let name: String
    let about: AboutMe?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("About \(name)").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                if let pronouns = about?.pronouns, !pronouns.isEmpty {
                    Text(pronouns).font(Theme.font(13, .semibold)).foregroundStyle(Theme.subtitle)
                }
                Spacer()
            }
            if let about, !about.isEmpty {
                if !about.bio.isEmpty {
                    Text(about.bio).font(Theme.font(15)).foregroundStyle(Theme.title)
                }
                if let birthday = about.birthday {
                    AboutRow(label: "Birthday", value: birthday.formatted(.dateTime.month(.wide).day()))
                }
                ForEach(about.items) { AboutRow(label: $0.label, value: $0.value) }
            } else {
                Text("\(name) hasn't filled in their profile yet.")
                    .font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 22)
    }
}

private struct AboutRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.font(13, .semibold)).foregroundStyle(Theme.subtitle)
            Spacer()
            Text(value).font(Theme.font(14, .bold)).foregroundStyle(Theme.title).multilineTextAlignment(.trailing)
        }
    }
}

/// Us: your profile and your partner's, side by side. The things you've both filled in line
/// up row by row, with what you have in common marked.
struct UsProfilesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    var body: some View {
        let partner = model.selectedPartner
        let mine = store.profile.about ?? AboutMe()
        let theirs = partner.flatMap { model.partnerAbout($0.id) } ?? AboutMe()
        let labels = Self.labels(mine, theirs)
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    person(name: store.profile.name, color: store.profile.colorRGB, photo: model.myPhoto, about: mine)
                    person(name: partner?.displayName ?? "Them", color: partner?.colorRGB ?? 0xFF4081,
                           photo: model.photo(forBond: partner?.id), about: theirs)
                }

                VStack(spacing: 0) {
                    if labels.isEmpty {
                        Text("Add the things you like to your profile, and they line up here with \(partner?.displayName ?? "your partner")'s.")
                            .font(Theme.font(13)).foregroundStyle(Theme.subtitle).padding(16)
                    }
                    ForEach(labels, id: \.self) { label in
                        let a = mine.items.first { $0.label.lowercased() == label.lowercased() }?.value ?? ""
                        let b = theirs.items.first { $0.label.lowercased() == label.lowercased() }?.value ?? ""
                        let same = !a.isEmpty && a.lowercased() == b.lowercased()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(label).font(Theme.font(12, .heavy)).foregroundStyle(Theme.subtitle)
                                if same { Image(systemName: "heart.fill").font(.system(size: Theme.s(10))).foregroundStyle(Theme.accent) }
                            }
                            HStack(alignment: .top, spacing: 12) {
                                Text(a.isEmpty ? "—" : a).frame(maxWidth: .infinity, alignment: .leading)
                                Text(b.isEmpty ? "—" : b).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if label != labels.last { Divider().overlay(Theme.ink.opacity(0.12)).padding(.horizontal, 16) }
                    }
                }
                .glass(cornerRadius: 22)

                NavigationLink { MyProfileView().screenBackground() } label: {
                    Label("Edit my profile", systemImage: "person.crop.circle")
                        .font(Theme.font(15, .bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(Theme.accent).glass(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .navigationTitle("Us")
    }

    private func person(name: String, color: Int, photo: UIImage?, about: AboutMe) -> some View {
        VStack(spacing: 6) {
            AvatarRing(name: name, ringColor: Color(rgbInt: color), size: 64, photo: photo)
            Text(name).font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            if !about.pronouns.isEmpty {
                Text(about.pronouns).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            if !about.bio.isEmpty {
                Text(about.bio).font(Theme.font(13)).foregroundStyle(Theme.title)
                    .multilineTextAlignment(.center).lineLimit(4)
            }
        }
        .padding(14).frame(maxWidth: .infinity).glass(cornerRadius: 22)
    }

    /// Every label either of you filled in, yours first, each once.
    static func labels(_ a: AboutMe, _ b: AboutMe) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for item in a.items + b.items where !item.label.isEmpty && seen.insert(item.label.lowercased()).inserted {
            out.append(item.label)
        }
        return out
    }
}
