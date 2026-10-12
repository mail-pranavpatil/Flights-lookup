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

    var id: String { hex }
    var callsign: String { (flight ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown flight" : (flight ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
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

struct FlightRoute: Decodable {
    let flightNumber: String
    let departureAirport: String?
    let arrivalAirport: String?
    let departureIATA: String?
    let arrivalIATA: String?
}
