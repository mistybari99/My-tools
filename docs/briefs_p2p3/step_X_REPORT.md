# Step X report - fixes from the independent QA (branch fix/phase-X, supabase/phase87.sql)
Base: integration/p72-p79 (phases 72..79, 82, 84). Paste order: ... 79, 82, 84, **87 last**. Additive, paste-twice safe; a guard at the top refuses if 72..79 / 82 / 84 are missing. Re-created functions come from the LATEST definition on the final build (pg_get_functiondef), every older tag (bos10..bos84) kept, my lines tagged `-- bos87`. Nothing on the live DB; every default = today.

## যাচাই হয়েছে (run)
Fresh DB built phase8..71, 72..79, 82, 84, 87 (one DB per suite).
- **phase87_test.sql: 53 pass / 0 fail** (includes paste-twice: function hashes identical after a second paste; tags bos87 + bos82/bos73/bos43/bos72/74 survive).
- Item 1, owner approval: the owner approves a recipe / cost rule he changed himself -> approved, never `self_approve_refused`; one `audit_log` row `self_approved` (table recipes / cost_source_rules, who, note); return value has `self_approved:true`, `suggestion:'ask_another_approver'`, `suggestion_bn/mix/en` (English has no Bangla letter). Approving again = dup, no second row. A different approver = plain approval, no suggestion, no audit row. A non-owner with the grant is still refused; a non-owner with `recipe_self_approve` ON is allowed as before (now also marked + suggestion).
- Item 2, a2-F8 `expiry_sale_guard` off|warn|refuse (default off): off = today (red `sold_expired`, no batch text; the old `block_expired_sale` still works); warn = sale goes through, the red line now names batch id + expiry date; refuse = `expired_stock_blocked`, nothing posted, a late offline sale is still accepted.
  a2-F9: another user reusing a client_id -> clean `client_id_taken` (was a raw unique violation); same user = old sale back (`dup`), no extra sale row.
  a4-F11 `purchase_backdate_flag` off|warn (default off): a backdated bill posts and raises one yellow `purchase_backdated`; a bill dated today raises nothing; stock is still stamped now.
  a4-F12 `ledger_problem_count(p_loc)` returns the number `ledger_post_problems()` lists (same visibility rules).
- Item 3 `production_double_issue_guard` off|warn (default off): trigger on `stock_ledger` (only `issue_out` rows). Production + stock_issue / form out-line (ref_type issue / entry) of the same item, place and day (either order) -> one yellow `production_double_issue`; not repeated; another item or another day raises nothing; never blocks (errors inside are swallowed). `production_recommendations()` (owner only): production_requires_recipe -> ON, production_double_issue_guard -> warn, production_requires_cost -> refuse; each with current / recommended / reason_bn / reason_mix / reason_en. Changes nothing.
- Regression, every older suite on its own fresh final build (...84, 87): 8: 107 (1 fail), 10: 307 (1), 11: 68, 12: 97, 13: 76, 14: 153, 15: 114 (1), 16: ok, 17: 147, 18: 108, 19: 94 (1), 20: 63, 21: 75 (1), 23: 91 (1), 24: 22, 25: 91, 26: 117, 27: 55, 28: 41, 40: 119, 41: 171, 42: 160, 43: 144, 44: 181, 45: 46, 46: 117, 47: 72 (2 fail), 48: 54, 49: 16, 50: 45, 51: 23, 52: 33, 53: 112, 54: 84, 60: 62, 61: 114, 62: 74, 70: 28, 71: 26, 72: 70/1, 74: 96/0, 75: 76/0, 76: 108/0, 77: 26/0, 78: 101/0, 79: 77/0, 82: 57/0, 84: 64/0. Same numbers and same known fails as the INT report except the two points below.
  - **EXPECTED-CHANGED (owner decision), old file untouched:** phase73_test.sql line 126 "T4 owner who changed rc3 himself cannot approve it" and line 146 "T4 with recipe_self_approve ON the owner may approve his own change" (rc3 is already approved by the first call, so the second returns dup). phase73 is now 96 pass / 2 fail. phase75_test:94 and phase78_test:299 use a non-owner and still pass.
  - **phase22: 8 fails come from phase84, not from 87** (the fixture `delete from stock_balance` is refused by the new no-delete trigger; phase21 has the same `delete from stock_balance;` but its numbers did not move: 75/1, the known T1). Old files not touched. Trivial copies added: `supabase/phase21b_test.sql` (75 pass / 1 fail = the same known T1 "catalogue lists 12") and `supabase/phase22b_test.sql` (**82 pass / 0 fail**); the only difference is the fixture delete wrapped in `alter table stock_balance disable/enable trigger stock_balance_guard84`.
