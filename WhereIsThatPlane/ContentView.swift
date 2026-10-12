import SwiftUI
import UIKit
import CoreLocation
import UserNotifications

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var model = HomeViewModel()
    @State private var detailsItem: RankedAircraft?
    /// adsbdb routes by callsign (unverified; views check them with `Aircraft.verifiedRoute`).
    @State private var routes: [String: FlightRoute] = [:]
    @State private var appearance = SkyAppearance.current(for: .now)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SkyHeaderView(placeName: locationManager.placeName, hasLocation: locationManager.location != nil,
                                  lastUpdated: model.lastUpdated, items: model.ranked) {
                        withAnimation(reduceMotion ? nil : .easeInOut) { proxy.scrollTo("alerts", anchor: .top) }
                    }
                    hero
                    if case .error(let message) = model.state, model.selected != nil {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(appearance.text)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(appearance.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .environment(\.skyAppearance, appearance)
        .preferredColorScheme(appearance.colorScheme)
        .task { await model.refresh(using: locationManager) }
        // Re-check the theme at each local hour boundary while the app is on screen (no background timer).
        .task {
            while !Task.isCancelled {
                let next = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)
                try? await Task.sleep(for: .seconds(max(1, next?.timeIntervalSinceNow ?? 3_600)))
                updateAppearance()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateAppearance() }
        }
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
                .environment(\.skyAppearance, appearance)
                .preferredColorScheme(appearance.colorScheme)
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func refresh() { Task { await model.refresh(using: locationManager) } }

    private func updateAppearance() {
        let now = SkyAppearance.current(for: .now)
        guard now != appearance else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.2)) { appearance = now }
    }

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
                HeroStatusCard(icon: "cloud", title: "Quiet skies",
                               message: "No matching aircraft nearby right now.", actionTitle: "Refresh", action: refresh)
            case .error(let message):
                HeroStatusCard(icon: "exclamationmark.triangle", title: "Couldn't load aircraft data",
                               message: message, actionTitle: "Try again", action: refresh)
            case .idle, .loading, .loaded:
                HeroStatusCard(icon: "airplane", title: "Looking for aircraft...", message: nil, showsSkeleton: true)
            }
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby flights").font(.headline).foregroundStyle(appearance.text)
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
                .padding(.vertical, 8)
            }
            .padding(.horizontal, -20)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A BEST GUESS, NOT RADAR VISION")
                .font(.caption2.weight(.semibold)).tracking(1.2)
            Text("Aircraft data can be delayed or missing. The closest plane isn't guaranteed to be the one directly overhead, and route details may not be available.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(appearance.secondary)
        .padding(.top, 4)
    }
}

// MARK: - Header

struct SkyHeaderView: View {
    let placeName: String?
    let hasLocation: Bool
    let lastUpdated: Date?
    let items: [RankedAircraft]
    let onAlerts: () -> Void
    @Environment(\.skyAppearance) private var sky
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 32

    /// Describes the aircraft data, never the weather.
    private var headline: String {
        guard lastUpdated != nil else { return "Your sky, right now" }
        if items.isEmpty { return "Quiet skies" }
        if items.contains(where: \.isLikelyOverhead) { return "Flights overhead" }
        if items.count >= 8 { return "A busy sky" }
        return "Your sky, right now"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Label(placeName ?? (hasLocation ? "Near you" : "Location needed"), systemImage: "location.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(sky.text)
                    .lineLimit(1)
                Spacer()
                Button(action: onAlerts) {
                    Image(systemName: "bell.badge")
                        .font(.body.weight(.semibold)).foregroundStyle(sky.text)
                        .frame(width: 44, height: 44)
                        .background(sky.card, in: Circle())
                        .overlay(Circle().strokeBorder(sky.cardBorder))
                }
                .accessibilityLabel("Sky alerts settings")
            }
            HStack(spacing: 8) {
                Text(SkyAppearance.greeting(for: .now)).font(.subheadline).foregroundStyle(sky.secondary)
                FreshnessBadge(lastUpdated: lastUpdated)
            }
            Text(headline)
                .font(.system(size: titleSize, weight: .bold, design: .rounded)).foregroundStyle(sky.text)
                .accessibilityAddTraits(.isHeader)
            if lastUpdated != nil {
                Text(items.count == 1 ? "1 aircraft nearby" : "\(items.count) aircraft nearby")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(sky.secondary)
            }
        }
    }
}

private struct FreshnessBadge: View {
    let lastUpdated: Date?
    @Environment(\.skyAppearance) private var sky

    var body: some View {
        if let lastUpdated {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                if context.date.timeIntervalSince(lastUpdated) < SkyTiming.freshWindow {
                    LiveChip()
                } else {
                    Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(sky.secondary)
                }
            }
        }
    }
}

private struct LiveChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.skyAppearance) private var sky
    @State private var dimmed = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(SkyPalette.liveGreen).frame(width: 6, height: 6).opacity(dimmed ? 0.35 : 1)
            Text("LIVE").font(.caption2.weight(.semibold)).tracking(1)
        }
        .foregroundStyle(sky.text)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(sky.card, in: Capsule())
        .accessibilityLabel("Live data")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dimmed = true }
        }
    }
}

