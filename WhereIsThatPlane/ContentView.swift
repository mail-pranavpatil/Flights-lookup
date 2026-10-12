import SwiftUI
import UIKit
import CoreLocation
import UserNotifications

enum SkyPalette {
    static let ink = Color(red: 16.0/255.0, green: 17.0/255.0, blue: 20.0/255.0)
    static let ivory = Color(red: 247.0/255.0, green: 245.0/255.0, blue: 239.0/255.0)
    static let gold = Color(red: 245.0/255.0, green: 189.0/255.0, blue: 69.0/255.0)
    static let radarBlue = Color(red: 83.0/255.0, green: 107.0/255.0, blue: 255.0/255.0)
    static let slate = Color(red: 116.0/255.0, green: 119.0/255.0, blue: 131.0/255.0)
    static let mistBlue = Color(red: 221.0/255.0, green: 231.0/255.0, blue: 255.0/255.0)
    static let lilac = Color(red: 220.0/255.0, green: 215.0/255.0, blue: 255.0/255.0)
    static let cardWhite = Color.white
    static let divider = Color(red: 232.0/255.0, green: 231.0/255.0, blue: 226.0/255.0)
    /// Deeper end of the radar gradient so white text keeps AA contrast.
    static let indigo = Color(red: 64.0/255.0, green: 77.0/255.0, blue: 217.0/255.0)
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var model = HomeViewModel()
    @State private var detailsItem: RankedAircraft?
    /// adsbdb routes by callsign (unverified; views check them with `Aircraft.verifiedRoute`).
    @State private var routes: [String: FlightRoute] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SkyHeaderView(placeName: locationManager.placeName, hasLocation: locationManager.location != nil, lastUpdated: model.lastUpdated) {
                        withAnimation(reduceMotion ? nil : .easeInOut) { proxy.scrollTo("alerts", anchor: .top) }
                    }
                    hero
                    if case .error(let message) = model.state, model.selected != nil {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(SkyPalette.ink)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(SkyPalette.cardWhite.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if model.ranked.count > 1 { nearbySection }
                    SkyActivityCard(items: model.ranked, userLocation: locationManager.location, selectedID: model.selected?.id,
                                    hasData: model.lastUpdated != nil, isRefreshing: model.isRefreshing, onRefresh: refresh)
                    SkyAlertsSettingsRow().id("alerts")
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background(SkyBackground())
        .preferredColorScheme(.light)
        .task { await model.refresh(using: locationManager) }
        .onChange(of: locationManager.authorizationStatus) { _, _ in refresh() }
        .onChange(of: locationManager.location) { _, newValue in
            if newValue != nil && model.lastUpdated == nil { refresh() }
        }
        .onChange(of: locationManager.locationError) { _, value in
            if let value { model.locationFailed(value) }
        }
        .task(id: "\(model.lastUpdated?.timeIntervalSince1970 ?? 0)|\(model.selected?.id ?? "")") {
            // Selected plane first, then the first few cards; one request at a time to respect adsbdb.
            let lookup = RouteLookupService()
            let wanted = ([model.selected].compactMap { $0 } + model.ranked.prefix(6)).compactMap(\.aircraft.knownCallsign)
            for callsign in wanted where routes[callsign] == nil {
                let route = await lookup.route(callsign: callsign)
                if Task.isCancelled { return }
                if let route { routes[callsign] = route }
            }
        }
        .sheet(item: $detailsItem) { item in
            FlightDetailsView(initial: item, model: model, userLocation: locationManager.location, onRefresh: refresh)
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func refresh() { Task { await model.refresh(using: locationManager) } }

    private func route(for item: RankedAircraft) -> FlightRoute? {
        item.aircraft.knownCallsign.flatMap { routes[$0] }
    }

    @ViewBuilder private var hero: some View {
        if let item = model.selected {
            HeroAircraftCard(item: item, route: route(for: item), isRefreshing: model.isRefreshing, onDiscover: { detailsItem = item }, onRefresh: refresh)
        } else {
            switch model.state {
            case .locationPermissionRequired:
                HeroStatusCard(icon: "location.circle", title: "Where are you looking?",
                               message: "Your location is used only to find aircraft near you. It never leaves your device except as a search area.",
                               actionTitle: locationManager.authorizationStatus == .notDetermined ? "Allow location" : "Open Settings") {
                    if locationManager.authorizationStatus == .notDetermined {
                        locationManager.requestLocation()
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            case .empty:
                HeroStatusCard(icon: "cloud", title: "A quiet patch of sky",
                               message: "No matching aircraft found nearby right now.", actionTitle: "Try again", action: refresh)
            case .error(let message):
                HeroStatusCard(icon: "exclamationmark.triangle", title: "Couldn't reach the sky",
                               message: message, actionTitle: "Try again", action: refresh)
            case .idle, .loading, .loaded:
                HeroStatusCard(icon: "airplane", title: "Looking for aircraft…", message: nil, showsSkeleton: true)
            }
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Around you").font(.headline).foregroundStyle(SkyPalette.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(model.ranked.prefix(12))) { item in
                        let isSelected = item.id == model.selected?.id
                        let verified = item.aircraft.verifiedRoute(route(for: item))
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) { model.selectedHex = item.id }
                        } label: {
                            NearbyAircraftCard(item: item, isSelected: isSelected, route: verified)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.accessibilitySummary(route: verified))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, -20)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A BEST GUESS, NOT RADAR VISION")
                .font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(SkyPalette.slate)
            Text("Aircraft data can be delayed or missing. The closest plane isn't guaranteed to be the one directly overhead, and route details may not be available.")
                .font(.caption).foregroundStyle(SkyPalette.slate).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

// MARK: - Background

private struct SkyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [SkyPalette.mistBlue, SkyPalette.ivory], startPoint: .top, endPoint: .center)
            RadialGradient(colors: [SkyPalette.lilac.opacity(0.7), .clear], center: .topTrailing, startRadius: 10, endRadius: 340)
            RadialGradient(colors: [SkyPalette.cardWhite.opacity(0.6), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Header

struct SkyHeaderView: View {
    let placeName: String?
    let hasLocation: Bool
    let lastUpdated: Date?
    let onAlerts: () -> Void
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("YOUR SKY, RIGHT NOW")
                        .font(.caption2.weight(.medium)).tracking(1.6).foregroundStyle(SkyPalette.slate)
                    FreshnessBadge(lastUpdated: lastUpdated)
                }
                Text("Look up.")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded)).foregroundStyle(SkyPalette.ink)
                Label(placeName ?? (hasLocation ? "Near you" : "Location needed"), systemImage: "location.fill")
                    .font(.footnote).foregroundStyle(SkyPalette.slate)
            }
            Spacer()
            Button(action: onAlerts) {
                Image(systemName: "bell.badge")
                    .font(.body.weight(.semibold)).foregroundStyle(SkyPalette.ink)
                    .frame(width: 44, height: 44)
                    .background(SkyPalette.cardWhite, in: Circle())
                    .shadow(color: SkyPalette.ink.opacity(0.08), radius: 8, y: 3)
            }
            .accessibilityLabel("Sky alerts settings")
        }
    }
}

