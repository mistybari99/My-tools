// Islamia BOS · X1 "Test connection" check. OPTIONAL Supabase Edge Function. SOURCE ONLY: NOT DEPLOYED. Nothing here runs until the owner deploys it.
// Owner only: the database refuses everyone else (integration_registry is readable by the owner; integration_test_record needs the owner or the ops bot).
//
// What it does, for one connection code (for example "website"), and only this:
//   1. Reads that connection's NON-SECRET config and its env_names (the NAMES of server secrets) through the caller's own session.
//   2. For every env_name: checks that a server secret with that name is set (presence only). The value is never read out, logged or returned.
//   3. If config.endpoint is set: it must be https://, and it gets ONE HEAD request (8 seconds, no body, no credentials sent).
//   4. Records the result with integration_test_record (the database redacts the detail text and sets status connected or error).
//   The browser only sees { ok, checks: [{ name, ok, text }] } with names and yes/no answers, never a value.
//
// Secrets: none stored here. The owner sets the secrets in Supabase (Project Settings > Edge Functions > Secrets) under the names the Connect Center shows.
// Deploy (owner, from a computer with the Supabase CLI):  supabase functions deploy x1-connect-check
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "method" });
  const auth = req.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "sign_in_required" });

  let body: { code?: string };
  try { body = await req.json(); } catch { return json(400, { error: "bad_json" }); }
  const code = String(body.code || "");
  if (!/^[a-z][a-z0-9_]{2,40}$/.test(code)) return json(400, { error: "bad_code" });

  // every read and write runs as the caller: the database decides who may see or record anything
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const reg = await db.from("integration_registry").select("code, config, env_names").eq("code", code).maybeSingle();
  if (reg.error) return json(403, { error: "not_allowed" });
  if (!reg.data) return json(404, { error: "unknown_connection" });

  const checks: { name: string; ok: boolean; text: string }[] = [];
  for (const name of (reg.data.env_names as string[]) || []) {
    const present = /^[A-Z][A-Z0-9_]{2,60}$/.test(name) && (Deno.env.get(name) ?? "") !== "";
    checks.push({ name: "secret:" + name, ok: present, text: present ? "secret name is set on the server" : "secret is NOT set on the server (set it under this name)" });
  }
  const endpoint = (reg.data.config && (reg.data.config as Record<string, unknown>).endpoint) as string | undefined;
  if (endpoint) {
    if (!/^https:\/\/[^\s]+$/.test(endpoint)) {
      checks.push({ name: "endpoint", ok: false, text: "endpoint must start with https://" });
    } else {
      try {
        const r = await fetch(endpoint, { method: "HEAD", signal: AbortSignal.timeout(8000), redirect: "manual" });
        checks.push({ name: "endpoint", ok: r.status < 500, text: "endpoint answered HTTP " + r.status });
      } catch (_e) {
        checks.push({ name: "endpoint", ok: false, text: "endpoint did not answer in 8 seconds" });
      }
    }
  }
  if (checks.length === 0) checks.push({ name: "config", ok: false, text: "nothing to test yet: add the endpoint or the secret names first" });

  const ok = checks.every((c) => c.ok);
  const detail = checks.map((c) => `${c.name}: ${c.ok ? "ok" : "fail"} - ${c.text}`).join("; ").slice(0, 300);
  const rec = await db.rpc("integration_test_record", { p_code: code, p_ok: ok, p_detail: detail });
  if (rec.error) return json(403, { error: "not_recorded", checks });
  return json(200, { ok, checks, status: rec.data && rec.data.status });
});
