import SwiftUI
import CoreLocation
import MapKit

struct FlightDetailsView: View {
    let initial: RankedAircraft
    @ObservedObject var model: HomeViewModel
    let userLocation: CLLocation?
    let onRefresh: () -> Void

    @State private var route: FlightRoute?
    @State private var info: AircraftInfo?
    @State private var isLoading = true
    private let lookup = RouteLookupService()

    /// Latest data for this aircraft after a refresh, falling back to what was tapped.
    private var current: RankedAircraft { model.ranked.first { $0.id == initial.id } ?? initial }
    private var aircraft: Aircraft { current.aircraft }
    private var stillInRange: Bool { model.ranked.contains { $0.id == initial.id } }
    private var verified: FlightRoute? { aircraft.verifiedRoute(route) }

    var body: some View {
        ZStack {
            SkyPalette.ivory.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("FLIGHT DETAILS").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(SkyPalette.slate)
                        Spacer()
                        Button(action: onRefresh) {
                            Group {
                                if model.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                            }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(SkyPalette.ink)
                            .frame(width: 44, height: 44)
                            .background(SkyPalette.cardWhite, in: Circle())
                        }
                        .disabled(model.isRefreshing)
                        .accessibilityLabel("Refresh position")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(aircraft.knownCallsign ?? "Aircraft nearby")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(SkyPalette.ink)
                        if let airline = route?.airline?.name {
                            Text(airline).font(.headline).foregroundStyle(SkyPalette.ink.opacity(0.75))
                        }
                    }
                    if !stillInRange {
                        Label("Not in the latest update. It may have left the area.", systemImage: "clock.arrow.circlepath")
                            .font(.footnote).foregroundStyle(SkyPalette.slate)
                    }
                    if let thumb = info?.url_photo_thumbnail ?? info?.url_photo, let url = URL(string: thumb) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { SkyPalette.mistBlue }
                        .frame(height: 170).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityLabel("Photo of this aircraft type")
                    }
                    Text("Where is it going?").font(.headline).foregroundStyle(SkyPalette.ink)
                    routeSection
                    flightMap
                    detailsCard
                    if !funFacts.isEmpty {
                        Text("Flight facts").font(.headline).foregroundStyle(SkyPalette.ink).padding(.top, 4)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(funFacts.indices, id: \.self) { i in factTile(funFacts[i].icon, funFacts[i].text) }
                        }
                    }
                    Text("We match nearby aircraft using public ADS-B tracking data. This isn't visual confirmation of the plane you saw.")
                        .font(.caption).foregroundStyle(SkyPalette.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
        }
        .task(id: aircraft.id) {
            isLoading = true
            async let r = lookup.route(callsign: aircraft.knownCallsign ?? "")
            async let i = lookup.info(hex: aircraft.hex)
            (route, info) = await (r, i)
            isLoading = false
        }
    }

    @ViewBuilder private var routeSection: some View {
        if let route = verified {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    airportLabel("FROM", route.origin, alignment: .leading)
                    Spacer()
                    Image(systemName: "airplane").font(.title2).foregroundStyle(SkyPalette.gold).padding(.top, 18)
                        .accessibilityHidden(true)
                    Spacer()
                    airportLabel("TO", route.destination, alignment: .trailing)
                }
                if let progress = aircraft.progress(on: route) {
                    ProgressView(value: progress.fraction).tint(SkyPalette.gold)
                    HStack {
                        Text("\(Int((progress.fraction * 100).rounded()))% of the way there")
                        Spacer()
                        Text("\(Int(progress.kmLeft.rounded()).formatted()) km to go")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(SkyPalette.slate)
                    if let minutes = aircraft.minutesToLanding(kmLeft: progress.kmLeft) {
                        Label("Lands in about \(minutes / 60 > 0 ? "\(minutes / 60) h " : "")\(minutes % 60) min (estimate)", systemImage: "clock")
                            .font(.subheadline).foregroundStyle(SkyPalette.ink)
                    }
                }
                Text("Route looked up by callsign in the adsbdb database and checked against the plane's live position and heading.")
                    .font(.caption).foregroundStyle(SkyPalette.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(SkyPalette.cardWhite, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else if isLoading {
            HStack(spacing: 10) { ProgressView().tint(SkyPalette.ink); Text("Looking up the route…") }
                .font(.subheadline).foregroundStyle(SkyPalette.slate)
        } else if route != nil {
            Text("Route couldn't be confirmed. The scheduled route for this callsign doesn't match where the plane is or where it's heading, so we're not showing it.")
                .font(.subheadline).foregroundStyle(SkyPalette.slate).fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Route not identified. Private, cargo, training and military flights often don't publish one.")
                .font(.subheadline).foregroundStyle(SkyPalette.slate).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func airportLabel(_ title: String, _ airport: Airport, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(SkyPalette.slate)
            Text(airport.code).font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(SkyPalette.ink)
            Text(airport.city).font(.headline).foregroundStyle(SkyPalette.ink)
            if let country = airport.country_name { Text(country).font(.caption).foregroundStyle(SkyPalette.slate) }
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
    }

    @ViewBuilder private var flightMap: some View {
        if let planeCoordinate = aircraft.coordinate {
            Map(interactionModes: []) {
                if let route = verified {
                    MapPolyline(coordinates: [route.origin.coordinate, route.destination.coordinate], contourStyle: .geodesic)
                        .stroke(SkyPalette.gold, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                    Marker(route.origin.code, systemImage: "airplane.departure", coordinate: route.origin.coordinate).tint(SkyPalette.ink)
                    Marker(route.destination.code, systemImage: "airplane.arrival", coordinate: route.destination.coordinate).tint(SkyPalette.gold)
                }
                if let userLocation {
                    Annotation("You", coordinate: userLocation.coordinate) {
                        Circle().fill(SkyPalette.radarBlue).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                Annotation(aircraft.callsign, coordinate: planeCoordinate) {
                    // SF Symbol "airplane" points east (90°), so rotate by track − 90.
                    Image(systemName: "airplane").font(.title2).foregroundStyle(SkyPalette.gold)
                        .rotationEffect(.degrees((aircraft.track ?? 90) - 90))
                        .shadow(radius: 2)
                }
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityLabel("Map showing your position and the aircraft")
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 12) {
            detailRow("Aircraft", aircraft.aircraftDescription)
            Divider().overlay(SkyPalette.divider)
            detailRow("Altitude", aircraft.altitudeLabel)
            Divider().overlay(SkyPalette.divider)
            detailRow("Speed", aircraft.speedLabel)
            Divider().overlay(SkyPalette.divider)
            detailRow("Heading", aircraft.track.map { "\(Int($0.rounded()))°\(aircraft.compassDirection.map { " (\($0))" } ?? "")" } ?? "Unavailable")
            Divider().overlay(SkyPalette.divider)
            detailRow("Distance from you", current.distanceLabel)
            if let lastUpdated = model.lastUpdated {
                Divider().overlay(SkyPalette.divider)
                let seenAt = lastUpdated.addingTimeInterval(-(aircraft.seen_pos ?? 0))
                detailRow("Position seen", seenAt.formatted(.relative(presentation: .numeric)))
            }
        }
        .padding(18)
        .background(SkyPalette.cardWhite, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var funFacts: [(icon: String, text: String)] {
        var facts: [(icon: String, text: String)] = []
        if let s = aircraft.speedFact { facts.append(("hare.fill", s)) }
        if let h = aircraft.heightFact { facts.append(("mountain.2.fill", h)) }
        if let t = aircraft.tempFact { facts.append(("thermometer.snowflake", t)) }
        if let d = aircraft.compassDirection { facts.append(("location.north.line.fill", "It's flying toward the \(d).")) }
        let km = current.distanceKM
        facts.append(("figure.walk", "It's \(km.formatted(.number.precision(.fractionLength(1)))) km from you. That's about \(Int((km * 1000 / 105).rounded()).formatted()) football fields!"))
        if let route = verified {
            let km = route.totalKM
            facts.append(("map.fill", "This whole trip is \(Int(km.rounded()).formatted()) km. A car would need about \(Int((km / 90).rounded())) hours of driving (if there were a road)!"))
            if let airline = route.airline { facts.append(("building.2.fill", "\(airline.name)\(airline.country.map { " comes from \($0)" } ?? " flies this plane").")) }
        }
        if let maker = info?.manufacturer, let type = info?.type { facts.append(("wrench.and.screwdriver.fill", "Built by \(maker): it's a \(type).")) }
        if let reg = info?.registration { facts.append(("number", "Every plane has its own license plate. This one's is \(reg).")) }
        if let owner = info?.registered_owner, owner != route?.airline?.name { facts.append(("person.fill", "It belongs to \(owner).")) }
        return facts
    }

    private func factTile(_ icon: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(SkyPalette.radarBlue).accessibilityHidden(true)
            Text(text).font(.caption).foregroundStyle(SkyPalette.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(SkyPalette.mistBlue.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(SkyPalette.slate)
            Spacer()
            Text(value).foregroundStyle(SkyPalette.ink).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
