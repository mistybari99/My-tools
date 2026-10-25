# Integrations P3c (phase62): SMS/WhatsApp queue, payment-gateway records, accounting CSV, assistant access
No provider secret is in the repo or the database. Everything below is additive, default OFF (Switchboard group "integrations").

## 1. SMS / WhatsApp queue (#21)
* Tables: `notify_templates` (code, channel, body_bn/en with `{name} {amount} {ref} {shop}` placeholders), `notify_optin` (+ append-only `notify_optin_log`), `notify_outbox` (status queued/sending/sent/failed/cancelled, attempts, max_attempts, next_try_at, last_error, provider_ref; unique on (source_type, source_id, template) so one event = one message).
* A message is queued only if `notify_sms_on` is ON AND the customer has opted in for that channel (`notify_optin_set`, owner or customer_manage). Opting out cancels waiting messages.
* Worker: `python3 tools/notify_sms.py` (every 5-10 min from a GitHub Actions cron, same bot as notify_digest.py; the bot needs ops purpose `notify`). Env secrets: SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_BOT_EMAIL, NOTIFY_BOT_PASSWORD, SMS_PROVIDER_URL (https), SMS_PROVIDER_TOKEN, SMS_SENDER, and `SMS_SEND_ENABLED=1` (without it the script claims and sends nothing).
* Flow: `notify_outbox_claim` -> POST to provider -> `notify_outbox_report`. Failure: back-off 2,4,8.. minutes, `failed` after `notify_sms_max_tries` (default 5). A crash leaves `sending`; re-claimed after 15 min (at-least-once; use the provider's own idempotency/reference if it has one).

## 2. Payment gateway records (#22) - no live call
* `payment_intents` (provider, provider_ref unique per provider, amount, status created/pending/succeeded/failed/cancelled/refunded, paid_amount, optional sale_payment_id), `payment_webhook_log` (append-only, unique (provider, event_id) = idempotent receipt), view `payment_recon_v` (closed to browsers) read through `payment_recon(from,to,state)`.
* Recon states: open, closed_unpaid, refunded, matched, amount_mismatch, missing_payment (gateway says paid, no sale_payments row), voided_payment. A sale_payments row matches an intent by explicit link (`payment_intent_link`) or by mode='mobile' and ref = provider_ref. Webhook events with no intent / bad signature are listed as orphans. The reconciliation never creates or changes a sale_payment.
* Edge function contract (NOT built): (1) logs in as the ops bot; (2) `payment_intent_create(client, provider, sale, customer, loc, amount)` then calls the gateway server-side and `payment_intent_set_ref(id, provider_ref)`; (3) on the gateway webhook it verifies the provider signature itself, then calls `payment_webhook_receive(provider, event_id, provider_ref, event_type, status, amount, signature_ok, payload)`; a duplicate event returns `{duplicate:true}`; status never goes backwards (pending < failed/cancelled < succeeded < refunded). Secrets and card fields in the payload are stripped by the server. Needs `pay_gateway_on` = ON.

## 3. Accounting export (#23)
`acct_export_csv(kind, from, to, loc)` - STABLE, read-only, owner or accounts_manage, location-scoped like the books, max 50,000 journal lines and 3,660 days. Returns {filename, csv, columns, rows, truncated}. UTF-8 (the page adds a BOM), CRLF rows, RFC 4180 quoting, cells starting with = + - @ get a leading apostrophe. Amounts are plain decimals with 2 places.
* `journal` columns: entry_id, entry_date, location_code, source_type, source_id, subtype, status(posted|void), reverses_id, entry_memo, line_no, account_code, account_name_en, account_type, debit, credit, line_location_code, party_type, party_id, line_memo. Voided and reversing entries are included.
* `trial_balance` columns: account_code, account_name_en, account_name_bn, account_type, is_group, opening_debit, opening_credit, period_debit, period_credit, closing_debit, closing_credit (group rows included; leaf rows add up to the JSON total_debit = total_credit).

## 4. Assistant access (#30)
See docs/ASSISTANT_ACCESS.md.
