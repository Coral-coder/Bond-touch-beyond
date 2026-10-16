import MapKit
import SwiftUI

/// The map: you and every partner who's sharing, zoomed as close as possible while keeping
/// everyone in view. Tap a face to zoom to that person (and select them); the corner button
/// fits everyone again. Toggle your own location sharing at the top.
struct MapTabView: View {
    @EnvironmentObject var model: AppModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    @State private var focused: String?
    @State private var didFit = false

    private struct Pin: Identifiable {
        let id: String
        let partner: Partner?
        let coordinate: CLLocationCoordinate2D
    }

    private var pins: [Pin] {
        var out: [Pin] = model.partners.compactMap { p in
            guard let lat = p.latitude, let lng = p.longitude else { return nil }
            return Pin(id: p.id, partner: p, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        if let me = model.location.coordinate { out.append(Pin(id: "me", partner: nil, coordinate: me)) }
        return out
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $region, annotationItems: pins) { pin in
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
    }

    @ViewBuilder private func annotation(_ pin: Pin) -> some View {
        if let p = pin.partner {
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
            }
            Spacer()
        }
        .padding(14).glass(cornerRadius: 24)
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
