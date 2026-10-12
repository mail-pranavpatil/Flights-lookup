# Where Is That Plane? --- Complete UI/UX Design Specification

**Platform:** Native iOS / SwiftUI\
**Design direction:** Playful, premium, sky-first, adaptive day/night\
**Primary reference:** The supplied split-screen concept showing a
light-blue daytime experience and deep-indigo nighttime experience.\
**Implementation target:** Apply to the existing repository through
Claude Code. Preserve functioning flight data, location, notification,
and GitHub Actions logic.

------------------------------------------------------------------------

## 1. Product vision

Where Is That Plane? answers one tiny but delightful question:

> "That plane passing above me --- where is it going?"

The app should feel like a live sky companion: quick to glance at,
friendly, visually atmospheric, and honest about what the tracking data
can confirm.

The core flow: 1. Open the app or receive a sky alert. 2. See the
current sky mood and available nearby aircraft. 3. See the most likely
matching aircraft in a prominent flight card. 4. Tap to inspect verified
route and aircraft details. 5. Optionally enable notifications for
likely overhead aircraft.

The UI may borrow the hierarchy and atmosphere of the supplied
weather-app reference, but **must display flight information, not
weather forecasts**. Weather data should not be added unless the product
scope explicitly changes.

## 2. Design principles

-   **Sky-first:** gradients and clouds establish atmosphere; aircraft
    data remains readable.
-   **Dynamic by local time:** day and night palettes transition
    according to the user's local time.
-   **Simple, not noisy:** one hero card, one nearby flights row, one
    small sky activity section.
-   **Trustworthy:** never invent airline, flight number, altitude,
    speed, origin, destination, or flight status.
-   **Brand consistency:** blue, light blue, white, navy, and violet
    only. Remove the old yellow/brown/sepia visual direction. Use gold
    only if needed for tiny, restrained status accents; it must not
    dominate.
-   **Native iOS:** SF Symbols, system type, SwiftUI materials, safe
    areas, accessible controls.
-   **Responsive:** support smaller iPhones, large devices, Dynamic
    Type, VoiceOver, and Reduce Motion.

## 3. Color system

Use semantic design tokens rather than hardcoding colors throughout
views.

### Day theme

-   `SkyDayBackgroundTop`: `#A7D4FF`
-   `SkyDayBackgroundBottom`: `#EAF6FF`
-   `SkyDayCloud`: `#FFFFFF`
-   `SkyDayPrimaryText`: `#13264F`
-   `SkyDaySecondaryText`: `#45669D`
-   `SkyDayAccent`: `#3478F6`
-   `SkyDayCard`: `#FFFFFF` with 72--88% opacity
-   `SkyDayCardBorder`: `#FFFFFF` with subtle opacity
-   `SkyDayShadow`: soft blue-gray, low opacity

### Evening / night theme

-   `SkyNightBackgroundTop`: `#071638`
-   `SkyNightBackgroundMiddle`: `#102C70`
-   `SkyNightBackgroundBottom`: `#070D26`
-   `SkyNightCloud`: `#283D7B` / `#4058A0`
-   `SkyNightPrimaryText`: `#F7FAFF`
-   `SkyNightSecondaryText`: `#B6C8F5`
-   `SkyNightAccent`: `#65A8FF`
-   `SkyNightCard`: `#10265A` with 76--90% opacity
-   `SkyNightCardBorder`: `#8FB9FF` at low opacity
-   `SkyNightGlow`: electric blue / periwinkle with restrained bloom

### Shared semantic colors

-   `LiveGreen`: `#36D98A` --- only for fresh/live status.
-   `WarningAmber`: `#F2B84B` --- stale or uncertain state only; do not
    make this the brand color.
-   `ErrorRed`: system red / accessible semantic error.
-   `Divider`: adapt to theme.
-   `AirlineLogoSurface`: transparent or subtle neutral surface
    according to the airline asset.

### Rules

-   Day: airy blue gradient, luminous clouds, clear contrast, light
    translucent cards.
-   Evening: dusk blue / violet, gradual transition toward navy.
-   Night: deep navy, faint stars and blue-lit clouds, dark glass cards.
-   Never show a literal sun/moon solely based on arbitrary mock data.
    If decorative sun/moon is used, derive it from local time and keep
    it subtle.
