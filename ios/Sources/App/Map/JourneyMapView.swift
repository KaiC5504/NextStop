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

    /// Follow height for in-journey navigation: close enough to read street names,
    /// far enough to see the next corner. Google's walking nav sits about here.
    static let navigationDistance: Double = 350

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

    /// Camera distance in metres below which per-leg stop dots earn their clutter.
    /// Zero means the camera has not reported yet, which must read as "too far out".
    static func showsIntermediateStops(cameraDistance: Double) -> Bool {
        cameraDistance > 0 && cameraDistance < 25_000
    }
}

struct JourneyMapView: View {
    let journey: Journey?
    /// How the map frames itself on appear. `.journey` fits the whole route (Home);
    /// `.navigation` zooms to the user at street level and follows (live journey).
    var framing: Framing = .journey
    /// The leg currently being travelled, when the caller tracks progress. Legs before
    /// it render dimmed and thinner; the leg itself slightly heavier.
    var activeLegID: String? = nil
    /// Height of whatever the caller lays over the bottom of the map, so the recenter
    /// button clears it.
    var bottomInset: CGFloat = 0
    /// Increment to re-frame the whole journey — the bar's overview button.
    var overviewTrigger: Int = 0

    enum Framing { case journey, navigation }

    @EnvironmentObject private var location: LocationProvider

    @State private var position: MapCameraPosition = .userLocation(fallback: .region(MapFraming.sydney))
    @State private var mode: CameraMode = .centered
    /// Mirror of the live camera heading, quantised: every write re-evaluates a body
    /// full of polylines, and sub-degree jitter is not worth a render.
    @State private var cameraHeading: Double = 0
    /// Unwrapped accumulator — allowed outside 0–360 — so the arrow animates the short
    /// way around instead of spinning back through a full turn at the wrap point.
    @State private var puckRotation: Double = 0
    @State private var cameraDistance: Double = 0
    /// Set on the first pan, recenter or overview tap. The first-fix auto-snap into
    /// navigation follow must never fight a camera the user has already taken.
    @State private var userDroveCamera = false
    @State private var navFramed = false

