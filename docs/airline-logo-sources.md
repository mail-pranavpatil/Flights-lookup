# Airline logo sources

Logos live in `WhereIsThatPlane/Assets.xcassets/Airline_<ICAO>.imageset`. A logo is shown only when the adsbdb route for a callsign has passed `Aircraft.verifiedRoute` (live position and heading agree with the route) **and** that route's `airline.icao` matches an asset. All other cases get the SF Symbol `airplane`. The app never infers an airline from a callsign prefix and never fetches logos at runtime.

| ICAO | Airline | Source file (Wikimedia Commons) | Upstream source cited on Commons | Commons licence | Retrieved |
|---|---|---|---|---|---|
| IGO | IndiGo | [File:IndiGo_Airlines_logo.svg](https://commons.wikimedia.org/wiki/File:IndiGo_Airlines_logo.svg) | static.goindigo.in (official site header logo) | `{{PD-textlogo}}` + `{{Trademarked}}` | 2026-10-12 |
| AIC | Air India | [File:Air_India_2023.svg](https://commons.wikimedia.org/wiki/File:Air_India_2023.svg) | Air India digital media library (dmlib.airindia.com, archived) | `{{PD-textlogo}}` + `{{Trademarked}}` | 2026-10-12 |
| AKJ | Akasa Air | [File:Akasa_Air_logo.svg](https://commons.wikimedia.org/wiki/File:Akasa_Air_logo.svg) | akasaair.com header logo | `{{PD-TextLogo}}` + `{{trademarked}}` | 2026-10-12 |
| AXB | Air India Express | [File:Air_India_Express_logo.svg](https://commons.wikimedia.org/wiki/File:Air_India_Express_logo.svg) | Air India | `{{PD-textlogo}}` + `{{Trademark}}` | 2026-10-12 |

Each file is the PNG that Commons renders from the SVG at 960 px wide, downloaded from `thumb.wikimedia.org`. Nothing was cropped, recoloured or redrawn.

## Usage terms

- **Copyright:** Commons tags each file `PD-textlogo`. That means the logo is simple text and shapes below the threshold of originality, so it is not protected by copyright and can be reproduced without a licence.
- **Trademark:** each file also carries a trademark template. Trademark rights are separate from copyright and still apply. The app uses the logos only to identify the airline operating a flight (nominative use). The rules that follow from this:
  - don't alter, recolour or crop the logos
  - don't use them in a way that suggests endorsement, or in app marketing, screenshots or App Store artwork, without the airline's permission
- **Not legal advice.** Before a commercial App Store release, get a legal review or written permission from each airline.

## Skipped

- **SpiceJet (SEJ):** the only Commons file (`New_SpiceJet_Logo.png`) is tagged CC BY-SA 4.0, a licence the uploader likely cannot grant for a third-party mark. Its provenance is unclear, so the app shows the airplane glyph.

## Adding a carrier

1. Find the logo on Commons. Confirm the file page carries `{{PD-textlogo}}` (or the airline's own permission) and cites an official source.
2. Add `Assets.xcassets/Airline_<ICAO>.imageset` containing the unmodified PNG render.
3. Add a row to the table above.
