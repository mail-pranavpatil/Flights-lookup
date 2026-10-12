import Foundation
import CoreLocation

enum SkyTiming {
    /// Data younger than this is labelled LIVE; older data shows its age instead.
    static let freshWindow: TimeInterval = 90
    // ponytail: fixed client-side floor between fetches to stay polite to ADSB.lol; move to server-side throttling if traffic grows.
    static let minimumRefreshInterval: TimeInterval = 15
}

struct RankedAircraft: Identifiable, Hashable {
    let aircraft: Aircraft
    let distanceKM: Double
    var id: String { aircraft.id }

    /// Matches AircraftRanker's 45 km cutoff, so every ranked plane fits on the radar.
    static let radarRangeKM = 45.0

    // ponytail: fixed 30° elevation cutoff, the one tuning knob; adjust with real sighting feedback.
    static let overheadElevationDegrees = 30.0

    /// Angle above the horizon from the user, ignoring terrain height (altitude is barometric).
    var elevationDegrees: Double? {
        guard let meters = aircraft.altitudeMeters, meters > 0 else { return nil }
        return atan2(meters, max(distanceKM * 1_000, 1)) * 180 / .pi
    }
    var isLikelyOverhead: Bool { (elevationDegrees ?? 0) >= Self.overheadElevationDegrees }
    var confidenceLabel: String { isLikelyOverhead ? "LIKELY OVERHEAD" : "NEARBY AIRCRAFT" }
    var confidenceNote: String { isLikelyOverhead ? "Likely overhead — not visually confirmed" : "Best match based on nearby aircraft position" }
    var distanceLabel: String { "\(distanceKM.formatted(.number.precision(.fractionLength(1)))) km away" }

    func accessibilitySummary(route: FlightRoute?) -> String {
        var parts = [aircraft.knownCallsign.map { "Flight \($0)" } ?? "Aircraft nearby"]
        parts.append(route.map { "\($0.origin.city) to \($0.destination.city)" } ?? "route not identified")
        if aircraft.altitudeFeet != nil { parts.append(aircraft.altitudeLabel) }
        parts.append(distanceLabel)
        if let direction = aircraft.compassDirection { parts.append("heading \(direction)") }
        return parts.joined(separator: ", ")
    }

    /// Initial great-circle bearing in degrees (0 = north, clockwise).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, empty, locationPermissionRequired, error(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var ranked: [RankedAircraft] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published var selectedHex: String?

    private let service: any AircraftProviding

    init(service: any AircraftProviding = ADSBLolService()) { self.service = service }

    var selected: RankedAircraft? { ranked.first { $0.id == selectedHex } ?? ranked.first }

    func refresh(using locationManager: LocationManager) async {
        switch locationManager.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            locationManager.requestLocation()
            if ranked.isEmpty { state = .locationPermissionRequired }
            return
        default: break
        }
        guard let location = locationManager.location else {
            locationManager.locationError = nil
            locationManager.requestLocation()
            if ranked.isEmpty { state = .loading }
            return
        }
        guard !isRefreshing else { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < SkyTiming.minimumRefreshInterval { return }

        isRefreshing = true
        if ranked.isEmpty { state = .loading }
        defer { isRefreshing = false }
        do {
            let fetched = try await service.nearbyAircraft(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, radiusNM: 25)
            ranked = AircraftRanker.rank(fetched, from: location).map { RankedAircraft(aircraft: $0.aircraft, distanceKM: $0.distanceKM) }
            lastUpdated = Date()
            if !ranked.contains(where: { $0.id == selectedHex }) { selectedHex = ranked.first?.id }
            state = ranked.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func locationFailed(_ message: String) {
        guard ranked.isEmpty, state != .locationPermissionRequired else { return }
        state = .error(message)
    }
}
