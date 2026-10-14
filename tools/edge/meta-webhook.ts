// Islamia BOS · Supabase Edge Function "meta-webhook" - receives Facebook Messenger / Instagram DM / WhatsApp Business messages and PULLS THEM INTO the inbox.
// STATUS: SOURCE ONLY - NOT DEPLOYED, NOT RUN, NOT TESTED against Meta. Nothing here runs until the OWNER (or a helper with a computer) does the
// setup listed in docs/briefs_p2p3/step_H_REPORT.md ("ফোনে সম্ভব নয় এমন সেটআপ"). The payload field names below are written from memory of Meta's
// documented shapes and MUST be checked against Meta's current documentation before use (UNVERIFIED - 'যাচাই হয়নি').
//
// What it does (and only this):
//   GET  : Meta's subscribe check - echoes hub.challenge when hub.verify_token equals the secret META_VERIFY_TOKEN.
//   POST : 1. reads the RAW body, checks the X-Hub-Signature-256 header (HMAC-SHA256 with the app secret META_APP_SECRET) - the secret never leaves this function;
//          2. signs in as the intake bot (a normal, limited user marked in intake_bots) and calls the database function inbound_message_receive()
//             for each message; the DATABASE stores it once per (channel, external id), and puts failures in the failed list for retry;
//          3. a wrong signature is reported to the database as p_signature_ok=false (kept only as a "rejected" line, no body) and answered 403;
//          4. it never replies to the customer, never creates an order, never calls any AI.
//   The retry worker for the failed list calls intake_retry_due() (same bot login) - a GitHub Actions cron or Supabase cron; not written here.
//
// Secrets (NAMES only - set with `supabase secrets set NAME=...`, never in the repo or chat):
//   META_APP_SECRET, META_VERIFY_TOKEN, INTAKE_BOT_EMAIL, INTAKE_BOT_PASSWORD   (SUPABASE_URL and SUPABASE_ANON_KEY are provided by Supabase; service_role is NOT used)
// Deploy (needs a computer):  supabase functions deploy meta-webhook --no-verify-jwt     (Meta cannot send a Supabase login token)
import { createClient } from "npm:@supabase/supabase-js@2";

const enc = new TextEncoder();
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

async function sigOk(raw: string, header: string | null): Promise<boolean> {
  const secret = Deno.env.get("META_APP_SECRET");
  if (!secret || !header || !/^sha256=[0-9a-fA-F]{64}$/.test(header)) return false;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const exp = hex(await crypto.subtle.sign("HMAC", key, enc.encode(raw)));
  const got = header.slice(7).toLowerCase();
  let diff = 0;
  for (let i = 0; i < 64; i++) diff |= exp.charCodeAt(i) ^ got.charCodeAt(i);   // constant time
  return diff === 0;
}

type Msg = { kind: string; account: string; id: string; handle: string | null; name: string | null; text: string | null; time: string | null; attachment: string | null };

// UNVERIFIED shapes: Messenger / Instagram: entry[].messaging[]; WhatsApp Cloud API: entry[].changes[].value.messages[]
function parse(body: any): Msg[] {
  const out: Msg[] = [];
  const iso = (t: unknown, ms: boolean) => (typeof t === "number" || typeof t === "string") && Number(t) > 0 ? new Date(Number(t) * (ms ? 1 : 1000)).toISOString() : null;
  if (body?.object === "page" || body?.object === "instagram") {
    const kind = body.object === "page" ? "facebook" : "instagram";
    for (const e of body.entry || []) for (const m of e.messaging || []) {
      if (!m?.message?.mid || m.message.is_echo) continue;               // echoes of our own page messages are not customer messages
      out.push({ kind, account: String(e.id), id: String(m.message.mid), handle: m.sender?.id ? String(m.sender.id) : null, name: null,
        text: m.message.text ?? null, time: iso(m.timestamp, true), attachment: m.message.attachments?.[0]?.payload?.url ?? null });
    }
  } else if (body?.object === "whatsapp_business_account") {
    for (const e of body.entry || []) for (const c of e.changes || []) {
      const v = c?.value || {};
      for (const m of v.messages || []) {
        if (!m?.id) continue;
        out.push({ kind: "whatsapp", account: String(v.metadata?.phone_number_id ?? ""), id: String(m.id), handle: m.from ? String(m.from) : null,
          name: v.contacts?.[0]?.profile?.name ?? null, text: m.text?.body ?? (m.type ? `[${m.type}]` : null), time: iso(m.timestamp, false), attachment: null });
      }
    }
  }
  return out;
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  if (req.method === "GET") {
    const ok = url.searchParams.get("hub.mode") === "subscribe" && url.searchParams.get("hub.verify_token") === Deno.env.get("META_VERIFY_TOKEN") && !!Deno.env.get("META_VERIFY_TOKEN");
    return ok ? new Response(url.searchParams.get("hub.challenge") ?? "", { status: 200 }) : new Response("forbidden", { status: 403 });
  }
  if (req.method !== "POST") return new Response("method", { status: 405 });
  const raw = await req.text();
  const good = await sigOk(raw, req.headers.get("x-hub-signature-256"));

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });
  const login = await db.auth.signInWithPassword({ email: Deno.env.get("INTAKE_BOT_EMAIL") || "", password: Deno.env.get("INTAKE_BOT_PASSWORD") || "" });
  if (login.error) return new Response("bot_login", { status: 503 });           // Meta will retry

  if (!good) {
    await db.rpc("inbound_message_receive", { p_kind: "facebook", p_account_ref: null, p_external_id: "sig-" + crypto.randomUUID(), p_handle: null, p_name: null, p_text: null,
      p_msg_time: null, p_attachment: null, p_signature_ok: false });
    return new Response("bad signature", { status: 403 });
  }
  let body: any;
  try { body = JSON.parse(raw); } catch { return new Response("bad json", { status: 400 }); }
  let retry = false;
  for (const m of parse(body)) {
    const r = await db.rpc("inbound_message_receive", { p_kind: m.kind, p_account_ref: m.account, p_external_id: m.id, p_handle: m.handle, p_name: m.name, p_text: m.text,
      p_msg_time: m.time, p_attachment: m.attachment, p_signature_ok: true });
    if (r.error) retry = true;                                       // database unreachable / denied: ask Meta to send again
    else if (r.data?.off) retry = true;                              // switch is off: not stored; a 503 lets Meta retry later
    // r.data.queued = stored in the failed list, the database retries it itself (intake_retry_due)
  }
  return new Response(retry ? "retry" : "ok", { status: retry ? 503 : 200 });
});