private struct FreshnessBadge: View {
    let lastUpdated: Date?

    var body: some View {
        if let lastUpdated {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                if context.date.timeIntervalSince(lastUpdated) < SkyTiming.freshWindow {
                    LiveChip()
                } else {
                    Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(SkyPalette.slate)
                }
            }
        }
    }
}

private struct LiveChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(SkyPalette.gold).frame(width: 6, height: 6).opacity(dimmed ? 0.35 : 1)
            Text("LIVE").font(.caption2.weight(.semibold)).tracking(1)
        }
        .foregroundStyle(SkyPalette.cardWhite)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(SkyPalette.ink, in: Capsule())
        .accessibilityLabel("Live data")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dimmed = true }
        }
    }
}

// MARK: - Hero

private struct HeroBackground: View {
    var body: some View {
        ZStack {
            SkyPalette.ink
            RadialGradient(colors: [SkyPalette.gold.opacity(0.32), .clear], center: .topTrailing, startRadius: 0, endRadius: 230)
            RadialGradient(colors: [SkyPalette.radarBlue.opacity(0.38), .clear], center: .bottomLeading, startRadius: 0, endRadius: 260)
            FlightArc()
                .stroke(SkyPalette.cardWhite.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
        }
    }
}

/// Decorative route curve behind the hero content.
private struct FlightArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 20, y: rect.maxY * 0.8))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + 20, y: rect.maxY * 0.18),
                          control: CGPoint(x: rect.midX, y: rect.maxY * 0.05))
        return path
    }
}

private struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold)).tracking(1.1)
            .foregroundStyle(SkyPalette.ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint, in: Capsule())
    }
}

struct HeroAircraftCard: View {
    let item: RankedAircraft
    let route: FlightRoute?
    let isRefreshing: Bool
    let onDiscover: () -> Void
    let onRefresh: () -> Void