    var body: some View {
        // The ZStack keeps its own frame inside the safe area while the map escapes it,
        // which is what lets the recenter button align to the safe bounds.
        ZStack(alignment: .bottomTrailing) {
            Map(position: $position) {
                UserAnnotation { _ in
                    UserPuckView(rotation: location.headingDegrees != nil ? puckRotation : nil)
                }
                if let journey {
                    ForEach(Array(journey.legs.enumerated()), id: \.element.id) { index, leg in
                        let emphasis = emphasis(for: index, in: journey)
                        MapPolyline(coordinates: leg.path)
                            .stroke(
                                leg.mode.tint.opacity(emphasis.opacity),
                                style: StrokeStyle(
                                    lineWidth: (leg.mode.isWalking ? 4 : 7) + emphasis.extraWidth,
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: leg.mode.isWalking ? [2, 8] : []
                                )
                            )
                    }
                    if MapFraming.showsIntermediateStops(cameraDistance: cameraDistance) {
                        ForEach(journey.transitLegs) { leg in
                            ForEach(leg.stops.dropFirst().dropLast()) { stop in
                                Annotation(StopName.short(stop.name), coordinate: stop.coordinate) { stopDot(leg.mode) }
                            }
                        }
                        .annotationTitles(.hidden)
                    }
                    ForEach(journey.transitLegs) { leg in
                        if let start = leg.path.first {
                            Annotation(StopName.short(leg.originName), coordinate: start) { interchangeDot(leg.mode) }
                        }
                    }
                    if let final = journey.legs.last, let end = final.path.last {
                        Annotation(StopName.short(final.destinationName), coordinate: end) { interchangeDot(final.mode) }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            recenterButton
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: mode)
        .onMapCameraChange(frequency: .continuous) { context in
            syncCamera(context.camera)
        }
        .onChange(of: journey?.id) { _, _ in frame() }
        .onChange(of: location.headingDegrees) { _, _ in updatePuckRotation() }
        .onChange(of: cameraHeading) { _, _ in updatePuckRotation() }
        .onChange(of: location.coordinate == nil) { _, unavailable in
            if unavailable {
                mode = mode.reduced(.locationUnavailable)
            } else if framing == .navigation, !navFramed, !userDroveCamera,
                      let coordinate = location.coordinate {
                // The screen opened before the first fix and fell back to the route
                // overview; the fix arriving is the cue to start navigating.
                frameNavigation(on: coordinate)
            }
        }
        .onChange(of: overviewTrigger) { _, _ in
            userDroveCamera = true
            frameJourney()
        }
        .onAppear { frame() }
    }

    @ViewBuilder
    private var recenterButton: some View {
        if location.coordinate != nil {
            Button {
                userDroveCamera = true
                apply(mode.reduced(.recenterTapped))
            } label: {
                Image(systemName: recenterGlyph)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(mode == .free ? Theme.Colors.textSecondary : Theme.Colors.userPuck)
                    .frame(width: 44, height: 44)
                    .glassSurface(cornerRadius: 22)
            }
            .padding(.trailing, Theme.Spacing.m)
            .padding(.bottom, bottomInset + Theme.Spacing.m)
            .animation(.snappy, value: mode)
        }
    }

    private var recenterGlyph: String {
        switch mode {
        case .free: "location"
        case .centered: "location.fill"
        case .following: "location.north.line.fill"
        }
    }

    private func apply(_ newMode: CameraMode) {
        mode = newMode
        switch newMode {
        case .free:
            break
        case .centered:
            // Whether followsHeading:false animates an existing rotation back to north
            // cannot be verified without a device. If it does not, the fix belongs here
            // alone: an explicit .camera write at heading 0, then hand over to
            // .userLocation. The reducer and tests stay untouched either way.
            withAnimation(.easeInOut(duration: 0.4)) {
                position = .userLocation(followsHeading: false, fallback: .region(MapFraming.sydney))
            }
        case .following:
            withAnimation(.easeInOut(duration: 0.4)) {
                position = .userLocation(followsHeading: true, fallback: .region(MapFraming.sydney))
            }
        }
    }

    /// Behind-the-user legs stay visible as context but must not compete with what is
    /// left to travel.
    private func emphasis(for index: Int, in journey: Journey) -> (opacity: Double, extraWidth: CGFloat) {
        guard let activeLegID,
              let activeIndex = journey.legs.firstIndex(where: { $0.id == activeLegID })
        else { return (1, 0) }
        if index < activeIndex { return (0.35, -2) }
        if index == activeIndex { return (1, 1) }
        return (1, 0)
    }

    private func syncCamera(_ camera: MapCamera) {
        if abs(camera.heading - cameraHeading) > 0.5 {
            cameraHeading = camera.heading
        }
        // 5% steps: enough to catch the stop-dot zoom threshold without re-rendering
        // the polylines on every frame of a pinch.
        if cameraDistance == 0 || abs(camera.distance - cameraDistance) > cameraDistance * 0.05 {
            cameraDistance = camera.distance
        }
        // A camera moved by a gesture flips positionedByUser; programmatic writes never
        // do. This is the pan-exits-follow signal.
        if position.positionedByUser && mode != .free {
            userDroveCamera = true
            mode = mode.reduced(.userPanned)
        }
    }

    private func updatePuckRotation() {
        guard let heading = location.headingDegrees else { return }
        let target = HeadingGeometry.screenRotation(deviceHeading: heading, cameraHeading: cameraHeading)
        puckRotation = HeadingGeometry.continuousRotation(from: puckRotation, to: target)
    }

    private func stopDot(_ mode: TransitMode) -> some View {
        Circle()
            .fill(Theme.Colors.background)
            .frame(width: 6, height: 6)
            .overlay(Circle().stroke(mode.tint, lineWidth: 1.5))
    }

    private func interchangeDot(_ mode: TransitMode) -> some View {
        Circle()
            .fill(Theme.Colors.background)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(mode.tint, lineWidth: 4))
            .shadow(color: .black.opacity(0.4), radius: 3)
    }

    private func frame() {
        if framing == .navigation, let coordinate = location.coordinate {
            frameNavigation(on: coordinate)
        } else {
            frameJourney()
        }
    }

    private func frameJourney() {
        guard let journey, let region = MapFraming.region(for: journey) else { return }
        mode = mode.reduced(.journeyFramed)
        withAnimation(.easeInOut(duration: 0.6)) { position = .region(region) }
    }

    private func frameNavigation(on coordinate: CLLocationCoordinate2D) {
        navFramed = true
        mode = .following
        withAnimation(.easeInOut(duration: 0.6)) {
            position = .camera(MapCamera(
                centerCoordinate: coordinate,
                distance: MapFraming.navigationDistance, heading: 0, pitch: 0
            ))
        }
        // .userLocation inherits whatever camera distance is current, so follow can
        // only take over after the zoom-in write has landed.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard mode == .following else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                position = .userLocation(followsHeading: true, fallback: .region(MapFraming.sydney))
            }
        }
    }
}
