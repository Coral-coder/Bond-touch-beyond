import MapKit
import SwiftUI

/// Presence — a live map of where you and your partner are. Toggle sharing to broadcast
/// your location over the relay; partners who are sharing appear as pins.
struct MapTabView: View {
    @EnvironmentObject var model: AppModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))

    private var pins: [PartnerPin] {
        model.partners.compactMap { p in
            guard let lat = p.latitude, let lng = p.longitude else { return nil }
            return PartnerPin(id: p.id, name: p.displayName, color: Color(rgbInt: p.colorRGB),
                              coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: pins) { pin in
                MapAnnotation(coordinate: pin.coordinate) {
                    VStack(spacing: 3) {
                        AvatarRing(name: pin.name, ringColor: pin.color, size: 46)
                        Text(pin.name).font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.bgBottom.opacity(0.85)))
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear { centerOnSomeone() }
            .onChange(of: model.location.coordinate?.latitude) { _ in centerOnSomeone() }

            controlCard
                .padding(.horizontal, 16).padding(.top, 10)
        }
    }

    private var controlCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: model.sharingLocation ? "location.fill" : "location.slash")
                    .foregroundStyle(model.sharingLocation ? Theme.accent : Theme.subtitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share my location").foregroundStyle(.white).font(.subheadline.weight(.semibold))
                    Text(model.sharingLocation ? "You're sharing with your partner" : "Off")
                        .font(.caption).foregroundStyle(Theme.subtitle)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.sharingLocation },
                                         set: { model.setLocationSharing($0) }))
                    .labelsHidden().tint(Theme.accent)
            }
            if model.partners.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
                HStack {
                    Text("Add a partner to see each other on the map")
                        .font(.caption).foregroundStyle(Theme.subtitle)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(Theme.bgBottom.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func centerOnSomeone() {
        if let pin = pins.first {
            region.center = pin.coordinate
        } else if let me = model.location.coordinate {
            region.center = me
        }
    }
}

struct PartnerPin: Identifiable {
    let id: String
    let name: String
    let color: Color
    let coordinate: CLLocationCoordinate2D
}
