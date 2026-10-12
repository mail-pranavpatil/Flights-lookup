import Foundation
import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published var locationError: String?
    /// e.g. "Pune, Maharashtra"; nil until reverse geocoding succeeds.
    @Published private(set) var placeName: String?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: locationError = "Enable Location Services for Where Is That Plane in Settings."
        @unknown default: locationError = "Location access isn't available on this device."
        }
    }

    // CLLocationManager calls its delegate on the thread it was created on (main here); these hop
    // explicitly so the conformance is valid under Swift 6 isolation checking.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in didUpdate(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in locationError = "Couldn't get your location. Check that Location Services are enabled." }
    }

    private func didUpdate(_ last: CLLocation) {
        location = last
        locationError = nil
        SkyAlerts.saveLocation(last.coordinate)
        guard !geocoder.isGeocoding else { return }
        Task {
            guard let mark = try? await geocoder.reverseGeocodeLocation(last).first else { return }
            let name = [mark.locality, mark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
            placeName = name.isEmpty ? nil : name
        }
    }
}
