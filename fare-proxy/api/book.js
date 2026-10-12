// GET /api/book?id=<ignav_id> → 302 to the first airline/agency booking page for that itinerary.
export default async function handler(req, res) {
  const id = String(req.query.id ?? "");
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(id)) return res.status(400).json({ error: "bad id" });

  const upstream = await fetch("https://ignav.com/api/fares/booking-links", {
    method: "POST",
    headers: { "X-Api-Key": process.env.IGNAV_API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ ignav_id: id }),
  });
  if (!upstream.ok) return res.status(502).json({ error: `ignav ${upstream.status}` });

  const url = (await upstream.json()).booking_options?.[0]?.links?.[0]?.url;
  if (!url) return res.status(404).json({ error: "no booking link" });
  res.redirect(302, /^https?:\/\//.test(url) ? url : `https://${url}`);
}
