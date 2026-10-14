# Step E-b report (phase83) - form vs screen, expense double count, transit shortage, offline POS
Branch fix/phase-Eb (base fix/phase-C2b). Files: supabase/phase83.sql, supabase/phase83_test.sql, web/posfail.js, tests/web/posfail_test.js, small tagged edit of web/pos.js. Not pushed; nothing touched on the live DB.
Build order tested: phase8..phase71, 73, 74, 75, 78 (phase72 skipped), then phase83. phase83 applied twice = no error.

## 1. যাচাই হয়েছে (run on scratch DBs)
- phase83_test.sql: 76 pass / 0 fail. Hand numbers: 5 kg cake = 0.5 batch -> flour 100-3=97, sugar 50-1.5=48.5, cake cost (3x40+1.5x20)/5 = 30; transit 10 sent / 6 received -> short 4 x cost 40 = 160, loss mode leaves loc1 80 + loc2 12 = 92 (100 - 8 lost); offline sale 2-5 = -3 stock, override sale -3-4 = -7; failed-card board 2 open / total 400.
- E5: form_051_mode reference = unchanged (cake +5, cost NULL, flour untouched) and now raises yellow form051_cost_null; post = ingredients out at average cost, finished goods costed, no recipe -> line fails (nothing minted), not enough flour -> whole line fails, nothing half-posted; refuse = line skipped form051_not_a_source. Primary 'a': skipped slip creates a PENDING shadow_link (primary entries, shadow stock_screen); unmatched_forms() lists lines with no same item/place/day screen record, shrinks after the screen action; unmatched_forms_sync() confirms matched links; dup_suspects 'production_screens' flags run + stock_production_in of the same item/day (other item not flagged); form_guard_recommendations() 4 rows, 3 languages, owner only, changes nothing.
- E6: dup_suspects 'expense' branch (quick expense vs approved 10-2 line, same place/day/head/amount, not linked); suggest_expense_link / expense_link_apply: fully covered voucher becomes the locked shadow (day book counts once, edit refused), voucher with an uncovered extra line refused (not_fully_covered), two identical quick entries + one voucher line link exactly one.
- E7: default keep_in_transit = no ledger change (as today) + transit_short_open() list (value only with cost right); transit_short_resolve() books later (reason required, once); loss mode books +short (cost blank, average unchanged) then -short transit_loss at the sender's cost; full receipt books nothing; transit_open_hours blank = no alert, 2 = a 3-hour-old open transfer appears in urgent_alerts once.
- E8: record_sale_offline with switch off = record_sale2 (refused insufficient_stock); switch on: online path still refused, replay accepted + yellow offline_soft_stock, same client_id twice = one sale; pos_replay_override: needs grant, reason >= 3 chars, original client_id, one log row + one yellow exception, second call = dup, closed period still refuses; trail append-only, cashier cannot read/write it; pos_failed_note idempotent, board count, only reporter/owner/grant holder can close, cards never deleted.
- Regression, before (DB through phase78) vs after (+phase83), 35 older suites run on fresh copies: IDENTICAL output. Includes 10 (306/1 date-dependent T12), 12, 19, 20, 22, 23, 24-28, 40-54, 60-62, 70, 71, 73, 74, 75, 78. Pre-existing fails unchanged: phase10 T12, phase19/23 T0 'no cost columns', phase47 role-list (2).
- Web: node tests/web/posfail_test.js 23 pass / 0 fail (all strings bn+en+mix, English mode has no Bangla letters, fallback to record_sale2 on an old DB, override args, export, report, guarded pos.js hooks). Existing playwright tests/web/pos2_test.js output identical before/after the pos.js edit, and identical with posfail.js loaded.

## 2. পড়ে বোঝা (code read only)
- GL/journal effect of a voucher that becomes a shadow AFTER it was already auto-posted: relies on the phase50/52 rule that shadows are skipped by _acct_docs (as for 02-2). Not run with accounting on.
- transit_loss has no journal document yet (Step D1 books it); phase83 only writes the ledger row (reason + cost).
- notify email path: _transit_open_scan83 uses _notif_add like notify_scan; the python mailer (tools/notify_digest.py) not run.
- RLS on pos_failed_cards / pos_replay_log written like the other trail tables; checked for cashier only.

## 3. যাচাই হয়নি
- Real phone / browser flow of the new buttons with phase83 on a real Supabase; manager override from a cashier's own phone (needs the cashier to hold grant pos_replay_override or the manager to log in on that phone: no emergency-window link was built).
- UI for E5-E7 (unmatched list, recommendations, expense-link offer on 10-2 approval, transit lists, switches) is NOT built: SQL functions only; posfail.js covers E8 only. Switches appear in the generic Switchboard from the rules table.
- Concurrency, concurrent override + original replay race (unique client_id is the guard, not load-tested).
- The failed card itself lives only in the phone's localStorage; the server keeps a summary (no customer data).

## Re-created functions (latest definition, lines tagged -- bos83 / bos83): 
_elp_post_line (phase51 text), dup_suspects (phase49), stock_receive_transfer, urgent_alerts (STABLE -> VOLATILE, needed for the scan), _sale_stock_out. Also: stock_ledger_reason_check gets 'transit_loss' (merge-safe DO block that reads the current list: other branches adding reasons will not clash).
NOT re-created: production_post, recipe_cost, _acct_docs, _p27_pl, biz_daily, acct_status, post_purchase, void_purchase.
Design notes: form_051_mode has 3 values (reference | post | refuse): "reference" literally means "unchanged / as the path switch says" (today), refuse added to cover "or refused". transit_short_mode keep_in_transit = today (shortfall books nothing; kept visible in transit_short_open). Override created_by = the manager; note carries the reason.

## web/pos.js edit (small, tagged bos83, 5 lines, every hook guarded by B.posfail, no behaviour change without posfail.js)
line ~387 failed-card buttons; ~480 pos_discard also closes the server card; ~311 send(p, replay) uses record_sale_offline for queue replay; ~353 flush passes replay; ~363 reports failed cards.

## Lines for the lead (not edited)
- web/index.html: after pos.js add `<script src="posfail.js"></script>`
- web/ia.js (owner board / control tile): rec for page id `posfailed` (BOS_PAGES.posfailed in posfail.js), label L('Offline POS — আটকে যাওয়া sale','Offline POS - refused sales','Offline POS — আটকে যাওয়া sale'); board badge via B.posfail.boardCount() -> {open, by_location}.
- Missing UI screens to add later: unmatched_forms, form_guard_recommendations, suggest_expense_link on the 10-2 approval sheet, transit_short_open / transit_open_list.

## Owner decisions
1 form_051_mode: reference (today) vs post vs refuse. Recommended: post when 05-1 is the production record, else reference.
2 transit_short_mode: keep_in_transit (today) vs loss. Recommended: loss.
3 transit_open_hours: blank today; owner types the number (no value built in).
4 offline_soft_stock: off today; recommended on (goods already handed over).
5 Who may hold grant pos_replay_override (managers) and whether a cashier-phone emergency approval link is wanted.
6 Whether linking a voucher to quick entries should be automatic on approval (now: offered, applied by the owner/approver only when every line is covered).
## Phone-impossible
Applying phase83 on the live Supabase (owner pastes SQL), deploying web files, any scheduler/mail setup for the urgent-alert email. Nothing here needs a script from the owner.
