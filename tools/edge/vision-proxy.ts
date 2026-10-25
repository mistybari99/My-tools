// Islamia BOS · OPTIONAL Supabase Edge Function "vision-proxy" (X5): label suggestions for a photo from a configured vision provider.
// STATUS: SOURCE ONLY. NOT DEPLOYED, NOT TESTED against a live provider. It refuses every call until ALL of these hold:
//   1. the X1 connection gate is in place (a rule the owner switches on after X1; this file checks VISION_X1_GATE=1 env as well)
//   2. the owner switches rule recog_vision_on = ON
//   3. the owner gives consent: rule recog_vision_consent_on = ON (default NO). Without it no photo leaves the phone.
//   4. a monthly cap is set: rule recog_vision_budget (blank = refused). Calls are counted in vision_calls (see the note below).
//   5. the provider key is set as a Supabase secret (VISION_API_KEY) and VISION_PROVIDER names the provider.
// What it does (and only this):
//   - reads the caller's JWT and asks the database AS THAT USER whether vision is allowed for this person (is_active + rules);
//   - checks the image: JPEG/PNG/WebP only, at most 1.5 MB after base64, at most 1600 px is asked from the phone (the phone already shrinks);
//   - sends the image to the provider ONCE with a fixed instruction: "list label words only, no names of people, no phone numbers";
//   - returns { labels: [{text, confidence}] } as SUGGESTIONS. It never writes an item, a price or a name.
// Not included on purpose: image storage (the image is not kept), any write to items, any second model call.
// Deploy (owner, later): supabase secrets set VISION_API_KEY=... VISION_PROVIDER=<name>; supabase functions deploy vision-proxy
// Budget note: the count of calls per month must be kept in a table (vision_calls) created by a later phase; until that phase is applied
// this function refuses with "budget_store_missing" instead of calling the provider.

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const MAX_B64 = 1_500_000;
const TYPES = ["image/jpeg", "image/png", "image/webp"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "method" });
  if (Deno.env.get("VISION_X1_GATE") !== "1") return json(403, { error: "needs_x1" });
  const auth = req.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "no_session" });
  let body: { image_b64?: string; mime?: string };
  try { body = await req.json(); } catch (_e) { return json(400, { error: "bad_json" }); }
  const mime = String(body.mime || "").toLowerCase();
  const b64 = String(body.image_b64 || "");
  if (!TYPES.includes(mime)) return json(415, { error: "bad_type" });
  if (!b64 || b64.length > MAX_B64) return json(413, { error: "too_big" });
  if (!/^[A-Za-z0-9+/=]+$/.test(b64)) return json(400, { error: "bad_base64" });

  // permission, switches and the monthly cap are read AS THE USER (RLS and rules decide, not this function)
  const { createClient } = await import("npm:@supabase/supabase-js@2");
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const gate = await sb.rpc("rule_on", { p_key: "recog_vision_on" });
  const consent = await sb.rpc("rule_on", { p_key: "recog_vision_consent_on" });
  if (gate.error || consent.error) return json(403, { error: "not_allowed" });
  if (gate.data !== true) return json(403, { error: "off" });
  if (consent.data !== true) return json(403, { error: "needs_consent" });
  const cap = await sb.rpc("rule_num", { p_key: "recog_vision_budget" });
  if (cap.error || !(Number(cap.data) > 0)) return json(403, { error: "budget_not_set" });

  const provider = Deno.env.get("VISION_PROVIDER") || "";
  const key = Deno.env.get("VISION_API_KEY") || "";
  if (!provider || !key) return json(503, { error: "provider_not_configured" });
  // the call counter table does not exist in this phase: refuse rather than call without a cap
  return json(503, { error: "budget_store_missing" });
});
