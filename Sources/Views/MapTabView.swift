import MapKit
import SwiftUI

/// The map: you and every partner who's sharing, zoomed as close as possible while keeping
/// everyone in view. Tap a face to zoom to that person (and select them); the corner button
/// fits everyone again. Toggle your own location sharing at the top.
struct MapTabView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var showPlaces = false
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    @State private var focused: String?
    @State private var didFit = false
    /// City and time zone where a focused partner is (reverse-geocoded on this phone).
    @State private var place: (id: String, city: String, zone: TimeZone?)?
    @State private var lookAround: MKLookAroundScene?
    @State private var showLookAround = false
    private let geocoder = CLGeocoder()

    private struct Pin: Identifiable {
        let id: String
        let partner: Partner?
        let coordinate: CLLocationCoordinate2D
        var place: SavedPlace? = nil
    }

    private var pins: [Pin] {
        var out: [Pin] = model.partners.compactMap { p in
            guard let lat = p.latitude, let lng = p.longitude else { return nil }
            return Pin(id: p.id, partner: p, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        if let me = model.location.coordinate { out.append(Pin(id: "me", partner: nil, coordinate: me)) }
        return out
    }

    /// People plus saved places (places don't count when fitting everyone in).
    private var allPins: [Pin] {
        pins + store.savedPlaces.map { Pin(id: "place-\($0.id)", partner: nil, coordinate: $0.coordinate, place: $0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $region, annotationItems: allPins) { pin in
                MapAnnotation(coordinate: pin.coordinate) { annotation(pin) }
            }
            .ignoresSafeArea()
            .onAppear { fitEveryone(animated: false) }
            .onChange(of: pins.count) { _ in if !didFit || focused == nil { fitEveryone(animated: true) } }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    sharingCard
                    Button { focused = nil; fitEveryone(animated: true) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 50, height: 50).glass(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fit everyone")
                }
                HStack {
                    Button { showPlaces = true } label: {
                        Label("Places", systemImage: "mappin.and.ellipse")
                            .font(Theme.font(13, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 44).glass(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if let me = model.location.coordinate {
                        Button { focused = nil; zoom(to: Pin(id: "me", partner: nil, coordinate: me)) } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).glass(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Centre on me")
                    }
                }
                Spacer()
                if let id = focused, let p = model.partners.first(where: { $0.id == id }) {
                    focusCard(p).padding(.bottom, 92)
                } else if pins.isEmpty {
                    Text(model.partners.isEmpty ? "Add a partner to see each other on the map"
                                                : "No one is sharing a location yet")
                        .font(Theme.font(13, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10).glass(Capsule())
                        .padding(.bottom, 92)
                }
            }
            .padding(.horizontal, 16).padding(.top, 10)
        }
        .sheet(isPresented: $showPlaces) { PlacesSheet(mapCenter: region.center) }
    }

    @ViewBuilder private func annotation(_ pin: Pin) -> some View {
        if let place = pin.place {
            VStack(spacing: 2) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                Text(place.name).font(Theme.font(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(.black.opacity(0.5)))
            }
            .accessibilityLabel("Saved place \(place.name)")
        } else if let p = pin.partner {
            let selected = p.id == focused || (focused == nil && p.id == model.selectedPartnerID)
            Button { zoom(to: pin) } label: {
                AvatarRing(name: p.displayName, ringColor: Color(rgbInt: p.colorRGB),
                           size: selected ? 58 : 46, photo: model.photo(forBond: p.id))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom to \(p.displayName)")
        } else {
            AvatarRing(name: "Me", ringColor: Theme.accent, size: 40, photo: model.myPhoto)
                .accessibilityLabel("You")
        }
    }

    private var sharingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: model.sharingLocation ? "location.fill" : "location.slash")
                .foregroundStyle(model.sharingLocation ? Theme.accent : Theme.subtitle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Share my location").foregroundStyle(.white).font(Theme.font(15, .bold))
                Text(model.sharingLocation ? "Your partners can see you" : "Off")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            Spacer()
            Toggle("Share my location", isOn: Binding(get: { model.sharingLocation },
                                                      set: { model.setLocationSharing($0) }))
                .labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 14).frame(height: 50)
        .glass(cornerRadius: 25)
    }

    private func focusCard(_ p: Partner) -> some View {
        HStack(spacing: 12) {
            AvatarRing(name: p.displayName, ringColor: Color(rgbInt: p.colorRGB), size: 44,
                       photo: model.photo(forBond: p.id), ringWidth: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.displayName).font(Theme.font(16, .heavy)).foregroundStyle(.white)
                Text(detail(p)).font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                // Where they are and their time there, and how fresh the location is.
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(whereAndWhen(p, now: ctx.date)).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                }
            }
            Spacer()
            if lookAround != nil {
                Button { showLookAround = true } label: {
                    Image(systemName: "binoculars.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 42, height: 42).glass(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Look Around at \(p.displayName)'s location")
            }
        }
        .padding(14).glass(cornerRadius: 24)
        .task(id: "\(p.id)-\(p.latitude ?? 0)-\(p.longitude ?? 0)") { await lookUp(p) }
        .sheet(isPresented: $showLookAround) {
            if let scene = lookAround { LookAroundSheet(scene: scene).ignoresSafeArea() }
        }
    }

    private func whereAndWhen(_ p: Partner, now: Date) -> String {
        var parts: [String] = []
        if let place, place.id == p.id {
            if !place.city.isEmpty { parts.append(place.city) }
            if let zone = place.zone {
                let f = DateFormatter()
                f.timeZone = zone
                f.timeStyle = .short
                parts.append(f.string(from: now))
            }
        }
        if let at = p.presence?.locationAt ?? p.lastSeen {
            parts.append("updated " + at.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }
        return parts.joined(separator: " · ")
    }

    /// The partner's city and time zone, and whether Look Around imagery exists there.
    private func lookUp(_ p: Partner) async {
        guard let lat = p.latitude, let lng = p.longitude else { place = nil; lookAround = nil; return }
        let loc = CLLocation(latitude: lat, longitude: lng)
        if let mark = try? await geocoder.reverseGeocodeLocation(loc).first {
            place = (p.id, mark.locality ?? mark.administrativeArea ?? "", mark.timeZone)
        }
        lookAround = try? await MKLookAroundSceneRequest(coordinate: loc.coordinate).scene
    }

    private func detail(_ p: Partner) -> String {
        var parts: [String] = [p.online ? "Online" : "Offline"]
        if let me = model.location.coordinate, let lat = p.latitude, let lng = p.longitude {
            let m = CLLocation(latitude: me.latitude, longitude: me.longitude)
                .distance(from: CLLocation(latitude: lat, longitude: lng))
            parts.append(MKDistanceFormatter().string(fromDistance: m))
        }
        return parts.joined(separator: " · ")
    }

    private func zoom(to pin: Pin) {
        focused = pin.id
        if let p = pin.partner { model.selectedPartnerID = p.id }
        withAnimation(.easeInOut(duration: 0.6)) {
            region = MKCoordinateRegion(center: pin.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        }
    }

    /// The closest zoom that still contains every pin.
    private func fitEveryone(animated: Bool) {
        let coords = pins.map(\.coordinate)
        guard !coords.isEmpty else { return }
        didFit = true
        let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!, minLng = lngs.min()!, maxLng = lngs.max()!
        let target = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.02),
                                   longitudeDelta: max((maxLng - minLng) * 1.5, 0.02)))
        if animated { withAnimation(.easeInOut(duration: 0.6)) { region = target } } else { region = target }
    }
}

/// Apple's Look Around at a partner's location (the original shows Street View).
private struct LookAroundSheet: UIViewControllerRepresentable {
    let scene: MKLookAroundScene
    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        MKLookAroundViewController(scene: scene)
    }
    func updateUIViewController(_ vc: MKLookAroundViewController, context: Context) { vc.scene = scene }
}

/// Saved places: arriving at one sends your partners a touch saying so ("📍 Arrived at Home").
private struct PlacesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    let mapCenter: CLLocationCoordinate2D
    @State private var name = ""
    @State private var useMapCentre = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (Home, Work…)", text: $name)
                    Picker("Where", selection: $useMapCentre) {
                        Text("Where I am").tag(false)
                        Text("Map centre").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Button("Save place") { add() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (!useMapCentre && model.location.coordinate == nil))
                } footer: {
                    Text("When you arrive at a saved place, your partners feel a touch on their bracelet saying so. Needs location access set to Always.")
                }
                if !store.savedPlaces.isEmpty {
                    Section("Saved") {
                        ForEach($store.savedPlaces) { $place in
                            Toggle(isOn: $place.notifyPartners) {
                                Label(place.name, systemImage: "mappin.circle.fill")
                            }
                        }
                        .onDelete { store.savedPlaces.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func add() {
        let at = useMapCentre ? mapCenter : (model.location.coordinate ?? mapCenter)
        store.savedPlaces.append(SavedPlace(name: name.trimmingCharacters(in: .whitespaces),
                                            latitude: at.latitude, longitude: at.longitude))
        name = ""
    }
}
