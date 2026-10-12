import Foundation
import CoreLocation

struct Aircraft: Identifiable, Decodable, Hashable {
    let hex: String
    let flight: String?
    let lat: Double?
    let lon: Double?
    let alt_baro: AltitudeValue?
    let gs: Double?
    let track: Double?
    let t: String?
    let desc: String?
    let ownOp: String?
    /// Seconds since ADSB.lol last received a position for this aircraft.
    let seen_pos: Double?

    var id: String { hex }
    /// The broadcast callsign, or nil when none was sent. A callsign isn't necessarily a flight number.
    var knownCallsign: String? {
        let trimmed = (flight ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var callsign: String { knownCallsign ?? "Unknown flight" }
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    var altitudeFeet: Int? {
        switch alt_baro {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }
    var altitudeLabel: String {
        guard let feet = altitudeFeet else { return "Altitude unavailable" }
        if feet < 0 { return "On the ground" }
        return "\(feet.formatted()) ft"
    }
    var speedLabel: String {
        guard let gs else { return "Speed unavailable" }
        return "\(Int(gs.rounded())) kt"
    }
    var aircraftDescription: String { [ownOp, desc, t].compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Aircraft details unavailable" }
}

enum AltitudeValue: Decodable, Hashable {
    case number(Double)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let number = try? container.decode(Double.self) { self = .number(number); return }
        if let string = try? container.decode(String.self) { self = .string(string); return }
        self = .null
    }
}

struct NearbyAircraftResponse: Decodable {
    let ac: [Aircraft]?
    let total: Int?
}

// MARK: - adsbdb.com route + aircraft lookups (unknowns come back as a string and fail to decode → nil)

struct RouteResponse: Decodable {
    struct Body: Decodable { let flightroute: FlightRoute }
    let response: Body
}

struct FlightRoute: Decodable, Hashable {
    let callsign_iata: String?
    let airline: Airline?
    let origin: Airport
    let destination: Airport

    /// Great-circle length of the whole trip.
    var totalKM: Double { origin.location.distance(from: destination.location) / 1_000 }
}

struct Airline: Decodable, Hashable {
    let name: String
    let country: String?
}

struct Airport: Decodable, Hashable {
    let name: String
    let municipality: String?
    let country_name: String?
    let iata_code: String?
    let latitude: Double
    let longitude: Double

    var code: String { iata_code ?? "???" }
    var city: String { municipality ?? name }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

struct AircraftInfoResponse: Decodable {
    struct Body: Decodable { let aircraft: AircraftInfo }
    let response: Body
}

struct AircraftInfo: Decodable, Hashable {
    let type: String?
    let manufacturer: String?
    let registration: String?
    let registered_owner: String?
    let url_photo: String?
    let url_photo_thumbnail: String?
}

// MARK: - Kid-friendly fun facts (pure math on live data)

extension Aircraft {
    var speedKMH: Double? { gs.map { $0 * 1.852 } }
    var altitudeMeters: Double? { altitudeFeet.map { Double($0) * 0.3048 } }

    /// Standard-atmosphere estimate; real temperature varies with weather.
    var outsideTempC: Int? {
        guard let feet = altitudeFeet, feet > 0 else { return nil }
        return Int((15 - 1.98 * Double(min(feet, 36_000)) / 1_000).rounded())
    }

    var compassDirection: String? {
        guard let track else { return nil }
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        return names[Int((track / 45).rounded()) % 8]
    }

    var speedFact: String? {
        guard let kmh = speedKMH, kmh > 0 else { return nil }
        let cars = kmh / 100
        return "\(Int(kmh.rounded())) km/h, about \(cars.formatted(.number.precision(.fractionLength(0...1))))× faster than a car on the highway and \(Int((kmh / 110).rounded()))× faster than a cheetah!"
    }

    var heightFact: String? {
        guard let m = altitudeMeters, m > 0 else { return nil }
        let towers = Int((m / 330).rounded())
        let everest = m > 8_849 ? " That's higher than Mount Everest!" : ""
        return "\(Int(m.rounded()).formatted()) m up, like \(towers) Eiffel Towers stacked on top of each other.\(everest)"
    }

    var tempFact: String? {
        guard let c = outsideTempC else { return nil }
        return c < -30 ? "About \(c) °C outside the window, colder than a winter day in Antarctica!" : "About \(c) °C outside the window."
    }

    /// Fraction of the trip done (0...1), measured origin → plane vs plane → destination.
    func progress(on route: FlightRoute) -> (fraction: Double, kmLeft: Double)? {
        guard let coordinate else { return nil }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let flown = route.origin.location.distance(from: here) / 1_000
        let left = here.distance(from: route.destination.location) / 1_000
        guard flown + left > 0 else { return nil }
        return (flown / (flown + left), left)
    }

    func minutesToLanding(kmLeft: Double) -> Int? {
        guard let kmh = speedKMH, kmh > 50 else { return nil }
        return Int((kmLeft / kmh * 60).rounded())
    }

    /// adsbdb routes come from a callsign database and can be stale. Only trust one if the plane is
    /// near the origin→destination path, between the two, and (when known) heading toward the destination.
    func routeMatches(_ route: FlightRoute) -> Bool {
        guard let coordinate else { return false }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let earthKM = 6_371.0
        let flownKM = route.origin.location.distance(from: here) / 1_000
        let leftKM = here.distance(from: route.destination.location) / 1_000
        guard flownKM + leftKM <= route.totalKM + 100 else { return false }
        let toPlane = RankedAircraft.bearing(from: route.origin.coordinate, to: coordinate) * .pi / 180
        let toDest = RankedAircraft.bearing(from: route.origin.coordinate, to: route.destination.coordinate) * .pi / 180
        let crossTrackKM = abs(asin(sin(flownKM / earthKM) * sin(toPlane - toDest))) * earthKM
        guard crossTrackKM <= 100 else { return false }
        guard let track else { return true }
        let bearingToDest = RankedAircraft.bearing(from: coordinate, to: route.destination.coordinate)
        let turn = abs((track - bearingToDest + 540).truncatingRemainder(dividingBy: 360) - 180)
        return turn <= 60
    }

    /// The route only if it passes `routeMatches`.
    func verifiedRoute(_ route: FlightRoute?) -> FlightRoute? {
        route.flatMap { routeMatches($0) ? $0 : nil }
    }
}

#if DEBUG
enum FunFactsSelfCheck {
    static func run() {
        func plane(track: Double?, alt: Double?, lat: Double = 0, lon: Double = 0) -> Aircraft {
            Aircraft(hex: "x", flight: nil, lat: lat, lon: lon, alt_baro: alt.map { .number($0) }, gs: 450, track: track, t: nil, desc: nil, ownOp: nil, seen_pos: nil)
        }
        assert(plane(track: 0, alt: nil).compassDirection == "north")
        assert(plane(track: 350, alt: nil).compassDirection == "north")
        assert(plane(track: 135, alt: nil).compassDirection == "south-east")
        assert(plane(track: nil, alt: 0).outsideTempC == nil)
        assert(plane(track: nil, alt: 35_000).outsideTempC == -54)
        let a = Airport(name: "A", municipality: nil, country_name: nil, iata_code: "A", latitude: 0, longitude: 0)
        let b = Airport(name: "B", municipality: nil, country_name: nil, iata_code: "B", latitude: 0, longitude: 10)
        let route = FlightRoute(callsign_iata: nil, airline: nil, origin: a, destination: b)
        let p = plane(track: 90, alt: 35_000, lon: 5).progress(on: route)!
        assert(abs(p.fraction - 0.5) < 0.01)

        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        assert(RankedAircraft.bearing(from: origin, to: .init(latitude: 1, longitude: 0)) < 0.01)
        assert(abs(RankedAircraft.bearing(from: origin, to: .init(latitude: 0, longitude: 1)) - 90) < 0.01)
        assert(abs(RankedAircraft.bearing(from: origin, to: .init(latitude: 0, longitude: -1)) - 270) < 0.01)
        assert(RankedAircraft(aircraft: plane(track: nil, alt: 30_000), distanceKM: 3).isLikelyOverhead)
        assert(!RankedAircraft(aircraft: plane(track: nil, alt: nil), distanceKM: 3).isLikelyOverhead)
        assert(!RankedAircraft(aircraft: plane(track: nil, alt: 30_000), distanceKM: 20).isLikelyOverhead)
        assert(plane(track: nil, alt: nil).knownCallsign == nil)

        // Elevation-angle overhead rule.
        assert(RankedAircraft(aircraft: plane(track: nil, alt: 35_000), distanceKM: 10).isLikelyOverhead)
        assert(!RankedAircraft(aircraft: plane(track: nil, alt: 3_000), distanceKM: 7).isLikelyOverhead)

        // Route plausibility: on path heading to B passes; off path or flying away fails.
        assert(plane(track: 90, alt: 35_000, lon: 5).routeMatches(route))
        assert(!plane(track: 90, alt: 35_000, lat: 5, lon: 5).routeMatches(route))
        assert(!plane(track: 270, alt: 35_000, lon: 5).routeMatches(route))
        assert(!plane(track: 90, alt: 35_000, lon: 20).routeMatches(route))
    }
}
#endif
