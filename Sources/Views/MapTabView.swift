import MapKit
import SwiftUI

/// Location-sharing map (Presence+). Shows a map with a sharing banner; the live partner
/// location sync is a later step — this establishes the screen and the share control.
struct MapTabView: View {
    @EnvironmentObject var model: AppModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
    @State private var sharing = true

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $region, showsUserLocation: true)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    pill("Pause", active: !sharing) { sharing = false }
                    pill("Sharing", active: sharing) { sharing = true }
                    Spacer()
                }
                HStack {
                    Text("Share your location together")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.black)
                    Spacer()
                    Button("INVITE") { Task { await model.createBond() } }
                        .font(.subheadline.bold()).foregroundStyle(.black)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.teal).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
    }

    private func pill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? .white : .black)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(active ? Theme.lime : Color.white))
        }
        .buttonStyle(.plain)
    }
}
