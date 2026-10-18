# Integration note XB: order-to-cash for a sweets and cake shop (part 1 of 3 built)

Scope: the owner brief "finish the complete order-to-cash loop" (mobile payments, custom cakes, riders and COD, festival playbook, small order extras). **This package is partial.** Built: mobile payment capture and reconciliation (backend), the custom-cake workflow (backend), riders / delivery status / COD reconciliation (backend), and the payment-SMS reader (pure function). Not built: festival playbook, ingredient pre-purchase list, web screens, and most of item 5. See section 5.

Local throwaway Postgres only (port 5860, database `xb_base` = phases 8 to 478 built by `tests/sql/build_fresh_db.sh` with `ORDER=all`). The live Supabase project was not touched. Nothing was pushed.

## 1. Files

| File | What |
|---|---|
| `supabase/phase491.sql` | payment captures (`pay_captures`), statement lines (`pay_statement_lines`), capture, verify, screenshot, statement import, daily tie-out. Rules `pay_capture_on` (OFF), `pay_capture_tol` (blank). Grant `pay_verify`. Bucket `payproof` (private). |
| `supabase/phase492.sql` | cake price table (`cake_price_rules`), cake jobs (`cake_jobs`) and trail (`cake_job_events`), quote, create, confirm, move, photo, cancel (calls `c2_order_cancel`), due sheet, customer text. Rules `cake_flow_on`, `cake_capacity_day`, `cake_lead_days`, `cake_photo_required` (all OFF or blank). Grant `cake_price_manage`. |
| `supabase/phase493.sql` | riders (`riders`), zones (`delivery_zones`), delivery jobs and trail (`delivery_jobs`, `delivery_events`), COD deposits (`cod_deposits`), reconciliation and cases (`cod_cases`), performance. Rule `xb_delivery_on` (OFF). Grant `rider_manage`. |
| `supabase/phase491_test.sql`, `phase492_test.sql`, `phase493_test.sql` | SQL suites on `test_*` data (fixture `tests/sql/c2_fixture.sql`). |
| `tests/sql/xb_run.sh` | runner: copies `xb_base`, pastes each XB phase twice (second paste on a copy), runs the suite. |
| `web/xb_paysms.js` | pure reader of a pasted bKash / Nagad / Rocket SMS: Trx-ID, amount, sender, date, direction, reasons. Saves nothing. Not loaded by `index.html`. |
| `tests/web/xb_paysms_test.js` | 32 sample texts (test fixtures only, invented numbers, no names). |
| `docs/integration/XB_info.json` | (i) texts for the 10 settings and grants above. `python3 tools/merge_pkg_info.py --dry` reports 10 entries. Not merged into `web/data/info.json` (integrator step). |

Paste order: after phase 478, paste 491, 492, 493 in that order (each once; each is safe to paste again). `tests/sql/ORDER.txt` and `docs/PASTE_ORDER.md` were not edited.

## 2. Hook sites

No old SQL function or table was edited or re-created. Each new function is a new `xb_*` / `_xb54x_*` name. Hooks used from old code (read-only calls):

| Used | Phase | Why |
|---|---|---|
| `online_orders` (balance = subtotal - discount + delivery_charge - advance) | 61 | expected amount of an order payment, cake order total, delivery COD |
| `online_order_save`, `online_order_status`, `online_order_deliver` | 61 | used by the tests to create and deliver an order (no change to them) |
| `c2_order_spec_save`, `c2_order_cancel` | 445, 448 | cake spec on the order; cancel and refund of a cake |
| `record_sale2` | 6 / 43 | used by the tests only, to make a sale with a due amount |
| `d_wallets` (active wallet codes) | 83 | wallet validation and statement tie-out |
| `notify_enqueue`, `notify_templates` (two templates added: `cake_confirmed`, `cake_ready`) | 62 | customer SMS, only when `notify_sms_on` is on and the customer has opted in |
| `crm_contact_prefs` (do-not-contact) | 303 | refuses the customer SMS |
| `employees` | 41 | optional staff link of a rider |
| `log_change`, `no_hard_delete`, `rule_on`, `rule_num`, `can_do`, `can_loc`, `is_active`, `is_owner`, `has_grant` | older | standard guards |

Web hook sites: none (no screen, no `ia.js` line, no `index.html` tag). The SMS reader is a library; a future screen calls `BOS.xbPaySms.parseMobilePaySms(text)` and must show the result for confirmation before calling `xb_pay_capture`.

## 3. Behaviour and decisions taken (defaults)

