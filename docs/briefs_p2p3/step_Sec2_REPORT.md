# Step Sec2 - fixes of the second security review (branch fix/phase-Sec2, from integration/p72-p79)

Files: `supabase/phase105.sql` (LAST; phase104 stays reserved), `phase105_test.sql` (52 assertions; 26 fail on a build without 105), `tests/sql/p105_conc.sh` (unmask race), web edits tagged bos111 (itemimg.js, catpick.js, purchaseprint.js, landed_q4.js, index.html), tests `tests/web/sec2_test.js`, `sec2_itemimg_test.js`, `sec2_csp_test.js`. Review: scratchpad SECURITY_REVIEW2.md (snippets verified, three were wrong or incomplete, see "Differences").

| Finding | Fix | Proof |
|---|---|---|
| H1 PII bypass | `customer_dues`, `customer_advances`, `customer_profile` (the "customer card") use `_cust_pii103` (owner and view_customer_mobile holders unchanged; inbox_pii_mode off = no change). `inbox_pii_guard_on` now also closes online_orders note, draft_note, lines. New opt-in switch `customers_pii_guard_on` (OFF) closes customers.mobile/whatsapp/address/note for direct table reads. `customer_save` ignores a value that holds the mask dot (a masked screen value is never saved back). | phase105_test H1 blocks |
| M1 unmask race | advisory lock before the count | p105_conc.sh: BEFORE 2 reveals, AFTER 1 |
| M2 auto payment | new `_bp_auto_ok105`: skip + yellow flag `bill_pay_auto_skipped` when amount >= bill_pay_large_amount, or (purchase) poster lacks supplier_pay | M2 block (700 / 6000 / 5000 / 4999, cost 300 / 5000) |
| M3 keep_credit | direct void of a linked payment raises `void_the_bill`; bill void cascade unchanged | M3 block |
| M6 phone regex | separators space, tab, NBSP, ( ) . - / _ (1-3); dates 14/10/2026, 2026.10.14 left alone; comma NOT a separator (prices) | M6 block |
| L3 L4 L5 L6 | private salt table `bos_salt105`; `client_id_reused`; one blocked log line per person per minute; directory name C••• in mask_all_pii | L3/L4/L5/H1 blocks |
| M4 | itemimg: no signed link persisted, stored paths + Cache API key bound to the user id, cleared on SIGNED_OUT and on user change | sec2_itemimg_test (14, 8 fail before) |
| L1 L2 L8 | CSV `'` guard; okMail strict; `CSS.escape` | sec2_test (18, 12 fail before) |
| M5 CSP | meta in index.html: script-src self + sha256 of the one inline theme script + wasm-unsafe-eval + cdn.jsdelivr.net (pinned tesseract), connect-src self + *.supabase.co + wss + jsdelivr + tessdata.projectnaptha.com, img-src self data: blob: *.supabase.co, style-src self unsafe-inline + fonts.googleapis.com, font-src fonts.gstatic.com, worker-src self blob:, frame-src self blob: about:, object-src none, base-uri self | sec2_csp_test: all 70+ IA routes opened with mocks, 0 violations; negative controls blocked |

## Differences from the review text
- M3: `void_supplier_payment` already refuses linked payments (`void_the_bill`), and the bill cascade voids payments BEFORE the bill row becomes void, so the review's "parent bill is void" test would break the cascade. The trigger now detects the cascade by its caller (`_void_purchase_p13`).
- L2: the old okMail already refused a second `@`; the real hole was `?bcc=` without `@`, `&cc=`, `,` `;`.
- H1 step 3 (setup_recommendations pushing the guard on) NOT done, see below.

## Not fixed / owner decides
- **Direct table reads stay open until the owner turns on `inbox_pii_guard_on` / `customers_pii_guard_on`**: nav search, filters, invoice, POS receipt and accounts/cashmoves read customers.mobile with plain selects, and salesx order edit reads online_orders directly; switching on breaks those until they move to RPCs (web files outside this step's scope). Both switches default OFF.
- Other readers of customer mobile not in the review (rpt_raw, _r3q_*, invoice_data92, record_sale2, notify_enqueue) were not changed.
- Edit form: a user who sees a masked address/note can no longer overwrite the real value (ignored), but cannot edit it either.
- L7 public setup/audit SQL pages: documentation only, no secrets; owner decides whether to unpublish.
- M5: a meta CSP cannot carry frame-ancestors/report-uri; set those as real headers if the host allows. Real OCR (tesseract worker/wasm/language data over the internet) could not be run here (no network): it is covered only by a mocked CDN + blob worker + WebAssembly check. If OCR scanning fails on a device, remove the meta and report the blocked URL. If the inline theme script is ever edited, its sha256 in the meta must change (sec2_csp_test checks it).
- itemimg_test.js: the mocked picture host changed from mock.local to mock.supabase.co (needed by the CSP).

## Order and tests
- Paste phase105 after 103 (docs/PASTE_ORDER.md rows 33/34, section H). After a re-paste of 89/94/96/97/98/103: paste 103, then 105.
- `phase103_test`, `phase89e_test`, `phase98b_test` end with a phase103 paste and are false by design once 105 is on top (1/1/2 fails, baseline updated); replacements `phase103b_test`, `phase89f_test`, `phase98c_test` pass 0 fail. phase103_test has 0 fail on a build without 105.
- run_all_sql.sh: every other suite = baseline; e2e (phase103 scripts) rec 205/0, def 206/0.
- Web: order_test, lang_en_test, purchaseprint(_pw), catpick_pw, landed_pw, inbox, itemimg_test pass; catpick_test, itemimg_static_test, optionsx_b_test, q4_test keep their old "last script" failures (identical without my edits).
