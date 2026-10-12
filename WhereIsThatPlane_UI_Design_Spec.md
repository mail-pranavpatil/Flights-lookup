# Where Is That Plane? --- SwiftUI UI Design Specification

## Purpose

Redesign the existing native SwiftUI app **Where Is That Plane?** using
the supplied weather-app screenshot as the layout reference, replacing
weather data with live aircraft information. Preserve existing
aircraft/location/API logic wherever possible. This is an implementation
brief for Claude Code to apply inside the existing repository.

## Product experience

-   A glanceable live status for the user's sky.
-   A large hero card showing the most likely aircraft passing nearby.
-   Horizontally scrolling cards for other nearby aircraft.
-   A compact sky-activity/radar card.
-   Friendly colorful UI with soft gradients, rounded cards, and clear
    typography.
-   One primary action: **Discover this flight**.
-   Never invent flight numbers, routes, altitude, or destination.

## Visual direction

### Palette

Use the app logo as the source of truth: near-black, warm ivory, and
restrained aviation gold. Add electric blue/lilac as secondary accents.

-   `SkyInk`: `#101114`
-   `CloudIvory`: `#F7F5EF`
-   `AviationGold`: `#F5BD45`
-   `RadarBlue`: `#536BFF`
-   `Slate`: `#747783`
-   `MistBlue`: `#DDE7FF`
-   `Lilac`: `#DCD7FF`
-   `CardWhite`: `#FFFFFF`
-   `Divider`: `#E8E7E2`

Use gold sparingly for the important aircraft and destination. Use
blue/lilac gradients in a few cards, inspired by the supplied weather
UI, while keeping the black/ivory/gold brand recognizable.

### Typography

Use native iOS system typography: - Hero title:
`.system(size: 30, weight: .bold, design: .rounded)` - Flight number:
24--28 pt, bold - Destination / airport names: 17--20 pt, semibold -
Card titles: 15--17 pt, semibold - Metadata: 12--14 pt - Live/status
labels: 10--12 pt, semibold, uppercase with subtle tracking

Use SF Pro via `.system`; avoid new font dependencies. Keep copy concise
and high contrast.

### Shapes and depth

-   Background: warm, very light blue/ivory gradient with subtle sky
    haze.
-   Cards: 24--30 pt corner radius; avoid hard borders unless needed.
-   Shadows: soft and low-opacity.
-   Use `Material` sparingly.
-   Decorative flight-path curves, waypoint marks, and radar rings
    should not compete with data.
-   Respect safe areas and Dynamic Type; avoid fixed screen coordinates.

## Home screen layout

Build a single scrollable SwiftUI home screen that is useful at a glance
on a typical iPhone.

### 1. Header

Top row: - Left: "Your sky, right now" / "Flights overhead". - Location
label such as "Pune, Maharashtra" only when available; otherwise "Near
you" or a location-permission prompt. - Right: circular radar or
notification-settings button. - A `LIVE` chip only when aircraft data is
fresh.

Suggested hierarchy: - Eyebrow: `YOUR SKY, RIGHT NOW` (11 pt, medium,
tracked). - Main title: `Look up.` or `Flights overhead` (28--32 pt
bold). - Location: 13 pt secondary.

### 2. Hero aircraft card

A large charcoal/black card with a soft gold/blue glow and a clear
airplane silhouette. It is the visual anchor.

Content: - Chip: `LIKELY OVERHEAD` or `NEARBY FLIGHT`, according to
ranking confidence. - Airplane symbol with a subtle route arc. -
Callsign/flight number when available; otherwise `Aircraft nearby`. -
Route: show `Pune → Delhi` only if verified. Otherwise show
`Route not available yet`. - Metadata: altitude, approximate distance,
direction --- only when available. - CTA: **Discover this flight** /
**View flight details**. - Confidence note:
`Best match based on nearby aircraft position` or
`Likely overhead — not visually confirmed`.

Loading state: "Looking for aircraft..." with skeleton metadata and no
fake flight details.

Empty state: "A quiet patch of sky" / "No matching aircraft found nearby
right now." Include "Try again".

Location denied: explain location is used to find nearby aircraft and
provide a permission action.

### 3. Nearby aircraft cards

Section title: **Around you** or **Other flights nearby**. Horizontal
scrolling row of compact cards, inspired by the forecast tiles in the
reference.

Each card: - Airplane glyph or route motif. - Callsign/flight number if
available. - Route if verified; otherwise `Route unknown`. - Altitude or
distance if available. - Heading arrow only when valid. - Selected state
highlighted in gold or blue.

Use a reusable component such as `NearbyAircraftCard`. Do not hardcode
sample aircraft in production. Mock data is allowed only in previews or
isolated fixtures. Tapping a card updates the hero/detail state.

### 4. Sky activity / radar card

A medium-size card with a blue/lilac gradient or light surface: - Title:
**Sky activity** - Minimal radar illustration with concentric circles
and dots based on actual nearby results. - Summary such as
`3 aircraft nearby` using the real result count. - Optional refresh
action. - Empty state when no aircraft are available. - Caption:
`Based on available aircraft tracking data`.

### 5. Optional secondary card

Only show recent sightings if the app actually stores history. Otherwise
use a small educational "Flight facts" card or omit the section. Never
create fake history.