// MARK: - Hero

/// Adaptive hero gradient: day haze, dusk periwinkle, night navy with stars.
private struct HeroBackground: View {
    @Environment(\.skyAppearance) private var sky

    var body: some View {
        ZStack {
            LinearGradient(colors: sky.hero, startPoint: .topLeading, endPoint: .bottomTrailing)
            CloudHaze(color: sky == .day ? .white.opacity(0.7) : SkyPalette.nightCloud.opacity(0.3))
            if sky != .day { Stars(count: sky == .night ? 24 : 10) }
            FlightArc()
                .stroke(sky.text.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
        }
    }
}

/// Curve from bottom-left to bottom-right; used for the decorative trail and the route line.
private struct FlightArc: Shape {
    var rise: CGFloat = 0.82
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.midX, y: rect.maxY - rect.height * rise * 2))
        return path
    }
}

private struct Chip: View {
    let text: String
    let highlighted: Bool
    @Environment(\.skyAppearance) private var sky

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold)).tracking(1.1)
            .foregroundStyle(highlighted ? sky.buttonText : sky.text)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(highlighted ? sky.buttonFill : sky.heroTile, in: Capsule())
    }
}

private extension View {
    func heroCardStyle(_ sky: SkyAppearance) -> some View {
        self
            .background(HeroBackground())
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(sky.cardBorder))
            .shadow(color: sky.shadow, radius: 22, y: 12)
    }
}

struct HeroAircraftCard: View {
    let item: RankedAircraft
    let route: FlightRoute?
    let isRefreshing: Bool
    let onDiscover: () -> Void
    let onRefresh: () -> Void
    @Environment(\.skyAppearance) private var sky

    private var verifiedRoute: FlightRoute? { item.aircraft.verifiedRoute(route) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Chip(text: item.confidenceLabel, highlighted: item.isLikelyOverhead)
                Spacer()
                Button(action: onRefresh) {
                    Group {
                        if isRefreshing { ProgressView().tint(sky.text) }
                        else { Image(systemName: "arrow.clockwise").font(.subheadline.weight(.semibold)) }
                    }
                    .foregroundStyle(sky.text)
                    .frame(width: 44, height: 44)
                    .background(sky.heroTile, in: Circle())
                }
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh aircraft")
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    AirlineLogo(airline: verifiedRoute?.airline, height: 24, maxWidth: 110)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.aircraft.knownCallsign ?? "Aircraft nearby")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let airline = verifiedRoute?.airline?.name {
                            Text(airline).font(.subheadline).foregroundStyle(sky.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(sky.text)
                routeRow
                metrics
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilitySummary(route: verifiedRoute))

            Button(action: onDiscover) {
                HStack {
                    Text("Discover this flight").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(sky.buttonText)
                .padding(.horizontal, 18).padding(.vertical, 15)
                .frame(minHeight: 44)
                .background(sky.buttonFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text(item.confidenceNote)
                .font(.caption).foregroundStyle(sky.secondary)
        }
        .padding(22)
        .heroCardStyle(sky)
    }

    @ViewBuilder private var routeRow: some View {
        if let route = verifiedRoute {
            HStack(alignment: .top, spacing: 8) {
                airport(route.origin, alignment: .leading)
                ZStack {
                    FlightArc().stroke(sky.accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))
                    // SF Symbol "airplane" points east, matching the left-to-right route.
                    Image(systemName: "airplane").font(.subheadline.weight(.bold)).foregroundStyle(sky.accent)
                        .offset(y: -11) // sits on the arc's apex
                }
                .frame(height: 34).frame(maxWidth: .infinity)
                .padding(.top, 4)
                airport(route.destination, alignment: .trailing)
            }
        } else {
            Label(route == nil ? "Route not identified yet" : "Route couldn't be confirmed", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline).foregroundStyle(sky.secondary)
        }
    }

    /// IATA code only when adsbdb supplied one; the city name always sits underneath.
    private func airport(_ airport: Airport, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(airport.iata_code ?? airport.city)
                .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(sky.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            if airport.iata_code != nil {
                Text(airport.city).font(.caption).foregroundStyle(sky.secondary).lineLimit(2)
            }
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .frame(maxWidth: 110, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            if item.aircraft.altitudeFeet != nil { tile("mountain.2.fill", "Altitude", item.aircraft.altitudeLabel) }
            if item.aircraft.gs != nil { tile("speedometer", "Speed", item.aircraft.speedLabel) }
            if let direction = item.aircraft.compassDirection { tile("safari", "Heading", direction.capitalized) }
            tile("location", "Distance", item.distanceLabel)
        }
    }

    private func tile(_ icon: String, _ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption2.weight(.semibold)).foregroundStyle(sky.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(sky.text)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sky.heroTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    @Environment(\.skyAppearance) private var sky

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold)).foregroundStyle(sky.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(sky.text)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(sky.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsSkeleton {
                HStack(spacing: 8) {
                    ForEach([90.0, 80.0, 110.0], id: \.self) { width in
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sky.heroTile).frame(width: width, height: 44)
                    }
                }
                .accessibilityHidden(true)
                ProgressView().tint(sky.text)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.headline).foregroundStyle(sky.buttonText)
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        .frame(minHeight: 44)
                        .background(sky.buttonFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCardStyle(sky)
    }
}

// MARK: - Nearby

struct NearbyAircraftCard: View {
    let item: RankedAircraft
    let isSelected: Bool
    /// Pass only a route that passed `Aircraft.verifiedRoute`.
    var route: FlightRoute? = nil
    @Environment(\.skyAppearance) private var sky

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                AirlineLogo(airline: route?.airline, height: 16, maxWidth: 72)
                Spacer(minLength: 4)
                if let track = item.aircraft.track {
                    Image(systemName: "location.north.fill")
                        .font(.caption).foregroundStyle(sky.secondary)
                        .rotationEffect(.degrees(track))
                }
            }
            Text(item.aircraft.knownCallsign ?? "Aircraft nearby")
                .font(.headline).foregroundStyle(sky.text)
                .lineLimit(1).minimumScaleFactor(0.75)
            if let route {
                Text("\(route.origin.iata_code ?? route.origin.city) → \(route.destination.iata_code ?? route.destination.city)")
                    .font(.caption.weight(.semibold)).foregroundStyle(sky.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("Route unknown").font(.caption).foregroundStyle(sky.secondary)
            }
            Spacer(minLength: 4)
            Text(item.distanceLabel).font(.subheadline.weight(.semibold)).foregroundStyle(sky.text)
            if item.aircraft.altitudeFeet != nil {
                Text(item.aircraft.altitudeLabel).font(.caption).foregroundStyle(sky.secondary)
            }
        }
        .padding(14)
        .frame(width: 150, alignment: .leading)
        .frame(minHeight: 172, alignment: .topLeading)
        .background(sky.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSelected ? sky.accent : sky.cardBorder, lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: isSelected ? sky.accent.opacity(0.45) : sky.shadow, radius: isSelected ? 12 : 10, y: 4)
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
    @Environment(\.skyAppearance) private var sky

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
                Label("Sky activity", systemImage: "dot.radiowaves.left.and.right").font(.headline)
                Text(summary).font(.system(.title3, design: .rounded, weight: .bold))
                Text("Based on available aircraft tracking data").font(.caption)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .disabled(isRefreshing)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            radar.frame(width: 120, height: 120).accessibilityHidden(true)
        }
        .padding(20)
        .background {
            ZStack {
                LinearGradient(colors: sky.activity, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 200)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: sky.shadow, radius: 18, y: 8)
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
                let r = CGFloat(min(item.distanceKM / RankedAircraft.radarRangeKM, 1)) * (radius - 6)
                let point = CGPoint(x: center.x + sin(bearing) * r, y: center.y - cos(bearing) * r)
                if item.id == selectedID {
                    context.stroke(dot(point, 14), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                    context.fill(dot(point, 8), with: .color(.white))
                } else {
                    context.fill(dot(point, 5), with: .color(.white.opacity(0.75)))
                }
            }
        }
    }
}

