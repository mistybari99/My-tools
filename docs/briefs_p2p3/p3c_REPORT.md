# p3c REPORT - gaps #21 SMS/WhatsApp, #22 payment gateway records, #23 accounting CSV, #30 assistant tab
Files: supabase/phase62.sql, supabase/phase62_test.sql, web/integrations.js, tests/web/integrations_test.js, tools/notify_sms.py, docs/INTEGRATIONS_P3C.md, docs/ASSISTANT_ACCESS.md (new, mine).

## #30 what ALREADY existed (inspected first)
* Route `assistant` = web/assistant.js (727 lines, read-only MVP chat) + web/assistant_tools.js + web/data/kb.json; server = phase47 (assistant_me/log/notes/usage/health, rules assistant_on/assistant_roles/assistant_provider...).
* Grant `assistant_use` already in grant_defs (module reports). ia.js line 118: group `reports`, `ok: own || head_management || assistant_use`. nav.js already loads GF.assistant_use.
* Server gate `_assistant_ok()` allowed: owner, head_management, assistant_use, rule assistant_roles (`*` = all, or role list). So it was NOT "owner + explicit grant only".
* Built (phase62): `_assistant_ok()` re-created (bos62) = active + rule assistant_on + (owner OR assistant_use at any place). head_management and assistant_roles no longer open it; every assistant function that calls it now refuses non-granted users (`not allowed`; assistant_me -> allowed:false/no_right). grant_defs insert is idempotent (1 row). New `assistant_access_list()` (owner only: who holds it, by person and role). Grant/revoke = existing grants screen (set_user_grant / role grants), tested incl. revoke and location-scoped grant.
* BEHAVIOUR CHANGE: head-management users lose the assistant until granted. phase47_test: 70/72 on a DB with phase62 (2 FAIL = the old rules "T1 role list opens it", "T1 head management allowed + health" assert the old behaviour); base DB (through phase51) 72/72. All other 70 pass.

## ia.js lines for the lead (do not edit by me)
1. Replace the existing 'assistant' rec `ok:` and make it a front/side tab: `ok: (c) => c.own || c.GF.assistant_use === true,` and add `mob: 2, home: { biz: 3 }` (owner sees it in bottom bar/Home; a granted person gets it too, nobody else - invisible otherwise). Keep icon 'doc' (or 'info' from ICON map).
2. New screen: `rec('integrations', 'settings', ['সংযোগ ও এক্সপোর্ট', 'Integrations & export', 'Integrations ও export'], { icon: 'doc', ok: (c) => c.own || c.GF.accounts_manage === true || c.GF.customer_manage === true, kw: ['sms', 'whatsapp', 'gateway', 'bkash', 'reconcile', 'export', 'csv', 'journal', 'trial balance', 'এসএমএস', 'হোয়াটসঅ্যাপ', 'মিলান', 'এক্সপোর্ট', 'জার্নাল'] }),`
3. index.html: `<script src="integrations.js"></script>` after assistant.js. nav.js loads grants list at line 209: add 'customer_manage' already there; 'accounts_manage' there too.

## Built per gap
* #21 notify_templates (3 seeded), notify_optin (+append-only log), notify_outbox (queued/sending/sent/failed/cancelled, attempts, max_attempts, next_try_at back-off 2^n min, last_error, provider_ref, unique (source_type, source_id, template)). Fns: notify_template_save (owner), notify_optin_set / notify_enqueue / notify_cancel / notify_outbox_summary (owner or customer_manage; phone masked in summary), notify_outbox_claim / notify_outbox_report (ops bot 'notify' or owner). Needs opt-in AND notify_sms_on. tools/notify_sms.py: env secrets only, generic HTTPS JSON adapter, needs SMS_SEND_ENABLED=1 too, redaction via ops_common; python fake-API self-check done (not a committed test).
* #22 payment_intents, payment_webhook_log (append-only, unique (provider,event_id), secret keys stripped), payment_recon_v (browser-closed) + payment_recon(); fns payment_intent_create / _set_ref / _link, payment_webhook_receive (status only moves forward; bad signature / unknown ref logged as orphan). No gateway call anywhere; Edge contract documented only.
* #23 acct_export_csv('journal'|'trial_balance', from, to, loc): STABLE, owner or accounts_manage, location scoped, BOM added client-side, formula-injection guard, columns in docs/INTEGRATIONS_P3C.md.
* Web: #/integrations with 4 tabs (SMS queue + cancel, payment recon, export download, assistant holders) in bn/mix/en.

## Switches / defaults
notify_sms_on OFF, pay_gateway_on OFF, notify_sms_max_tries 5. assistant_on unchanged (ON). Export has no switch (read-only, guarded by accounts_manage; say if you want one). Webhook/worker reuse ops purpose 'notify' (ops_accounts CHECK only allows backup/notify; I did not widen it).

## Tests
* SQL phase62_test.sql: RESULT pass=74 fail=0 (fresh DB through phase62). phase62.sql re-applied 2nd time: no errors.
* Web tests/web/integrations_test.js (stub DOM, no browser): pass=15 fail=0; node --check ok.
* Regression: phase47_test as above (2 intended changes). No other function touched.

## NOT done / UNVERIFIED
* No live SMS provider or gateway was contacted; notify_sms.py HTTP adapter is untested against a real provider (shape is generic, adjust post_message()).
* Edge function and GitHub Actions cron for notify_sms.py not written. No UI to opt customers in/out or edit templates (server fns exist; owner can call them; add to customers screen later).
* integrations.js not run in a real browser/Playwright (no 360px overflow check); not wired until the lead adds ia.js/index.html lines.
* Recon matches mobile payments by ref only; no auto-posting of gateway money into sale_payments (by design).
* Non-owner path for payment_intent_create in the POS UI not built.