### 6. Bottom navigation

Only add navigation if multiple real destinations exist. For the MVP,
prefer a single scrollable home screen. Do not add non-functional tabs.

## Flight details

On hero/card tap, open a native sheet or detail screen with: -
Callsign/flight number if known. - Airline name only if reliably
mapped. - Origin and destination only when supplied by a trusted
source. - Altitude, speed, heading, position age and distance when
available. - MapKit map if user and aircraft coordinates exist. -
Timestamp for last observed position. - Clear note when route is
unavailable or unverified. - Refresh action that respects API limits.

Do not imply visual identification. Explain that the app matches nearby
aircraft using tracking data.

## Notifications UX

Add a Settings row or toggle for **Sky alerts**: - Explain: "Get a
notification when a likely nearby aircraft passes overhead." - Request
notification permission only after the user opts in. - If denied,
provide a route to iOS Settings. - Never create notifications from mock
data. - Local notifications are for testing only; production background
detection requires a backend/APNs pipeline. Do not pretend this exists
if it is not implemented. - Use verified route data only. If destination
is unknown, say "A flight passed nearby" rather than guessing.

## Interaction and accessibility

-   Subtle spring animation when selecting an aircraft.
-   Restrained live indicator animation.
-   Respect `accessibilityReduceMotion`.
-   Useful VoiceOver labels summarizing callsign/route/metadata.
-   Minimum \~44 pt button hit targets.
-   Support Dynamic Type and sufficient contrast.

## SwiftUI implementation guidance

First inspect the existing repository and preserve working code. Before
editing: 1. Find the app entry point, root view, view models, aircraft
model, API service, location manager, and notification code. 2. Identify
the actual property names in the existing aircraft model. 3. Do not
replace working location/API logic with mocks. 4. Keep networking and
location logic out of view bodies. 5. Prefer reusable views: `HomeView`,
`SkyHeaderView`, `HeroAircraftCard`, `NearbyAircraftCard`,
`SkyActivityCard`, `FlightDetailsView`, `SkyAlertsSettingsRow`. 6. Reuse
existing view models; otherwise create a small `@MainActor`
`HomeViewModel` with injected services. 7. Handle missing data safely.
8. Avoid third-party dependencies for this visual pass. 9. Compile
against the existing deployment target. 10. Keep API calls rate-limited
and show loading, empty, stale and error states.

Suggested explicit states: `loading`, `loaded(aircraft:)`, `empty`,
`locationPermissionRequired`, `error(message:)`. Reuse existing state
types if present; don't duplicate them.

## Data honesty rules

-   Never invent flight numbers, airline names, airports, destinations,
    altitude, or distance.
-   A callsign is not automatically a commercial flight number or route.
-   Only show a destination when a reliable enrichment source supplies
    it.
-   Include data freshness; don't call stale data "live."
-   The closest aircraft is a candidate, not proof of the plane the user
    saw.
-   If route enrichment isn't connected, show `Destination unavailable`
    / `Route not identified`.

## Suggested Swift palette

``` swift
import SwiftUI

enum SkyPalette {
    static let ink = Color(red: 16.0/255.0, green: 17.0/255.0, blue: 20.0/255.0)
    static let ivory = Color(red: 247.0/255.0, green: 245.0/255.0, blue: 239.0/255.0)
    static let gold = Color(red: 245.0/255.0, green: 189.0/255.0, blue: 69.0/255.0)
    static let radarBlue = Color(red: 83.0/255.0, green: 107.0/255.0, blue: 255.0/255.0)
    static let slate = Color(red: 116.0/255.0, green: 119.0/255.0, blue: 131.0/255.0)
    static let mistBlue = Color(red: 221.0/255.0, green: 231.0/255.0, blue: 255.0/255.0)
    static let lilac = Color(red: 220.0/255.0, green: 215.0/255.0, blue: 255.0/255.0)
}
```

## Acceptance checklist

-   [ ] Home screen follows the reference layout but displays aircraft
    data, not weather.
-   [ ] Logo palette is respected: black/ivory/gold with blue/lilac
    supporting accents.
-   [ ] Hero aircraft card is visually dominant and fits on an iPhone
    screen.
-   [ ] Nearby flight cards scroll horizontally and update selection.
-   [ ] All displayed flight fields come from real model data or are
    omitted.
-   [ ] Loading, empty, location-denied and API-error states are
    designed.
-   [ ] Flight details use a native sheet/screen.
-   [ ] Notification permission is requested only after user intent.
-   [ ] UI does not claim backend push notifications work until
    implemented.
-   [ ] VoiceOver, Dynamic Type, contrast and Reduce Motion are
    respected.
-   [ ] Existing aircraft fetching, location and GitHub Actions setup
    remain intact.
-   [ ] App builds successfully for the current deployment target.

## Instructions to Claude Code

Implement this specification in the current repository. Start by
inspecting the project files and report which SwiftUI views and models
you found. Then make the smallest coherent patch that achieves this
design while preserving current data/networking logic. Do not merely
output a plan: edit the files, run available project checks, and report
changed files plus build limitations. If the current folder is not the
app repository, stop and ask the user to open Claude Code in the correct
project folder.