- Every new behaviour is behind a switch that is OFF (`pay_capture_on`, `cake_flow_on`, `xb_delivery_on`), or a blank number that blocks the form that needs it (`cake_capacity_day`, `cake_lead_days`, `pay_capture_tol` blank = exact match, `cake_photo_required` OFF). No limit, price, fee or code is invented: an empty price table gives "price_rules_missing"; a zone with no fee cannot be assigned.
- A payment capture is evidence, not a posting. It does not write `sale_payments`, `cash_moves` or the journal. The existing payment path still records the money; the tie-out compares the wallet statement with the captures.
- Nobody verifies the capture they wrote (`own_capture`), including the owner. A flagged (overpay / underpay / no target) or rejected capture needs a note.
- A Trx-ID is unique across live captures (`duplicate_trx`), normalised to upper case; the client id makes a retry return the earlier row.
- The cake job changes only its state, photo and cancel reason; the quote and the order are fixed after creation. Delivery of a cake requires the app order to be delivered first (the order's own money path), and the photo when `cake_photo_required` is on.
- The cake order total must carry the quote (`order_total_below_quote`). The order lines are not rewritten automatically.
- COD: the difference between collected (delivered jobs of the day) and deposited opens one case per rider per day (`cod_cases`), explained by the owner. **No cash move and no entry is posted.** Linking a short to the existing shortage cases needs an entry row (`shortage_cash_cases` is entry-based); that is an owner decision.
- Journal: none of the XB functions writes a journal entry (tested: `journal_entries` with `source_type like 'xb%'` is empty). So "every journal entry balances" is trivially true for this package; the paid / refund / COD flows post through the existing functions and were not re-tested here.
- Rider live location: a `https://` link field only. No tracking.
- Storage: `payproof` bucket (JPEG, 3 MB, private) and path rule `pay/<place>/<file>.jpg`; cake photos use a path rule in the table only (no bucket policy added, so the cake photo path is a text reference until the owner decides on storage).

## 4. Tests run (local throwaway Postgres 16, port 5860)

| Suite | Result |
|---|---|
| `PGPORT=5860 bash tests/sql/xb_run.sh phase491` (paste twice: no ERROR) | 36 pass, 0 fail |
| `... phase492` | 37 pass, 0 fail |
| `... phase493` | 29 pass, 0 fail |
| Total SQL | 102 checks, 0 fail |
| `node tests/web/xb_paysms_test.js` | 32 of 32 pass |
| `python3 tools/check_no_demo_leak.py` | OK |

Tests cover: switches OFF (refused, nothing written), duplicate Trx-ID (also in lower case), client-id retry, input refusals, overpay / underpay / no target, sale due amount, no self-approval, note rule, decided is final, append-only trails (delete and update refused), screenshot path and once-only, statement import (duplicates counted, bad row counted), tie-out status, anon denied, RLS on, the quote arithmetic, lead time, capacity cap (full, and freed by cancel), advance rule, chain order (no skipping), order-delivered rule, photo path, customer text and do-not-contact, COD deposit duplicate, reconcile short case (once per day), explain once, performance counts, fixed fields after creation.

The journal balance check and the defaults-parity snapshot (`integ_before_after.sh`) were **not run**. No old file was changed, so the old reports should be unchanged, but that was not proved.

## 5. Not built (brief items not delivered)

- Item 1: adapter interface for merchant APIs (not built; no outbound call exists); pending-verification **screen**; screenshot **upload** UI; CSV import UI (the function accepts parsed lines); mismatch **report screen** (the data is in `xb_pay_tieout`); the SMS parser is not wired to a screen.
- Item 2: promised time slot on the cake (`c2_order_promise_set` not called); per-slot capacity; production and decoration **printable sheets** (data only, `xb_cake_due`); the price calculator screen; birthday link to CRM; WhatsApp is a text and wa.me phone only (no send); the cake photo has no bucket policy.
- Item 3: COD to cash account and shortage cases (see section 3); delivery performance into reports #158-163 (`xb_rider_perf` exists, the reports are not changed); customer tracking text; rider screen; `delivery_jobs` does not call the order's own deliver step (the order is delivered through its existing path, then the cake, as in section 3).
- Item 4 (festival playbook, pre-order caps, ingredient pre-purchase list from forecast x recipes, extra staff shift prompt, countdown tasks): **not built**.
- Item 5: order edit history (the order already keeps its events), split payments (already supported by `record_sale2`), gift orders, repeat-order button, invoice or receipt print for web and chat orders, order-source profitability link: **not built**.
- Web: no screens, no `ia.js` registration, no Bangla / English screen text, no 360 px test. The (i) texts are English only.
- Owner decisions still open: who holds `pay_verify`, `cake_price_manage`, `rider_manage`; the cap and lead-time numbers; the SMS wording of `cake_confirmed` / `cake_ready` (Bangla and English drafts written by the builder, need the owner's read); whether COD shortage goes to the shortage cases; whether cake photos get a storage bucket.
- Not verified: real bKash / Nagad / Rocket SMS wording (the reader's layouts are UNVERIFIED); merchant API terms; the live project.
