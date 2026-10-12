import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var aircraft: [Aircraft] = []
    @State private var selectedAircraft: Aircraft?
    @State private var selectedDistanceKM: Double?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    private let service = ADSBLolService()

    private let ink = Color(red: 0.12, green: 0.15, blue: 0.17)
    private let parchment = Color(red: 0.96, green: 0.91, blue: 0.81)
    private let amber = Color(red: 0.78, green: 0.53, blue: 0.23)

    var body: some View {
        ZStack {
            parchment.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    skyCard
                    if let errorMessage {
                        Label(errorMessage, systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(ink.opacity(0.8))
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if !aircraft.isEmpty { nearbySection }
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.light)
        .onAppear { locationManager.requestLocation() }
        .onChange(of: locationManager.location) { _, newValue in
            if newValue != nil && aircraft.isEmpty { Task { await discover() } }
        }
        .onChange(of: locationManager.locationError) { _, value in
            if let value { errorMessage = value }
        }
        .sheet(item: $selectedAircraft) { plane in
            FlightDetailSheet(aircraft: plane, distanceKM: selectedDistanceKM, ink: ink, parchment: parchment, amber: amber)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "airplane").font(.headline).foregroundStyle(amber)
                Text("WHERE IS THAT PLANE?").font(.caption.weight(.bold)).tracking(2).foregroundStyle(ink.opacity(0.65))
            }
            Text("Look up.\nWonder less.")
                .font(.system(size: 42, weight: .semibold, design: .serif))
                .tracking(-1.5).lineSpacing(-2).foregroundStyle(ink)
            Text("A little curiosity about the sky above you.")
                .font(.subheadline).foregroundStyle(ink.opacity(0.7))
        }
    }

    private var skyCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "sun.max.fill").font(.system(size: 28)).foregroundStyle(amber)
                Spacer()
                Text(locationManager.location == nil ? "LOCATION NEEDED" : "YOUR SKY, RIGHT NOW")
                    .font(.caption2.weight(.bold)).tracking(1.3).foregroundStyle(.white.opacity(0.65))
            }
            if let plane = aircraft.first, let distance = AircraftRanker.rank(aircraft, from: locationManager.location ?? CLLocation()).first?.distanceKM {
                Text(plane.callsign).font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(.white)
                Text("Closest likely match · \(distance.formatted(.number.precision(.fractionLength(1)))) km away")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 14) {
                    metric("ALTITUDE", value: plane.altitudeLabel)
                    metric("HEADING", value: plane.track.map { "\(Int($0))°" } ?? "—")
                }
            } else {
                Text(isSearching ? "Listening to the sky…" : "What's flying over you?")
                    .font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(.white)
                Text("Find the nearest aircraft we can detect nearby.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            Button { Task { await discover() } } label: {
                HStack(spacing: 10) {
                    if isSearching { ProgressView().tint(ink) }
                    else { Image(systemName: "sparkle.magnifyingglass") }
                    Text(isSearching ? "Searching…" : "Discover this flight")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(ink).padding(.horizontal, 18).padding(.vertical, 16)
                .background(Color(red: 0.91, green: 0.75, blue: 0.49), in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(isSearching)
        }
        .padding(22).background(ink, in: RoundedRectangle(cornerRadius: 25))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ALSO NEARBY").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(ink.opacity(0.6))
                Spacer()
                if let lastUpdated { Text(lastUpdated, style: .time).font(.caption2).foregroundStyle(ink.opacity(0.5)) }
            }
            ForEach(Array(aircraft.prefix(5)), id: \.id) { plane in
                Button {
                    selectedAircraft = plane
                    selectedDistanceKM = locationManager.location.map { location in
                        guard let coordinate = plane.coordinate else { return 0 }
                        return location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) / 1_000
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "airplane").font(.title3).foregroundStyle(amber).frame(width: 44, height: 44).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plane.callsign).font(.headline).foregroundStyle(ink)
                            Text(plane.aircraftDescription).font(.caption).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(distanceText(for: plane)).font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                            Text(plane.altitudeLabel).font(.caption2).foregroundStyle(ink.opacity(0.6))
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(ink.opacity(0.35))
                    }
                    .padding(12).background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A BEST GUESS, NOT RADAR VISION")
                .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(ink.opacity(0.55))
            Text("Aircraft data can be delayed or missing. The closest plane isn't guaranteed to be the one directly overhead, and destination details may not be available yet.")
                .font(.caption).foregroundStyle(ink.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func distanceText(for plane: Aircraft) -> String {
        guard let location = locationManager.location, let coordinate = plane.coordinate else { return "Nearby" }
        let km = location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) / 1_000
        return "\(km.formatted(.number.precision(.fractionLength(1)))) km"
    }

    @MainActor
    private func discover() async {
        errorMessage = nil
        guard let location = locationManager.location else {
            locationManager.requestLocation()
            errorMessage = "Waiting for your location. Allow access when prompted, then tap again."
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let fetched = try await service.nearbyAircraft(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, radiusNM: 25)
            let ranked = AircraftRanker.rank(fetched, from: location)
            aircraft = ranked.map(\.aircraft)
            lastUpdated = Date()
            if let best = ranked.first {
                selectedAircraft = best.aircraft
                selectedDistanceKM = best.distanceKM
            } else {
                errorMessage = FlightDataError.noAircraft.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FlightDetailSheet: View {
    let aircraft: Aircraft
    let distanceKM: Double?
    let ink: Color
    let parchment: Color
    let amber: Color

    var body: some View {
        ZStack {
            parchment.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "airplane").font(.title).foregroundStyle(amber)
                    Spacer()
                    Text("FLIGHT DETAILS").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(ink.opacity(0.55))
                }
                Text(aircraft.callsign).font(.system(size: 32, weight: .semibold, design: .serif)).foregroundStyle(ink)
                Text("Where is it going?").font(.headline).foregroundStyle(ink)
                Text("Destination not available from the live position feed yet.")
                    .font(.subheadline).foregroundStyle(ink.opacity(0.72))
                Divider()
                detailRow("Aircraft", aircraft.aircraftDescription)
                detailRow("Altitude", aircraft.altitudeLabel)
                detailRow("Speed", aircraft.speedLabel)
                detailRow("Distance from you", distanceKM.map { "\($0.formatted(.number.precision(.fractionLength(1)))) km" } ?? "Unknown")
                Spacer(minLength: 0)
            }.padding(26)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(ink.opacity(0.58))
            Spacer()
            Text(value).foregroundStyle(ink).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}
