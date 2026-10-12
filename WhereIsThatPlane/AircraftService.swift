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

/// Route + airframe lookups from adsbdb.com. Best effort: any failure just means "unknown".
struct RouteLookupService {
    func route(callsign: String) async -> FlightRoute? {
        guard !callsign.isEmpty else { return nil }
        if let cached = await RouteCache.shared.get(callsign) { return cached }
        let route = await fetch(RouteResponse.self, path: "callsign/\(callsign)")?.response.flightroute
        await RouteCache.shared.set(callsign, route)
        return route
    }

    func info(hex: String) async -> AircraftInfo? {
        await fetch(AircraftInfoResponse.self, path: "aircraft/\(hex)")?.response.aircraft
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async -> T? {
        guard let url = URL(string: "https://api.adsbdb.com/v0/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Tomorrow's fare for the same flight number (or its route) via our Ignav proxy (fare-proxy/), which holds the API key.
struct FareService {
    // ponytail: set to the deployed fare-proxy URL.
    static let baseURL = URL(string: "https://whereisthatplane-fare-proxy.vercel.app/api")!

    func fare(for route: FlightRoute) async -> Fare? {
        guard let origin = route.origin.iata_code, let destination = route.destination.iata_code,
              let airline = route.airline?.iata, let callsign = route.callsign_iata, callsign.hasPrefix(airline),
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return nil }
        let day = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        var url = URLComponents(url: Self.baseURL.appending(path: "fare"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            .init(name: "origin", value: origin), .init(name: "destination", value: destination),
            .init(name: "date", value: String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)),
            .init(name: "airline", value: airline), .init(name: "flight", value: String(callsign.dropFirst(airline.count))),
            .init(name: "market", value: Locale.current.region?.identifier ?? "US"),
        ]
        guard let requestURL = url.url, let (data, response) = try? await URLSession.shared.data(from: requestURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Fare.self, from: data)
    }

    static func bookingURL(_ fare: Fare) -> URL {
        baseURL.appending(path: "book").appending(queryItems: [.init(name: "id", value: fare.id)])
    }
}

/// Shared by the home screen, cards and details so each callsign is looked up once per window.
/// Misses ("no route" or a network failure, which look the same) expire sooner so they get retried.
private actor RouteCache {
    static let shared = RouteCache()
    private var entries: [String: (route: FlightRoute?, at: Date)] = [:]

    func get(_ callsign: String) -> FlightRoute?? {
        guard let entry = entries[callsign] else { return nil }
        let ttl: TimeInterval = entry.route == nil ? 5 * 60 : 30 * 60
        return Date().timeIntervalSince(entry.at) < ttl ? .some(entry.route) : nil
    }

    func set(_ callsign: String, _ route: FlightRoute?) { entries[callsign] = (route, Date()) }
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
            if let age = plane.seen_pos, age > 60 { return nil }
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