-   Avoid strong yellow/brown/sepia colors from the earlier concept.
-   Keep text contrast accessible; don't put small text over busy cloud
    illustrations.

## 4. Dynamic sky background and time logic

Create a small `SkyAppearance` or equivalent abstraction, driven by the
user's **local device time**. The interface should not require weather
API access to choose a visual theme.

Suggested initial schedule: - `Day`: 07:00--16:59 - `Evening`:
17:00--19:59 - `Night`: 20:00--06:59

These are initial product defaults, not astronomical definitions. If a
reliable sunrise/sunset service is later added, it may replace fixed
time bands. Do not add a weather API only to select colors.

Use a gradual gradient transition rather than abruptly switching themes.
Animate only when appropriate and respect Reduce Motion.

Suggested API:

``` swift
enum SkyAppearance {
    case day
    case evening
    case night

    static func current(for date: Date, calendar: Calendar = .current) -> SkyAppearance {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 7..<17: return .day
        case 17..<20: return .evening
        default: return .night
        }
    }
}
```

Refresh appearance when the app enters the foreground and when the local
hour changes. Do not add a polling timer that runs continuously in the
background.

## 5. Main home screen structure

Build a native SwiftUI scroll view. The home screen should fit the
header and most of the hero flight card into the first viewport on
common iPhone sizes.

### A. Sky header

Top row: - Left: location pin + location label, e.g. "Pune, India", only
if permission and location are available. - Right: circular search or
settings/alerts control; only include search if search is implemented. -
Beneath: time-sensitive greeting such as "Good morning", "Good evening",
or "Good night". - Main headline: sky description based on aircraft
data, not weather. Examples: - "Flights overhead" - "Your sky, right
now" - "A busy sky" (only if count supports it) - "Quiet skies" (only if
data fetch succeeded and result is empty) - A live aircraft count,
e.g. "4 aircraft nearby", based on actual API results. Do not copy
placeholder counts from design references. - A small airplane
illustration or flight path trail may appear behind the title but must
not obscure the content.

Do not state "Clear skies" or describe cloud/weather conditions unless a
weather source has actually been integrated.

### B. Hero flight card --- the key component

This is the signature element of the app. It should have an adaptive
gradient: - Day: light blue to sky blue with soft cloud haze. - Evening:
periwinkle to deep blue. - Night: navy to indigo with faint stars and
moonlit cloud forms.

Use soft translucency, a rounded rectangle (24--30 pt radius), clear
information hierarchy, and minimal decorative elements.

Content order: 1. Badge: `LIKELY OVERHEAD`, `NEARBY AIRCRAFT`, or
`POSITION UPDATED` based on real state. 2. Airline logo +
callsign/flight number when known. If not known, show `Aircraft nearby`.
3. Route row: - Verified origin and destination: airport codes with
airport names below. - If only destination/origin is known, show only
known information. - If route is unknown, show
`Route not identified yet`. 4. A curved route line with a small aircraft
glyph between origin and destination. 5. Metadata tiles: altitude,
speed, heading, distance, only when available. 6. Primary button:
`Discover this flight`. 7. Tiny data-confidence label:
`Best match based on aircraft position` or equivalent.

No invented times, airport codes, routes, airline logos, aircraft
metrics, or live indicators. A callsign alone must not be presented as a
confirmed commercial flight number.

States: - Loading: animated placeholder/skeletons and "Looking for
aircraft...". - Loaded: real aircraft data. - Empty: "No matching
aircraft nearby right now" with refresh. - Location denied: explain why
location is needed and offer a permission action. - API error: explain
that aircraft data couldn't be loaded; provide retry. - Stale data: use
a "Updated X min ago" label and remove the live badge.

### C. Nearby flights carousel

Title: `Nearby flights` and optional `See all` only if a real full list
screen exists.

Horizontal card row. Each card should include: - Official airline logo
if confidently identified. - Flight number/callsign, when available. -
Route only if confirmed by the enrichment provider. - Altitude or
distance if available. - A small aircraft/heading motif. - Consistent
height and padding; avoid truncating codes.

Tapping a card selects that aircraft and updates the hero card, or opens
the details sheet. Use a subtle selected state (blue outline or glow).
Do not create fake airline branding for unknown callsigns.

