import Foundation
import BackgroundTasks
import CoreLocation
import UserNotifications

/// Phone-only Sky alerts: iOS background refresh checks the last known location and posts a local
/// notification for a real, likely-overhead aircraft. iOS decides when (and whether) this runs, so
/// alerts can be late or missed; real-time alerts need the server/APNs phase.
enum SkyAlerts {
    static let taskID = "com.intellobyte.flightlookup.skycheck"
    /// Shared with `SkyAlertsSettingsRow`'s @AppStorage.
    static let enabledKey = "skyAlertsEnabled"
    static let cooldown: TimeInterval = 30 * 60

    private static let latKey = "skyAlerts.lat", lonKey = "skyAlerts.lon"
    private static let lastAlertKey = "skyAlerts.lastAlertAt", hexesKey = "skyAlerts.notifiedHexes"
    private static var defaults: UserDefaults { .standard }

    /// Stored rounded to ~1 km; it never leaves the device except as the ADSB.lol search area.
    static func saveLocation(_ coordinate: CLLocationCoordinate2D) {
        defaults.set((coordinate.latitude * 100).rounded() / 100, forKey: latKey)
        defaults.set((coordinate.longitude * 100).rounded() / 100, forKey: lonKey)
    }

    static func schedule() {
        guard defaults.bool(forKey: enabledKey) else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID) }

    static func shouldAlert(hex: String, now: Date, lastAlertAt: Date?, notifiedHexes: [String]) -> Bool {
        if notifiedHexes.contains(hex) { return false }
        if let lastAlertAt, now.timeIntervalSince(lastAlertAt) < cooldown { return false }
        return true
    }

    static func check() async {
        let center = UNUserNotificationCenter.current()
        guard defaults.bool(forKey: enabledKey), defaults.object(forKey: latKey) != nil,
              await center.notificationSettings().authorizationStatus == .authorized else { return }
        let location = CLLocation(latitude: defaults.double(forKey: latKey), longitude: defaults.double(forKey: lonKey))
        guard let fetched = try? await ADSBLolService().nearbyAircraft(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, radiusNM: 25),
              let best = AircraftRanker.rank(fetched, from: location)
                .map({ RankedAircraft(aircraft: $0.aircraft, distanceKM: $0.distanceKM) })
                .first(where: \.isLikelyOverhead) else { return }

        let notified = defaults.stringArray(forKey: hexesKey) ?? []
        guard shouldAlert(hex: best.id, now: Date(), lastAlertAt: defaults.object(forKey: lastAlertKey) as? Date, notifiedHexes: notified) else { return }

        var route: FlightRoute?
        if let callsign = best.aircraft.knownCallsign {
            route = best.aircraft.verifiedRoute(await RouteLookupService().route(callsign: callsign))
        }
        let content = UNMutableNotificationContent()
        content.title = best.aircraft.knownCallsign.map { "\($0) is passing nearby" } ?? "A flight passed nearby"
        let routeText = route.map { "\($0.origin.city) → \($0.destination.city), " } ?? ""
        content.body = "\(routeText)\(best.distanceLabel). Likely overhead, not visually confirmed."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: best.id, content: content, trigger: nil))

        defaults.set(Date(), forKey: lastAlertKey)
        defaults.set(Array((notified + [best.id]).suffix(50)), forKey: hexesKey)
    }
}
