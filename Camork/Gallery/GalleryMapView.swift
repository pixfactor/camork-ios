import CoreLocation
import MapKit
import SwiftUI

struct GalleryMapView: View {
    let sessions: [SessionWithPreview]
    let onSelect: (UUID) -> Void

    @State private var position: MapCameraPosition = .automatic

    private var locatedSessions: [SessionWithPreview] {
        sessions.filter { $0.session.firstLocation != nil }
    }

    var body: some View {
        Map(position: $position) {
            ForEach(locatedSessions, id: \.session.id) { item in
                if let location = item.session.firstLocation {
                    Annotation(
                        item.session.name,
                        coordinate: CLLocationCoordinate2D(
                            latitude: location.latitude,
                            longitude: location.longitude
                        )
                    ) {
                        Button {
                            onSelect(item.session.id)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                Text("\(item.preview.totalPhotoCount)")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.session.name))
                    }
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .overlay(alignment: .bottom) {
            if locatedSessions.isEmpty {
                ContentUnavailableView(
                    "gallery_map_empty_title",
                    systemImage: "mappin.slash",
                    description: Text("gallery_map_empty_description")
                )
                .padding(.bottom, 96)
            }
        }
        .onChange(of: locatedSessions.map(\.session.id)) { _, _ in
            position = .automatic
        }
    }
}