If there are no nearby flights, don't show mock cards. Display a compact
empty-state tile or omit the carousel.

### D. Sky activity card

Use a compact blue/lilac card: - Title: `Sky activity`. - A radar-like
illustration with concentric rings and dots for actual aircraft returned
by the current fetch. - A real count of aircraft in the current search
area. - Optional refresh button respecting provider rate limits. -
Caption: `Based on available aircraft tracking data`.

This card must not imply full radar coverage or that all aircraft are
visible.

### E. Alerts card or settings shortcut

A compact row/card: - Icon: bell or airplane trail. - Title:
`Sky alerts`. - Copy:
`Get notified when a likely nearby aircraft passes overhead.` -
Toggle/CTA to enable alerts. - Request notification permission only
after user taps to enable. - If permission denied, show an explanation
and Settings shortcut.

Do not claim production background alerts are operational unless the
backend/APNs pipeline has actually been implemented. UI scaffolding must
remain honest.

### F. Bottom navigation

Only use a tab bar if destinations already exist and work. For an MVP, a
single scroll view is preferable. If the project already has real
screens, a restrained bottom bar may use `Sky`, `Map`, `Alerts`, and
`Saved`; do not add decorative non-functional tabs.

## 6. Flight detail sheet

Use native `.sheet` or a navigation destination. Include: -
Flight/callsign and official airline logo if identified. - Verified
origin and destination, otherwise a clear unknown-route state. -
Altitude, ground speed, heading, distance, last-seen timestamp if
available. - MapKit map with user and aircraft markers if coordinates
are available. - Explain that the app selects a likely aircraft based on
tracking data, not visual camera identification. - Refresh action with
API throttling.

## 7. Airline logos and official brand assets

**Claude Code must obtain official airline logos rather than inventing
or generically drawing airline marks.**

Implementation instructions: 1. Inspect the actual API data model and
determine whether it provides a trustworthy airline identifier,
ICAO/IATA airline code, callsign, or flight number. 2. Map an airline
only when the identifier is reliable. Do not infer an airline from an
ambiguous callsign substring. 3. Prefer assets from the airline's
official media/press/brand resources or an authorized provider's logo
service with appropriate usage rights. 4. If official assets are not
available, use a reputable licensed asset source or a simple neutral
airplane glyph. Do not scrape random Google Images results or use logos
with unclear provenance. 5. Check licensing/terms for app use,
especially commercial use, redistribution, caching, and attribution. 6.
Keep downloaded assets in a clear asset catalog,
e.g. `Assets.xcassets/Airline_<CODE>.imageset`, with consistent
transparent backgrounds and a normalized display size. 7. Preserve each
logo's original proportions. Do not recolor or distort trademarks. Use a
neutral circular/squircle backing only if necessary for consistent
contrast. 8. Add a fallback for unknown/unmapped airlines: SF Symbol
`airplane`, not a fabricated logo. 9. Cache remote logos only if the
provider's terms permit it. Never fetch a new logo for every SwiftUI
render. 10. Document the source and license/usage terms of each asset in
`docs/airline-logo-sources.md`. 11. Never hardcode airline names or
logos into live cards unless the data identifies the airline with
confidence. 12. For initial QA, only add assets for airlines that can be
reliably identified and sourced; do not try to collect every airline
before the UI works.

Use airline logo image assets in hero and nearby cards only when
available. Ensure logos remain legible in both day and night themes.

## 8. Typography and iconography

-   Use SF Pro/system fonts with rounded bold headlines where
    appropriate.
-   Use SF Symbols for location, radar, bell, refresh,
    altitude/mountain, speedometer, compass, airplane, and chevron.
-   Keep headline typography confident and friendly, not cartoonish.
-   Use short labels and avoid dense aviation jargon on the home screen.
    Advanced details belong in the detail sheet.
-   Don't use emoji as a substitute for airline logos in production.

## 9. Motion and interaction

-   Gentle fade/gradient crossfade between day/evening/night themes.
-   Subtle airplane trail animation only if inexpensive and not
    distracting.
-   Spring animation when selecting a nearby aircraft.
-   Respect `accessibilityReduceMotion`.
-   Do not animate a fake radar sweep if there is no live refresh/data
    update.