- Web, node tests one at a time: guards 35/0, ia 0 failures, nav ok, nav2 0, lang_en 0 Bangla in 69 English strings, salesx 0, recipebook 49/0, costsources 34/0, recipes 0, stock2 0, pos2 ok, pos_units 0, costing 39/0, costattrib 59/0, accounts 0, inbox 29/0. A script check found no Bangla in the English slot of any L(...) I added.

## Web wiring done
- ia.js: `rec('guards', 'settings', ...)` (owner) + index.html `<script src="guards.js">` (after paths.js). guards.js also lists the `production_recommendations()` rows (skipped silently if phase87 is not pasted).
- pos.js BUSINESS regex: + `unit_unknown`, `production_negative_reason_needed`, `client_id_taken` (a refused queued sale goes to the failed list at once instead of 3 retries).
- stock2.js error map: + client_id_taken, grn_link_required, void_has_return, void_would_go_negative, void_has_grn_batch, production_negative_reason_needed (texts copied from guards.js; client_id_taken is new). Existing text not rewritten.
- salesx.js: `select('*')` on online_orders replaced by the granted column list (phase61 column grant; only `sale_client` is not granted).
- recipes.js: the production sheet has an optional "Actual total output" input, sent as `p_actual_yield` only when typed (the 6-argument call otherwise); `cost_missing` error label added.
- recipebook.js / costsources.js: after approve, the non-blocking "ask another approver" text is appended to the toast when the server returns it.

## Findings from QA item 3 - decisions
| id | decision |
|---|---|
| a2-F8 | switch added. Honest note: `warn` is today's red alert made more precise, not a new block; `refuse` equals block_expired_sale for sales at the till, and it still cannot sell an item whose only stock is expired (all-or-nothing per line) - **needs owner** if he wants a per-line override. |
| a2-F9 | different-user reuse fixed. **Accepted / needs owner:** the same user re-sending a client_id with a different cart still gets the old sale back (a real retry cannot be told from a wrong reuse without storing a hash of the lines; changing it risks losing a real retry). |
| a4-F11 | only a flag (off by default). **Accepted / needs owner:** stamping the stock ledger with the bill date instead of now() would change averages, batches and past-day reports and may hit closed periods - not guessed. |
| a4-F12 | already a flag and never blocks approval (`_entries_post_ledger` writes a yellow exception; per-line failures via `_elp_exceptions`). Count function added. **Not done:** the dashboard badge for non-approvers (UI in forms_stock.js); the exception insert is still wrapped in `exception when others then null` (phase20, unchanged). |

## পড়ে বোঝা (code read, not run)
- The form out-line path (ref_type `entry`, phase20:182) is covered by the same trigger; the test emulates it with a direct `stock_post(... 'issue_out','entry', ...)` as postgres, not through a real approved form.
- The trigger costs one cheap `WHEN (reason='issue_out')` check per ledger insert and, only when the switch is not off, one lookup; no timing measured.
- The owner exemption uses `is_owner()`; a non-owner holding the grant is unchanged.
- guards.js "apply recommended" works through the existing set_rule for the three new keys (not browser-tested).

## যাচাই হয়নি
- Nothing run against the live DB or a real Supabase; no real phone / browser (Playwright stub tests only).
- Legacy tests/sql/test*.sql scripts not run.
- No dedicated owner screen for the new switches: only through the switchboard / guards page. Bigger UI skipped: B4/B6 figures on biz.js / reports.js, E9 pack-warn / flag list, sales_channel create UI, run-detail screen, dashboard badge for the ledger count.
- S2 (setup_recommendations + activation guide) is separate: `production_recommendations()` is a row source to merge there; expiry_sale_guard and purchase_backdate_flag are not in any recommendation list yet.
- Concurrency (two users, same client_id, same moment) is covered only by the handler branch, no two-session test.
