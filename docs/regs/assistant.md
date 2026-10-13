# Module G registration (business assistant) - for the lead to apply

## (a) web/ia.js - one record (group `reports`)
```js
  rec('assistant', 'reports', ['প্রশ্ন করুন (সহকারী)', 'Ask (assistant)', 'Ask (সহকারী)'], { icon: 'doc', ok: (c) => c.own || c.GF.head_management === true || c.GF.assistant_use === true, kw: ['ask', 'assistant', 'question', 'help', 'ai', 'chat', 'how much', 'why', 'প্রশ্ন', 'সহকারী', 'জিজ্ঞেস', 'সাহায্য', 'কত', 'কেন', 'হিসাব'] }),
```
* For the predicate to see `assistant_use`, add `'assistant_use'` to the `codes` arrays in `loadGrantFlags()` of web/nav.js (both branches).
  People opened only through rule `assistant_roles` do not see the menu entry; the page itself works for them (the server decides), so the lead may use
  `ok: any` instead if the owner opens it to roles.
* Floating "Ask" button (later, by the lead): call `BOS.assistant.open()` or `BOS.assistant.open('question text')`.

## (b) web/index.html - after reports2.js / daybook.js (needs entry.js, app.js, ia.js loaded first), tools file BEFORE the page:
```html
<script src="assistant_tools.js"></script><script src="assistant.js"></script>
```
* Service worker (optional): add `assistant_tools.js`, `assistant.js` and `data/kb.json` to the cache list in web/sw.js so knowledge questions work offline.

## (c) SQL / rules / grants added by supabase/phase47.sql (paste after phase28; does not need 40-46)
* Rules (Switchboard, module `assistant`): `assistant_on` (ON), `assistant_roles` (blank), `assistant_provider` (local | llm_proxy, default local),
  `assistant_monthly_token_budget` (blank = no paid model), `assistant_cache_seconds` (60), `assistant_actions_on` (OFF, reserved),
  `assistant_voice_on` (OFF), `assistant_rate_per_hour` (120), `assistant_closed_age_days` (45).
* Grants: `assistant_use` (use the assistant), `assistant_health` (see the setup check). Owner and `head_management` have both by design.
* Tables: `assistant_notes` (owner-approved rules/procedures/facts; RLS read for assistant users; writes only via RPC; no delete; audited),
  `assistant_usage` (append-only usage log without content; owner reads).
* Functions (authenticated): `assistant_me()`, `assistant_health()`, `assistant_log(text,text,text[],int,int,int,boolean)`, `assistant_usage_summary(date)`,
  `assistant_proxy_check()`, `assistant_note_save(bigint,uuid,text,text,text,text)`, `assistant_note_retire(bigint,text)`.

## (d) Publish routine
`python3 tools/build_kb.py` before publishing web/ (fails on a dead route / rule / grant in a playbook) and copy `web/data/kb.json` with the web files.
The Edge Function `tools/edge/assistant-proxy.ts` is NOT to be deployed without the owner's explicit approval (see docs/ASSISTANT.md section 5).
