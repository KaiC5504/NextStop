import CoreLocation

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorisation: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorisation = manager.authorizationStatus
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func start() { manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }

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
        Task { @MainActor in self.coordinate = last.coordinate }
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
