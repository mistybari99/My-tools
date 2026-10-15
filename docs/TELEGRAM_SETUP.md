# Telegram setup - owner steps (Step Tg, phase86)

**Status: UNVERIFIED. No real Telegram call was ever made.** The database part is tested on a local Postgres; the Edge function is source only (never deployed, never run against Telegram); the steps below are written from memory of Telegram's Bot API and must be checked against the current Telegram documentation. Nothing here sends a reply to a customer: Telegram is *pull-in only*.

## What is BUILT (in the repo)  vs  what YOU must do

| Item | Built? | Who |
|---|---|---|
| `supabase/phase86.sql` (channel kind, intake, secret check, chat link) | Built, tested locally | You paste it once (Supabase SQL editor) |
| App screen: Inbox shows Telegram, chat info / link to customer, owner buttons on the Channels tab | Built, tested with a stub page | Nothing |
| `supabase/functions/telegram-webhook/index.ts` | Source only, **not deployed, not run** | **A computer is needed** to deploy it (Supabase CLI) |
| Telegram bot, its token, the secret token | Not built (cannot be) | **You** (BotFather) |
| Calling `setWebhook` | Not done | **You** (a browser link is enough) |
| Reply to customers, photo download, groups | **Not built** | - |

## Step 1 - make the bot (phone, Telegram app) - YOU
1. Open Telegram, find **@BotFather**, send `/newbot`, give a display name and a username ending in `bot`.
2. BotFather answers with the **bot token** (looks like `123456:ABC...`). It is a password. Do not paste it in chat, in the repo, or in a screenshot. If it leaks, send `/revoke` to BotFather.
3. Write down the bot's **username** (without @). You will type it in the app as the "bot reference".

## Step 2 - choose the secret token - YOU
Make one random text of 16 to 255 characters using only letters, digits, `_` and `-` (a password manager can generate it). This is the `secret_token`: Telegram will send it back in the header `X-Telegram-Bot-Api-Secret-Token` on every update, and that is how the system knows the message really came from Telegram. (Telegram itself allows 1-256 characters; this system asks for at least 16 and at most 255.)

## Step 3 - database and switches - YOU (phone)
1. Paste `supabase/phase86.sql` into the Supabase SQL editor and run it (safe to run twice). Phase 76 (Step H) must already be in.
2. In the Switchboard turn on `inbox_on`, then `telegram_intake_on`. Both are OFF by default.
3. The intake needs a limited login that is marked as an intake bot - the same one as for the Meta channels (see `docs/briefs_p2p3/step_H_REPORT.md`, `intake_bot_set`). If you already did that for Meta, reuse it.

## Step 4 - add the channel in the app - YOU (phone)
1. Inbox > Channels (owner only): **+ Add Telegram channel**. Type a name, the bot username, and the place number (the place that will handle these chats).
2. The channel card shows a **webhook code** such as `?c=tg_a1b2c3`. Note it.
3. On the card press **Set secret token** and type the secret token from step 2. The app sends it to the database, which keeps **only its SHA-256 hash** (it cannot be read back). Until this is done the card says "Token not set" and every Telegram message is refused.

## Step 5 - deploy the Edge function - NEEDS A COMPUTER (not possible on a phone)
```
supabase secrets set INTAKE_BOT_EMAIL=<bot login email> INTAKE_BOT_PASSWORD=<bot login password>
# optional second check (the same secret token from step 2):
supabase secrets set TELEGRAM_SECRET_TOKEN=<secret token>
supabase functions deploy telegram-webhook --no-verify-jwt
```
- `--no-verify-jwt` is needed because Telegram cannot send a Supabase login token. The protection is the secret token check.
- The function never uses `service_role`. The bot token is **not** read by this function (it never calls Telegram). Keep the bot token for step 6 only (or as a Supabase secret `TELEGRAM_BOT_TOKEN` if a later step needs it).
- The function address will be `https://<project-ref>.functions.supabase.co/telegram-webhook?c=<webhook code>`.

## Step 6 - tell Telegram where to send messages (`setWebhook`) - YOU (a browser link works)
Open this link (replace the three parts; the url must be URL-encoded as shown, `%3F` = `?`, `%3D` = `=`):
```
https://api.telegram.org/bot<BOT TOKEN>/setWebhook?url=https%3A%2F%2F<project-ref>.functions.supabase.co%2Ftelegram-webhook%3Fc%3D<webhook code>&secret_token=<SECRET TOKEN>&allowed_updates=%5B%22message%22%5D
```
- Telegram should answer `{"ok":true,...}`. Check with `https://api.telegram.org/bot<BOT TOKEN>/getWebhookInfo` (look at `last_error_message`).
- The link contains the bot token and the secret token; it stays in your browser history. Clear it afterwards. A curl command on a computer does the same.
- To stop: `.../deleteWebhook`, and switch `telegram_intake_on` off.

## Step 7 - first test - YOU
Send "test" to your bot from a personal Telegram account. It should appear in Inbox (kind Telegram, status New) within seconds. Open **Chat info** to link the chat to a customer (type the customer's mobile number) - Telegram does not give a phone number, so a person links it. An order made from that message links its chat automatically.

## What the system does with a message
- Only private chats and normal `message` updates are taken. Groups, channels, edited messages and bot senders are acknowledged and ignored.
- Stored once per bot channel + Telegram `update_id` (a repeat delivery changes nothing).
- A wrong or missing secret token: nothing is stored; a line "rejected" (no text, no chat id) appears in the failed list; the function answers 403.
- Photos / documents / voice: only a marker such as `photo:<file id>` is kept. **They are not downloaded.**
- Phone/contact masking and the view audit are the same as for Meta messages (`inbox_pii_guard_on`, grant `inbox_contact_view`).
- No reply is sent, no order is created, no AI is called.

## Known limits and things to watch (honest list)
- UNVERIFIED against real Telegram: payload field names, the `setWebhook` link form, delivery retries, header name casing.
- Anyone who finds the function address can send requests; each wrong-token request writes one "rejected" line (and needs one bot login). There is no rate limit on these lines yet. If you see a flood, switch the channel off or rotate the webhook code.
- If the switch is off or the database is down the function answers 503 and Telegram retries for a limited time; messages older than that are lost.
- To rotate the secret token: set a new one in step 4 (old stops working at once), then call `setWebhook` again with the new `secret_token`.
- If the bot token leaks: `/revoke` in BotFather, then repeat step 6 with the new token. The secret token is a separate thing and does not protect the bot token.
