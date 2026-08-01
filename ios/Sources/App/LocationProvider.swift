import CoreLocation

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    /// `ambient` is enough to pick a journey origin. `navigation` is what a moving puck
    /// and heading arrow need — hundred-metre fixes make the dot visibly wander at
    /// walking pace. The values mirror the spike's proven `LocationUpdatesHolder`.
    enum Fidelity {
        case ambient, navigation
    }

    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy?
    /// Degrees clockwise from north — true heading when a fix allows declination,
    /// magnetic otherwise. Nil until the compass produces a usable reading.
    @Published private(set) var headingDegrees: Double?
    /// Compass confidence in degrees. Nil means the reading is unusable and the arrow
    /// should hide rather than point somewhere invented.
    @Published private(set) var headingAccuracy: Double?
    @Published private(set) var authorisation: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    /// Read-only window for tests; the manager itself stays private.
    var desiredAccuracy: CLLocationAccuracy { manager.desiredAccuracy }

    override init() {
        super.init()
        manager.delegate = self
        // Two degrees is barely perceptible on a 13pt arrow; anything finer just
        // re-renders a polyline-heavy map for no visible movement.
        manager.headingFilter = 2
        apply(.ambient)
        authorisation = manager.authorizationStatus
        // CI screenshots need the heading arrow and the simulator has no compass.
        if let fake = UserDefaults.standard.string(forKey: "fakeHeading"),
           let degrees = Double(fake) {
            ingest(headingDegrees: degrees, accuracy: 15)
        }
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    func start() {
        // iOS 26 implicitly raises the permission prompt when updates start while the
        // status is undetermined — not just on requestWhenInUse. CI launches can never
        // tap that dialog (it photobombed every screenshot), so under -initialScreen
        // the stream only starts once simctl's grant has taken effect.
        if authorisation == .notDetermined,
           UserDefaults.standard.string(forKey: "initialScreen") != nil {
            return
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func set(fidelity: Fidelity) { apply(fidelity) }

    private func apply(_ fidelity: Fidelity) {
        switch fidelity {
        case .ambient:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.activityType = .other
        case .navigation:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.activityType = .otherNavigation
        }
    }

    /// Delegate callbacks funnel through these so tests and the CI fake can inject
    /// readings — `CLHeading` has no usable initialiser.
    func ingest(location: CLLocation) {
        coordinate = location.coordinate
        horizontalAccuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
    }

    func ingest(headingDegrees: Double, accuracy: Double) {
        guard accuracy >= 0 else {
            self.headingDegrees = nil
            self.headingAccuracy = nil
            return
        }
        self.headingDegrees = headingDegrees
        self.headingAccuracy = accuracy
    }

    /// EFA wants longitude before latitude here, unlike the `coords` arrays it returns.
    /// Six decimal places is roughly 0.1 m — more than enough, and shorter than the default
    /// description, which can render in scientific notation.
    ///
    /// `nonisolated` because it reads no state; inheriting the class's main-actor isolation
    /// only stops tests and background callers from using a pure formatter.
    nonisolated static func tfnswOriginString(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f:%.6f:EPSG:4326", coordinate.longitude, coordinate.latitude)
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.ingest(location: last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // True heading needs a location fix for declination; -1 marks it unavailable.
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in self.ingest(headingDegrees: degrees, accuracy: accuracy) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorisation = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.start()
            }
        }
    }
}