-   Buttons should have \~44 pt minimum hit targets.
-   Support VoiceOver and Dynamic Type.

## 10. SwiftUI architecture requirements

Before modifying code, Claude Code must inspect the existing repository
and report: - App entry point and current root view. - Aircraft model
and available properties. - Aircraft API service and rate limits. -
Location manager and permission flow. - Notification settings and
existing APNs work. - Current asset catalog and build/deployment
target. - GitHub Actions workflow and signing configuration.

Then make the smallest coherent patch: - Reuse existing aircraft models
and service methods. - Keep API and location code out of `body`. -
Prefer reusable views such as: - `HomeView` - `SkyHeaderView` -
`HeroFlightCard` - `NearbyFlightCard` - `SkyActivityCard` -
`FlightDetailsView` - `SkyAlertsRow` - Use an
`Observable`/`ObservableObject` view model consistent with the project's
deployment target. - Keep theme logic in `SkyAppearance` and color
tokens in `SkyPalette`. - Avoid adding packages unless there is a clear
requirement. - Preserve the current bundle identifier, entitlements,
signing, and GitHub Actions setup. - Don't replace real data with mock
values. Previews may use isolated sample fixtures only.

## 11. Suggested color tokens

``` swift
import SwiftUI

enum SkyPalette {
    static let dayTop = Color(red: 167/255, green: 212/255, blue: 1.0)
    static let dayBottom = Color(red: 234/255, green: 246/255, blue: 1.0)
    static let dayText = Color(red: 19/255, green: 38/255, blue: 79/255)
    static let daySecondary = Color(red: 69/255, green: 102/255, blue: 157/255)
    static let dayAccent = Color(red: 52/255, green: 120/255, blue: 246/255)

    static let nightTop = Color(red: 7/255, green: 22/255, blue: 56/255)
    static let nightMiddle = Color(red: 16/255, green: 44/255, blue: 112/255)
    static let nightBottom = Color(red: 7/255, green: 13/255, blue: 38/255)
    static let nightText = Color(red: 247/255, green: 250/255, blue: 1.0)
    static let nightSecondary = Color(red: 182/255, green: 200/255, blue: 245/255)
    static let nightAccent = Color(red: 101/255, green: 168/255, blue: 1.0)

    static let liveGreen = Color(red: 54/255, green: 217/255, blue: 138/255)
}
```

In Swift, ensure numeric division is floating-point
(e.g. `167.0 / 255.0`), not integer division.

## 12. Acceptance criteria

-   [ ] Day, evening, and night visual themes are implemented and follow
    local device time.
-   [ ] Theme refreshes on app foreground and hour changes without
    excessive background timers.
-   [ ] Day hero card uses airy light-blue gradients and cloud haze.
-   [ ] Night hero card uses deep navy/indigo gradients, restrained
    stars and moonlit clouds.
-   [ ] The main UI uses flight data instead of weather data.
-   [ ] Nearby cards scroll horizontally and selection works.
-   [ ] Airline logos come from documented official/licensed sources and
    only appear for confidently identified airlines.
-   [ ] Unknown airlines use a neutral airplane glyph.
-   [ ] Flight routes, metrics and counts are sourced from actual
    API/model values.
-   [ ] Loading, empty, denied-location, API-error and stale-data states
    exist.
-   [ ] Details sheet shows only verified data.
-   [ ] Notification permission is requested after explicit user intent.
-   [ ] Existing API, location, signing, and GitHub Actions logic is
    preserved.
-   [ ] Accessibility and reduced motion are supported.
-   [ ] Project compiles for its current deployment target, or build
    blockers are documented.

## 13. Instructions to Claude Code

Read this entire document before editing. Inspect the existing project
first. Then implement the design in the current SwiftUI app, preserving
working flight fetching, location, notification, signing, and CI/CD
behavior. Obtain official or properly licensed airline logo assets as
specified and document each source in `docs/airline-logo-sources.md`. Do
not scrape random image search results or fabricate logos. If no
reliable logo is available, use an airplane symbol.

Do not stop after writing a plan: edit the relevant source files, run
available project checks, and report: - files changed, - assets added
and their sources, - behavior implemented, - build/test results, -
remaining requirements or blockers.

If the current working directory is not the actual app repository, stop
and ask the user to open Claude Code in the correct project folder.
