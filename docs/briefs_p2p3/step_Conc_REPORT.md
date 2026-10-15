# Step Conc - report (branch fix/phase-Conc)

`supabase/phase109.sql` (+ `phase109_test.sql`): additive, paste-twice safe, guard 72..103, body guard (refuses to overwrite a function with a bosNN tag it does not know), tag bos109. 12 functions re-created from the latest bodies (build of PASTE_ORDER incl. 103; no 104/105/108 existed on origin yet, 106/107 are independent). Old tags kept.

| finding | fix (verified, not copied blindly) |
|---|---|
| F1 production_post oversell | row lock (`order by item_id for update`) on ALL ingredient + packaging balances AND the finished-good balance, one item order, before the shortage check (FG added by me: avoids a lock-order cycle between recipes that use each other's output) |
| F2 scan_confirm(post) deadlock | supplier lock `FOR NO KEY UPDATE` in all 7 functions that take it (post/void purchase, _bp_pay99, pay/void supplier payment, supplier refund/void) |
| F4 bulk option views | keys upserted sorted (`order by key, position`, so "later duplicate wins" is kept) |
| F5 setup_recommend_apply | global advisory lock after the client lock: second tap sees `already`, each rule applied/audited once |
| F6 card_settle | default behaviour unchanged. New rule `card_settle_over_mode` off/warn/refuse (default off). warn = saved + yellow exception `card_settle_over` + corrected `over`/`unsettled`; refuse = `over_settlement`; both subtract settlements saved but not yet booked and take a per-place advisory lock. Advisor row (phase 109, sort 350; phase101_test ignores phase 109 rows) recommends warn |
| F3 | untouched (Sec2/phase105) |

Tests
- Concurrency: `tests/sql/concurrency/verify_fixes.sh` (builds NO109 and phase109 templates). Before: 10 FAIL (S04 default, S08 warn/refuse, S09b, S12b, S13). After: 57 PASS / 0 FAIL, 0 deadlocks. S08 gained default-off/warn/refuse checks; `build_template.sh` includes phase109 (`NO109=1` = old state); `proposed_fixes.sql` is now historic.
- `phase109_test.sql`: 21 checks (shape, sorted bulk, repeated apply, card_settle off/warn/refuse with hand-computed 600/100/50/850).
- docs/PASTE_ORDER.md: rows 33 (106), 34 (107), 35 (109) + section J; tools/check_paste_order.py knows them. Numbers 104-108 reserved.
- Full suite results: see the final lines below.

Final results (phase109 on the full chain 72..103, 106, 107, 109)
- tests/sql/run_all_sql.sh: total fail 32 = baseline, no regression (phase109 23/0). To keep old suites green: phase103 body guard now also knows bos109 for setup_recommend_apply (tags only); phase89e/phase103/phase87/phase101 tests adapted (109 re-pasted after 103, `_post_purchase_p13` and phase109 rows excluded from re-paste hashes/counts). Invariant: if phase87/89 or 103 is pasted again, paste phase109 after it. run_all_sql.sh no longer picks the "Live status" row of PASTE_ORDER as a file (it used to paste phase103 a second time).
- e2e both modes (rec, def): 0 fail (205 / 206 pass).
- Full tests/sql/concurrency/run_all.sh: 222 PASS, 1 FAIL (S10 = F3 inbox_unmask, left to phase105), 0 deadlocks.
- origin/fix/phase-Sec2 does not exist yet; qa/errlog (phase107) is already in the branch.