// MARK: - Sky alerts

struct SkyAlertsSettingsRow: View {
    @AppStorage(SkyAlerts.enabledKey) private var enabled = false
    @State private var status: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.skyAppearance) private var sky

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { enabled && status != .denied }, set: setEnabled)) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sky alerts", systemImage: "bell.badge").font(.headline).foregroundStyle(sky.text)
                    Text("Get notified when a likely nearby aircraft passes overhead.")
                        .font(.footnote).foregroundStyle(sky.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(sky.accent)
            if status == .denied {
                Button("Notifications are off. Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.semibold))
                .tint(sky.accent)
                .frame(minHeight: 44)
            }
            Text("iOS decides when the app can check in the background, so alerts may be delayed or missed. Real-time alerts need our server, which is coming later.")
                .font(.caption).foregroundStyle(sky.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(sky.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(sky.cardBorder))
        .shadow(color: sky.shadow, radius: 10, y: 4)
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
        guard on else { SkyAlerts.cancel(); return }
        Task {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            await reloadStatus()
            if status == .denied { enabled = false } else { SkyAlerts.schedule() }
        }
    }
}

#if DEBUG
private let previewPlane = RankedAircraft(
    aircraft: Aircraft(hex: "preview1", flight: "IGO512 ", lat: 18.6, lon: 73.9, alt_baro: .number(32_000), gs: 450, track: 45, t: "A20N", desc: nil, ownOp: nil, seen_pos: 2),
    distanceKM: 4.2)

#Preview("Hero card · day") {
    HeroAircraftCard(item: previewPlane, route: nil, isRefreshing: false, onDiscover: {}, onRefresh: {})
        .padding().background(SkyBackground())
}

#Preview("Hero card · night") {
    HeroAircraftCard(item: previewPlane, route: nil, isRefreshing: false, onDiscover: {}, onRefresh: {})
        .padding().background(SkyBackground())
        .environment(\.skyAppearance, .night).preferredColorScheme(.dark)
}

#Preview("Nearby card") {
    NearbyAircraftCard(item: previewPlane, isSelected: true).padding().background(SkyBackground())
}
#endif
