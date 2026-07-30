import MapKit
import SwiftUI

enum MapFraming {
    /// Below this the map shows a single blank tile at maximum zoom, which reads as a
    /// broken map rather than a short walk.
    private static let minimumSpan: CLLocationDegrees = 0.005

    /// Where the map sits before there is a journey or a location fix. `.automatic` frames
    /// the whole globe in that state, and that state is the first thing the app ever shows.
    static let sydney = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
        span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
    )

    static func region(for journey: Journey, padding: Double = 1.4) -> MKCoordinateRegion? {
        let points = journey.legs.flatMap(\.path)
        guard let first = points.first else { return nil }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * padding, minimumSpan),
                longitudeDelta: max((maxLon - minLon) * padding, minimumSpan)
            )
        )
    }
}

struct JourneyMapView: View {
    let journey: Journey?

    @State private var position: MapCameraPosition = .userLocation(fallback: .region(MapFraming.sydney))

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            if let journey {
                ForEach(journey.legs) { leg in
                    MapPolyline(coordinates: leg.path)
                        .stroke(
                            leg.mode.tint,
                            style: StrokeStyle(
                                lineWidth: leg.mode.isWalking ? 4 : 7,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: leg.mode.isWalking ? [2, 8] : []
                            )
                        )
                }
                ForEach(journey.transitLegs) { leg in
                    if let start = leg.path.first {
                        Annotation(leg.originName, coordinate: start) { interchangeDot(leg.mode) }
                    }
                }
                if let final = journey.legs.last, let end = final.path.last {
                    Annotation(final.destinationName, coordinate: end) { interchangeDot(final.mode) }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .preferredColorScheme(.dark)
        .onChange(of: journey?.id) { _, _ in frame() }
        .onAppear { frame() }
    }

    private func interchangeDot(_ mode: TransitMode) -> some View {
        Circle()
            .fill(Theme.Colors.background)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(mode.tint, lineWidth: 4))
            .shadow(color: .black.opacity(0.4), radius: 3)
    }

    private func frame() {
        guard let journey, let region = MapFraming.region(for: journey) else { return }
        withAnimation(.easeInOut(duration: 0.6)) { position = .region(region) }
    }
}