    private var verifiedRoute: FlightRoute? { item.aircraft.verifiedRoute(route) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Chip(text: item.confidenceLabel, tint: item.isLikelyOverhead ? SkyPalette.gold : SkyPalette.mistBlue)
                Spacer()
                Button(action: onRefresh) {
                    Group {
                        if isRefreshing { ProgressView().tint(SkyPalette.cardWhite) }
                        else { Image(systemName: "arrow.clockwise").font(.subheadline.weight(.semibold)) }
                    }
                    .foregroundStyle(SkyPalette.cardWhite)
                    .frame(width: 44, height: 44)
                    .background(SkyPalette.cardWhite.opacity(0.1), in: Circle())
                }
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh aircraft")
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.aircraft.knownCallsign ?? "Aircraft nearby")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(SkyPalette.cardWhite)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let route = verifiedRoute {
                            Text("\(route.origin.city) → \(route.destination.city)")
                                .font(.headline).foregroundStyle(SkyPalette.gold)
                            Text("Route matches live position")
                                .font(.caption).foregroundStyle(SkyPalette.cardWhite.opacity(0.6))
                        } else {
                            Text(route == nil ? "Route not identified" : "Route couldn't be confirmed")
                                .font(.subheadline).foregroundStyle(SkyPalette.cardWhite.opacity(0.65))
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "airplane")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(SkyPalette.gold)
                        // SF Symbol "airplane" points east (90°); decorative tilt when heading is unknown.
                        .rotationEffect(.degrees((item.aircraft.track ?? 45) - 90))
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(SkyPalette.gold.opacity(0.12)))
                        .shadow(color: SkyPalette.gold.opacity(0.35), radius: 14)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { pills }
                    VStack(alignment: .leading, spacing: 8) { pills }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilitySummary(route: verifiedRoute))

            Button(action: onDiscover) {
                HStack {
                    Text("Discover this flight").font(.headline)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(SkyPalette.ink)
                .padding(.horizontal, 18).padding(.vertical, 15)
                .frame(minHeight: 44)
                .background(SkyPalette.gold, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text(item.confidenceNote)
                .font(.caption).foregroundStyle(SkyPalette.cardWhite.opacity(0.65))
        }
        .padding(22)
        .background(HeroBackground())
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: SkyPalette.ink.opacity(0.18), radius: 22, y: 12)
    }

    @ViewBuilder private var pills: some View {
        if item.aircraft.altitudeFeet != nil { pill("arrow.up", item.aircraft.altitudeLabel) }
        pill("location", item.distanceLabel)
        if let direction = item.aircraft.compassDirection { pill("safari", "Heading \(direction)") }
    }

    private func pill(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.medium))
            .foregroundStyle(SkyPalette.cardWhite)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(SkyPalette.cardWhite.opacity(0.1), in: Capsule())
            .fixedSize()
    }
}

/// Loading / empty / permission / error variants of the hero slot. Shows no flight data.
private struct HeroStatusCard: View {
    let icon: String
    let title: String
    let message: String?
    var actionTitle: String? = nil
    var showsSkeleton = false
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold)).foregroundStyle(SkyPalette.gold)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(SkyPalette.cardWhite)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(SkyPalette.cardWhite.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsSkeleton {
                HStack(spacing: 8) {
                    ForEach([90.0, 80.0, 110.0], id: \.self) { width in
                        Capsule().fill(SkyPalette.cardWhite.opacity(0.12)).frame(width: width, height: 26)
                    }
                }
                .accessibilityHidden(true)
                ProgressView().tint(SkyPalette.cardWhite)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.headline).foregroundStyle(SkyPalette.ink)
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        .frame(minHeight: 44)
                        .background(SkyPalette.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroBackground())
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: SkyPalette.ink.opacity(0.18), radius: 22, y: 12)
    }
}

// MARK: - Nearby

struct NearbyAircraftCard: View {
    let item: RankedAircraft
    let isSelected: Bool
    /// Pass only a route that passed `Aircraft.verifiedRoute`.
    var route: FlightRoute? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "airplane")
                    .font(.title3)
                    .foregroundStyle(isSelected ? SkyPalette.gold : SkyPalette.radarBlue)
                Spacer()
                if let track = item.aircraft.track {
                    Image(systemName: "location.north.fill")
                        .font(.caption).foregroundStyle(SkyPalette.slate)
                        .rotationEffect(.degrees(track))
                }
            }
            Text(item.aircraft.knownCallsign ?? "Aircraft nearby")
                .font(.headline).foregroundStyle(SkyPalette.ink)
                .lineLimit(1).minimumScaleFactor(0.75)
            if let route {
                Text("\(route.origin.code) → \(route.destination.code)")
                    .font(.caption.weight(.semibold)).foregroundStyle(SkyPalette.ink)
            } else {
                Text("Route unknown").font(.caption).foregroundStyle(SkyPalette.slate)
            }
            Spacer(minLength: 4)
            Text(item.distanceLabel).font(.subheadline.weight(.semibold)).foregroundStyle(SkyPalette.ink)
            if item.aircraft.altitudeFeet != nil {
                Text(item.aircraft.altitudeLabel).font(.caption).foregroundStyle(SkyPalette.slate)
            }
        }
        .padding(14)
        .frame(width: 144, alignment: .leading)
        .frame(minHeight: 168, alignment: .topLeading)
        .background(isSelected ? SkyPalette.gold.opacity(0.14) : SkyPalette.cardWhite.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSelected ? SkyPalette.gold : .clear, lineWidth: 2)
        }
        .shadow(color: SkyPalette.ink.opacity(0.06), radius: 10, y: 4)
    }
}

