// node --test fare-proxy/fare.test.mjs — fare.js against a mocked Ignav response.
import { test } from "node:test";
import assert from "node:assert/strict";
import handler from "./api/fare.js";

const itinerary = (amount, code, number, id) => ({
  price: { amount, currency: "INR", status: "verified" },
  ignav_id: id,
  outbound: { segments: [{ marketing_carrier_code: code, flight_number: number, departure_time_local: "2026-10-13T07:15:00" }] },
});

async function call(query, itineraries = []) {
  globalThis.fetch = async () => ({ ok: true, json: async () => ({ itineraries }) });
  const res = { code: 200, body: null, headers: {} };
  res.status = (c) => ((res.code = c), res);
  res.json = (b) => ((res.body = b), res);
  res.setHeader = (k, v) => (res.headers[k] = v);
  await handler({ query }, res);
  return res;
}

const q = { origin: "bom", destination: "BHO", date: "2026-10-13", airline: "6E", flight: "687", market: "IN" };

test("prefers the same flight number over a cheaper one", async () => {
  const res = await call(q, [itinerary(3900, "AI", "655", "cheap"), itinerary(4250, "6E", "6E0687", "same")]);
  assert.equal(res.body.id, "same");
  assert.equal(res.body.matched, true);
  assert.equal(res.body.flight, "6E 687");
  assert.match(res.headers["Cache-Control"], /s-maxage/);
});

test("matches an ATC-suffixed callsign to its flight number", async () => {
  const res = await call({ ...q, flight: "687C" }, [itinerary(3900, "AI", "655", "cheap"), itinerary(4250, "6E", "687", "same")]);
  assert.equal(res.body.id, "same");
  assert.equal(res.body.matched, true);
});

test("falls back to the cheapest fare on the route", async () => {
  const res = await call(q, [itinerary(5000, "AI", "1", "a"), itinerary(3900, "AI", "655", "b")]);
  assert.equal(res.body.id, "b");
  assert.equal(res.body.matched, false);
});

test("rejects bad input and empty results", async () => {
  assert.equal((await call({ ...q, origin: "../x" })).code, 400);
  assert.equal((await call(q, [])).code, 404);
});
