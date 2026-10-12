// GET /api/fare?origin=BOM&destination=BHO&date=2026-10-13&airline=6E&flight=687&market=IN
// Cheapest nonstop Ignav fare for that flight number (or the route if it isn't on sale). Holds the API key.
// ponytail: open endpoint, anyone with the URL can spend Ignav credits; add a Vercel Firewall rate limit if abused.
const IGNAV = "https://ignav.com/api";
const RULES = {
  origin: /^[A-Z]{3}$/,
  destination: /^[A-Z]{3}$/,
  date: /^\d{4}-\d{2}-\d{2}$/,
  airline: /^[A-Z0-9]{2,3}$/,
  flight: /^\d{1,5}[A-Z]?$/, // adsbdb keeps ATC suffixes: IGO687C → 6E687C
  market: /^[A-Z]{2}$/,
};

// "6E0687" / "687" / "687C" → "687"
const flightDigits = (number, airline) =>
  String(number ?? "").toUpperCase().replace(new RegExp(`^${airline}`), "").replace(/\D/g, "").replace(/^0+/, "");

export default async function handler(req, res) {
  const q = {};
  for (const [key, rule] of Object.entries(RULES)) {
    q[key] = String(req.query[key] ?? "").toUpperCase();
    if (!rule.test(q[key])) {
      console.warn(`400 bad ${key}=${JSON.stringify(q[key])}`);
      return res.status(400).json({ error: `bad ${key}` });
    }
  }

  const upstream = await fetch(`${IGNAV}/fares/one-way`, {
    method: "POST",
    headers: { "X-Api-Key": process.env.IGNAV_API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({
      origin: q.origin, destination: q.destination, departure_date: q.date, max_stops: 0, market: q.market,
    }),
  });
  if (!upstream.ok) return res.status(502).json({ error: `ignav ${upstream.status}` });

  const itineraries = ((await upstream.json()).itineraries ?? []).sort((a, b) => a.price.amount - b.price.amount);
  const wanted = flightDigits(q.flight, q.airline);
  const isFlight = (it) => {
    const s = it.outbound?.segments?.[0];
    return s?.marketing_carrier_code === q.airline && flightDigits(s.flight_number, q.airline) === wanted;
  };
  const pick = itineraries.find(isFlight) ?? itineraries[0];
  if (!pick) return res.status(404).json({ error: "no fares" });

  const seg = pick.outbound.segments[0];
  res.setHeader("Cache-Control", "s-maxage=10800, stale-while-revalidate=3600");
  res.json({
    amount: pick.price.amount,
    currency: pick.price.currency,
    matched: isFlight(pick),
    flight: `${seg.marketing_carrier_code ?? ""} ${flightDigits(seg.flight_number, seg.marketing_carrier_code ?? "")}`.trim(),
    departure_time_local: seg.departure_time_local,
    id: pick.ignav_id,
  });
}
