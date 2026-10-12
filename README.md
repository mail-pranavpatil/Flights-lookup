# Where Is That Plane? — SwiftUI MVP starter

A native SwiftUI app that asks for foreground location, fetches nearby ADS-B aircraft, ranks likely candidates by horizontal distance, and lets the user tap a result for details.

## Architecture

- **SwiftUI**: screen, nearby list, flight detail sheet.
- **Core Location**: one-shot foreground location only; no background tracking.
- **ADSB.lol**: nearby aircraft positions from `GET https://api.adsb.lol/v2/lat/{lat}/lon/{lon}/dist/{radiusNM}`.
- **AircraftRanker**: filters aircraft without positions and likely ground traffic, then sorts by distance with a small penalty for missing callsigns.
- **Destination enrichment (next step)**: call a commercial flight-data provider through a small backend proxy. ADS-B position feeds generally do not include destination airports.

## Open in Xcode

1. In Xcode, create **iOS App** named `WhereIsThatPlane`, Interface **SwiftUI**, Language **Swift**.
2. Set deployment target to iOS 17 or later.
3. Replace the generated `ContentView.swift` and app entry file with the matching files here. Add `Plane.swift`, `AircraftService.swift`, and `LocationManager.swift` to the app target.
4. In the target's **Info** tab, add `Privacy - Location When In Use Usage Description` (`NSLocationWhenInUseUsageDescription`) with value: `Your location helps find aircraft flying near you.`
5. Run on an iPhone or simulator. A real device outdoors is more useful for validating location and aircraft coverage.

## Flight data choices

### Start with ADSB.lol (implemented)
- Free/open API and a nearby-aircraft endpoint; no key is currently required.
- Data is crowdsourced and can be incomplete. Review its API terms and ODbL attribution/share-alike implications before a public/commercial launch.
- API docs: https://api.adsb.lol/docs and https://www.adsb.lol/docs/open-data/api/

### Destination enrichment (not implemented yet)
The live aircraft endpoint provides callsign/position/altitude/heading, not a reliable destination. For a quick prototype, evaluate Aviationstack's real-time flight endpoint and test whether the callsign can be matched to an IATA flight number. Its free tier is listed for personal/non-commercial use with a limited request allowance; commercial use requires a suitable paid plan. Keep the API key on a backend, not in the iOS app. Pricing: https://aviationstack.com/pricing

OpenSky is another option for state vectors, but its API is research/non-commercial oriented and has request-credit limits. It also does not provide commercial schedules/destinations directly. Docs: https://openskynetwork.github.io/opensky-api/

## Current limitations

- This is a source-code starter, not a signed `.ipa` or a complete generated `.xcodeproj`.
- The app ranks by distance, not by camera recognition or true vertical overhead. Nearest does not guarantee directly overhead.
- Destination is explicitly shown as unavailable until route enrichment is connected.
- Add API attribution and confirm data-provider terms before App Store distribution.
- Do not ship provider secrets in the app bundle. Put destination-provider calls behind a small serverless endpoint (for example, a Supabase Edge Function).

## Build without a Mac (GitHub Actions)

This repo includes `project.yml` for XcodeGen and `.github/workflows/ios-testflight.yml` to build/sign on a hosted macOS runner and upload to TestFlight. Follow [`docs/GITHUB_ACTIONS_IOS_RELEASE_AND_APNS.md`](docs/GITHUB_ACTIONS_IOS_RELEASE_AND_APNS.md) to set the real bundle identifier, create signing assets, add the eight GitHub secrets, and configure APNs. The workflow is a template and requires matching Apple Developer assets before it can pass.
