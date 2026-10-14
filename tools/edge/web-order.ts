// Islamia BOS · Supabase Edge Function "web-order" - the public web / landing order form (fully automatic intake).
// STATUS: SOURCE ONLY - NOT DEPLOYED, NOT RUN. The database side (web_order_submit, web_form_catalog) is tested; THIS FILE IS UNVERIFIED.
//
//   GET  ?c=<channel code>  : shows a small Bangla form (items come from web_form_catalog: only active + sellable + visible + priced items).
//   POST (JSON)             : { c, submission, name, mobile, address, delivery_mode, lines:[{item_id, qty}], note, source, pay_mode, pay_ref, captcha }
//        - `submission` is a uuid made in the browser when the page opens and reused on re-send, so the same submission twice = ONE order (the database client id).
//        - any price sent by the browser is ignored: the database prices the order from the list and returns the total.
//        - spam: the database applies the rate limit (rules web_form_rate_max / window) on a hash of the visitor address made HERE with WEB_FORM_SALT
//          (the raw address is never stored); captcha: if CAPTCHA_VERIFY_URL + CAPTCHA_SECRET are set, the token is checked and the result passed as p_captcha_ok.
//   It signs in as the intake bot (limited user). It never writes a table, never confirms an order: the order enters as status "new" for staff.
//
// Secrets (NAMES only): INTAKE_BOT_EMAIL, INTAKE_BOT_PASSWORD, INTAKE_PROOF_SECRET (optional, bos94), WEB_FORM_SALT, CAPTCHA_SECRET (optional), CAPTCHA_VERIFY_URL (optional; provider specific - UNVERIFIED)
// Deploy (needs a computer):  supabase functions deploy web-order --no-verify-jwt    then put its URL in the setting "web_form_public_url".
import { createClient } from "npm:@supabase/supabase-js@2";

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const J = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "content-type" } });

async function bot() {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });
  const r = await db.auth.signInWithPassword({ email: Deno.env.get("INTAKE_BOT_EMAIL") || "", password: Deno.env.get("INTAKE_BOT_PASSWORD") || "" });
  return r.error ? null : db;
}
async function sha256(s: string) { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((x) => x.toString(16).padStart(2, "0")).join(""); }

function page(code: string, items: any[]) {
  const rows = items.map((i) => `<label class="r"><span>${esc(i.name_bn)} <small>${esc(i.price)} / ${esc(i.unit)}</small></span><input type="number" min="0" step="any" data-id="${esc(i.id)}" value="0"></label>`).join("");
  return `<!doctype html><html lang="bn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>অর্ডার</title>
<style>body{font:16px system-ui;margin:0;padding:16px;max-width:480px}input,select,textarea{width:100%;box-sizing:border-box;padding:10px;margin:4px 0 12px;font:inherit}.r{display:flex;gap:8px;align-items:center}.r input{width:90px}button{width:100%;padding:14px;font:inherit}</style></head><body>
<h2>অর্ডার দিন</h2><form id="f"><label>নাম<input name="name" required maxlength="80"></label><label>মোবাইল<input name="mobile" inputmode="tel" required></label>
<label>ডেলিভারি<select name="delivery_mode"><option value="home">বাসায় পৌঁছে দিন</option><option value="pickup">দোকান থেকে নেব</option></select></label>
<label>ঠিকানা<textarea name="address" maxlength="300"></textarea></label><div>${rows}</div><label>নোট<textarea name="note" maxlength="300"></textarea></label>
<button type="submit">অর্ডার পাঠান</button><p id="m"></p></form>
<script>const sub=crypto.randomUUID();document.getElementById('f').onsubmit=async(e)=>{e.preventDefault();const f=e.target,d=new FormData(f);const lines=[...f.querySelectorAll('[data-id]')].filter(x=>+x.value>0).map(x=>({item_id:x.dataset.id,qty:+x.value}));
const r=await fetch(location.pathname,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({c:${JSON.stringify(code)},submission:sub,name:d.get('name'),mobile:d.get('mobile'),address:d.get('address'),delivery_mode:d.get('delivery_mode'),note:d.get('note'),lines})});
const j=await r.json();document.getElementById('m').textContent=j.queued?'আপনার অর্ডার পেয়েছি, শীঘ্রই জানাব।':j.ok?('ধন্যবাদ! অর্ডার নং '+j.order_no+', মোট '+j.subtotal+'. আমরা যোগাযোগ করব।'):('হয়নি: '+(j.error||'আবার চেষ্টা করুন'));};</script></body></html>`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return J(200, {});
  const url = new URL(req.url);
  const db = await bot();
  if (!db) return J(503, { ok: false, error: "unavailable" });
  if (req.method === "GET") {
    const code = url.searchParams.get("c") || "";
    const cat = await db.rpc("web_form_catalog", { p_channel: code });
    if (cat.error || !cat.data?.ok) return new Response("unavailable", { status: cat.data?.off ? 503 : 404 });
    return new Response(page(code, cat.data.items), { headers: { "Content-Type": "text/html; charset=utf-8" } });
  }
  if (req.method !== "POST") return J(405, { ok: false });
  let b: any;
  try { b = await req.json(); } catch { return J(400, { ok: false, error: "bad_json" }); }
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() || "";
  const keyHash = await sha256((Deno.env.get("WEB_FORM_SALT") || "") + "|" + ip);
  const ps = Deno.env.get("INTAKE_PROOF_SECRET"), proof = ps ? await sha256(ps) : null;   // bos94: optional; the owner stores its hash with intake_proof_set94('web_form', ...); not set = null = as before
  let captcha: boolean | null = null;
  const cs = Deno.env.get("CAPTCHA_SECRET"), cu = Deno.env.get("CAPTCHA_VERIFY_URL");
  if (cs && cu) {
    try { const r = await fetch(cu, { method: "POST", body: new URLSearchParams({ secret: cs, response: String(b.captcha || "") }) }); captcha = (await r.json()).success === true; } catch { captcha = false; }
  }
  // only the necessary fields are forwarded; item lines carry item_id + qty only (price is never read from the browser)
  const lines = Array.isArray(b.lines) ? b.lines.slice(0, 100).map((l: any) => ({ item_id: String(l.item_id), qty: Number(l.qty) })) : [];
  const r = await db.rpc("web_order_submit", { p_channel: String(b.c || ""), p_submission: String(b.submission || ""), p_name: String(b.name || ""), p_mobile: String(b.mobile || ""),
    p_address: b.address ? String(b.address) : null, p_delivery_mode: String(b.delivery_mode || "pickup"), p_lines: lines, p_note: b.note ? String(b.note) : null,
    p_source: b.source ? String(b.source) : null, p_pay_mode: b.pay_mode ? String(b.pay_mode) : null, p_pay_ref: b.pay_ref ? String(b.pay_ref) : null, p_key_hash: keyHash, p_captcha_ok: captcha, p_proof_hash: proof });
  if (r.error) return J(500, { ok: false, error: "server" });
  if (r.data?.off) return J(503, { ok: false, error: "closed" });
  if (r.data?.queued) return J(202, { ok: true, queued: true, order_no: null, subtotal: null });   // saved in the failed list; the system retries it
  return J(r.data?.ok ? 200 : 400, r.data);
});
