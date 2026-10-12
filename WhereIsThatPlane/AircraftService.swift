import Foundation
import CoreLocation

protocol AircraftProviding {
    func nearbyAircraft(latitude: Double, longitude: Double, radiusNM: Int) async throws -> [Aircraft]
}

/// Uses ADSB.lol's public nearby-aircraft endpoint. Its data is crowdsourced and may be incomplete.
struct ADSBLolService: AircraftProviding {
    func nearbyAircraft(latitude: Double, longitude: Double, radiusNM: Int = 25) async throws -> [Aircraft] {
        let urlString = "https://api.adsb.lol/v2/lat/\(latitude)/lon/\(longitude)/dist/\(radiusNM)"
        guard let url = URL(string: urlString) else { throw FlightDataError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FlightDataError.serverResponse
        }
        return try JSONDecoder().decode(NearbyAircraftResponse.self, from: data).ac ?? []
    }
}

enum FlightDataError: LocalizedError {
    case invalidURL, serverResponse, locationUnavailable, noAircraft
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Couldn't create the aircraft search request."
        case .serverResponse: return "The live aircraft service is temporarily unavailable. Try again in a moment."
        case .locationUnavailable: return "Allow location access to search the sky above you."
        case .noAircraft: return "No aircraft were found nearby right now. Try again in a few minutes."
        }
    }
}

struct AircraftRanker {
    /// Finds the nearest airborne aircraft. This is a best-effort guess, not visual identification.
    static func rank(_ aircraft: [Aircraft], from location: CLLocation) -> [(aircraft: Aircraft, distanceKM: Double)] {
        aircraft.compactMap { plane in
            guard let coordinate = plane.coordinate else { return nil }
            if let altitude = plane.altitudeFeet, altitude < 500 { return nil }
            let planeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let km = location.distance(from: planeLocation) / 1_000
            guard km <= 45 else { return nil }
            return (plane, km)
        }
        .sorted { lhs, rhs in
            // Distance is the strongest signal; missing callsigns are gently deprioritized.
            let lhsPenalty = lhs.aircraft.callsign == "Unknown flight" ? 2.0 : 0.0
            let rhsPenalty = rhs.aircraft.callsign == "Unknown flight" ? 2.0 : 0.0
            return lhs.distanceKM + lhsPenalty < rhs.distanceKM + rhsPenalty
        }
    }
}
