// Islamia BOS · Supabase Edge Function "telegram-webhook" - receives Telegram bot messages and PULLS THEM INTO the inbox.
// STATUS: SOURCE ONLY - NOT DEPLOYED, NOT RUN, NOT TESTED against Telegram (no real Telegram call was ever made). Nothing here runs until the OWNER
// (or a helper with a computer) does the setup in docs/TELEGRAM_SETUP.md. The Update field names below are written from memory of Telegram's documented
// Bot API shapes and MUST be checked against the current Bot API documentation before use (UNVERIFIED).
//
// What it does (and only this):
//   POST : 1. reads the header X-Telegram-Bot-Api-Secret-Token (Telegram sends the secret_token given to setWebhook) and computes its SHA-256 here;
//          2. signs in as the intake bot (a normal, limited user marked in intake_bots) and calls the database function telegram_message_receive();
//             the DATABASE compares that hash with the stored hash of the channel's secret token (constant time), stores the message once per
//             (channel, update_id), and puts failures in the failed list for retry. A wrong / missing token is logged there as a "rejected" line (no body) and answered 403;
//          3. it never replies to the customer (it never calls sendMessage - the bot token is NOT used by this function), never creates an order, never calls any AI.
//   Which channel: the webhook URL carries the channel code, e.g.  https://<project>.functions.supabase.co/telegram-webhook?c=tg_ab12
//   Only private chats and plain `message` updates are taken in (groups, channels, edited messages, callbacks are acknowledged and ignored).
//   The retry worker for the failed list calls intake_retry_due() (same bot login) - not written here (same as meta-webhook).
//
// Secrets (NAMES only - set with `supabase secrets set NAME=...`, never in the repo or chat):
//   INTAKE_BOT_EMAIL, INTAKE_BOT_PASSWORD        (required; SUPABASE_URL and SUPABASE_ANON_KEY are provided by Supabase; service_role is NOT used)
//   TELEGRAM_SECRET_TOKEN                        (REQUIRED since bos94: the header is compared with it before any sign-in; unset = every call is answered 403)
//   TELEGRAM_BOT_TOKEN                           (NOT read by this function. Keep it only for the owner's own setWebhook / getWebhookInfo calls, or as a Supabase secret for a future file-download step.)
// The secret_token itself must ALSO be given to the app once (Inbox > Channels > "Set secret token" -> telegram_secret_set); the database stores only its SHA-256.
// Deploy (needs a computer):  supabase functions deploy telegram-webhook --no-verify-jwt     (Telegram cannot send a Supabase login token)
import { createClient } from "npm:@supabase/supabase-js@2";

const enc = new TextEncoder();
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const sha256hex = async (s: string) => hex(await crypto.subtle.digest("SHA-256", enc.encode(s)));

// constant-time compare of two equal-length hex strings (false if lengths differ)
function ctEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

type Msg = { updateId: number; chatId: number; username: string | null; name: string | null; text: string | null; time: string | null; attachment: string | null };

// UNVERIFIED shape: Update { update_id, message { message_id, from { id, is_bot, first_name, last_name, username }, chat { id, type }, date, text, caption, photo[], document, voice, video, ... } }
function parse(body: any): Msg | null {
  const m = body?.message;
  if (typeof body?.update_id !== "number" || !m || m.chat?.type !== "private" || typeof m.chat?.id !== "number") return null;
  if (m.from?.is_bot) return null;                                   // a bot is not a customer
  const f = m.from || {};
  const name = [f.first_name, f.last_name].filter(Boolean).join(" ").trim() || null;
  let attachment: string | null = null, label: string | null = null;
  if (Array.isArray(m.photo) && m.photo.length) { attachment = "photo:" + m.photo[m.photo.length - 1]?.file_id; label = "[photo]"; }
  else if (m.document?.file_id) { attachment = "document:" + m.document.file_id; label = "[document]"; }
  else if (m.voice?.file_id) { attachment = "voice:" + m.voice.file_id; label = "[voice]"; }
  else if (m.video?.file_id) { attachment = "video:" + m.video.file_id; label = "[video]"; }
  else if (m.sticker) label = "[sticker]";
  else if (m.location) label = "[location]";
  else if (m.contact) label = "[contact]";
  const text = (m.text ?? m.caption ?? label) as string | null;
  return { updateId: body.update_id, chatId: m.chat.id, username: f.username ?? null, name, text: text ? String(text).slice(0, 4000) : null,
    time: typeof m.date === "number" && m.date > 0 ? new Date(m.date * 1000).toISOString() : null, attachment: attachment ? attachment.slice(0, 500) : null };
}

// bos94: the signed-in client is kept between calls of the same instance (one Auth sign-in per instance, not per request); dropped on any database error so the next call signs in again
let botDb: any = null;
async function bot() {
  if (botDb) return botDb;
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });
  const login = await db.auth.signInWithPassword({ email: Deno.env.get("INTAKE_BOT_EMAIL") || "", password: Deno.env.get("INTAKE_BOT_PASSWORD") || "" });
  if (login.error) return null;
  botDb = db; return db;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  const code = new URL(req.url).searchParams.get("c") || "";
  if (!/^[a-z0-9_]{2,30}$/.test(code)) return new Response("bad channel", { status: 400 });
  const raw = await req.text();
  const header = req.headers.get("x-telegram-bot-api-secret-token");
  const hash = header ? await sha256hex(header) : null;

  // bos94: the Supabase secret is checked FIRST and is required (fails closed when unset). A forged call is answered 403 before any sign-in or database call,
  // so a flood cannot use up the bot login's Auth rate limit or fill the failed list. The database check (stored hash per channel) still applies below.
  const envTok = Deno.env.get("TELEGRAM_SECRET_TOKEN");
  if (!envTok || !hash || !ctEq(hash, await sha256hex(envTok))) return new Response("forbidden", { status: 403 });

  const db = await bot();
  if (!db) return new Response("bot_login", { status: 503 });                   // Telegram will retry

  let body: any = null;
  try { body = JSON.parse(raw); } catch { /* handled below */ }
  const msg = body ? parse(body) : null;
  if (!body) return new Response("bad json", { status: 400 });
  if (!msg) return new Response("ignored", { status: 200 });                    // not a private text/media message: acknowledge so Telegram does not resend

  const r = await db.rpc("telegram_message_receive", { p_channel_code: code, p_secret_hash: hash, p_update_id: msg.updateId, p_chat_id: msg.chatId, p_username: msg.username,
    p_name: msg.name, p_text: msg.text, p_msg_time: msg.time, p_attachment: msg.attachment });
  if (r.error) { botDb = null; return new Response("retry", { status: 503 }); }   // database unreachable / denied: ask Telegram to send again
  if (r.data?.off) return new Response("retry", { status: 503 });              // switch is off: not stored; Telegram keeps and resends for a while
  if (r.data?.rejected) return new Response("forbidden", { status: 403 });     // wrong token (database check) / unknown or secret-less channel
  // r.data.queued = stored in the failed list, the database retries it itself (intake_retry_due); r.data.duplicate = already had it
  return new Response("ok", { status: 200 });
});
