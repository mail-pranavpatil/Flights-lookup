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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        locationError = nil
        if let last = locations.last { SkyAlerts.saveLocation(last.coordinate) }
        guard let last = locations.last, !geocoder.isGeocoding else { return }
        Task {
            guard let mark = try? await geocoder.reverseGeocodeLocation(last).first else { return }
            let name = [mark.locality, mark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
            placeName = name.isEmpty ? nil : name
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = "Couldn't get your location. Check that Location Services are enabled."
    }
}