// MARK: - Sky activity

struct SkyActivityCard: View {
    let items: [RankedAircraft]
    let userLocation: CLLocation?
    let selectedID: String?
    let hasData: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void

    private var summary: String {
        guard hasData else { return "Waiting for data" }
        switch items.count {
        case 0: return "No aircraft nearby"
        case 1: return "1 aircraft nearby"
        default: return "\(items.count) aircraft nearby"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sky activity").font(.headline)
                Text(summary).font(.system(.title3, design: .rounded, weight: .bold))
                Text("Based on available aircraft tracking data").font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(SkyPalette.cardWhite.opacity(0.18), in: Capsule())
                }
                .disabled(isRefreshing)
            }
            .foregroundStyle(SkyPalette.cardWhite)
            Spacer(minLength: 0)
            radar.frame(width: 120, height: 120).accessibilityHidden(true)
        }
        .padding(20)
        .background {
            ZStack {
                LinearGradient(colors: [SkyPalette.radarBlue, SkyPalette.indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [SkyPalette.lilac.opacity(0.45), .clear], center: .topTrailing, startRadius: 0, endRadius: 200)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: SkyPalette.radarBlue.opacity(0.25), radius: 18, y: 8)
    }

    private var radar: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func dot(_ point: CGPoint, _ diameter: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter))
            }
            for fraction in [1.0, 0.66, 0.33] {
                context.stroke(dot(center, radius * 2 * fraction), with: .color(.white.opacity(0.35)), lineWidth: 1)
            }
            context.fill(dot(center, 6), with: .color(.white))
            guard let user = userLocation?.coordinate else { return }
            for item in items {
                guard let coordinate = item.aircraft.coordinate else { continue }
                let bearing = CGFloat(RankedAircraft.bearing(from: user, to: coordinate) * .pi / 180)
                let r = CGFloat(min(item.distanceKM / RankedAircraft.radarRangeKM, 1)) * (radius - 5)
                let point = CGPoint(x: center.x + sin(bearing) * r, y: center.y - cos(bearing) * r)
                let isSelected = item.id == selectedID
                context.fill(dot(point, isSelected ? 10 : 6), with: .color(isSelected ? SkyPalette.gold : .white.opacity(0.9)))
            }
        }
    }
}

// MARK: - Sky alerts

struct SkyAlertsSettingsRow: View {
    @AppStorage("skyAlertsEnabled") private var enabled = false
    @State private var status: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { enabled && status != .denied }, set: setEnabled)) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sky alerts", systemImage: "bell.badge").font(.headline).foregroundStyle(SkyPalette.ink)
                    Text("Get a notification when a likely nearby aircraft passes overhead.")
                        .font(.footnote).foregroundStyle(SkyPalette.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(SkyPalette.gold)
            if status == .denied {
                Button("Notifications are off. Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
            }
            Text("Background alerts need our server, which isn't connected yet, so no alerts will arrive for now.")
                .font(.caption).foregroundStyle(SkyPalette.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(SkyPalette.cardWhite.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: SkyPalette.ink.opacity(0.06), radius: 10, y: 4)
        .task { await reloadStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reloadStatus() } }
        }
    }

    private func reloadStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Permission is requested only after the user opts in.
    private func setEnabled(_ on: Bool) {
        enabled = on
        guard on else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            await reloadStatus()
            if status == .denied { enabled = false }
        }
    }
}

#if DEBUG
private let previewPlane = RankedAircraft(
    aircraft: Aircraft(hex: "preview1", flight: "AIC101 ", lat: 18.6, lon: 73.9, alt_baro: .number(32_000), gs: 450, track: 45, t: "A20N", desc: nil, ownOp: nil, seen_pos: 2),
    distanceKM: 4.2)

#Preview("Hero card") {
    HeroAircraftCard(item: previewPlane, route: nil, isRefreshing: false, onDiscover: {}, onRefresh: {}).padding()
}

#Preview("Nearby card") {
    NearbyAircraftCard(item: previewPlane, isSelected: true).padding()
}
#endif
