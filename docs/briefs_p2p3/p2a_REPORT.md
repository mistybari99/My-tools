# p2a report - P2 gap #6: journal auto-post sources (phase52)
Files: supabase/phase52.sql, supabase/phase52_test.sql, this report. No web file (nothing needed: the existing accounts screen lists acct_mappings and acct_post_pending already covers new sources). No ia.js line, no script tag.

## Built
* **Re-created (latest definitions, bos50 blocks kept, only bos52 lines differ):** `_acct_docs`, `_daybook_lines23`, `daybook_vs_journal` (phase49).
* **(a) payroll_payment** (payroll_payments, status done): Dr salary expense (5200), Cr cash/bank/mobile by mode, party staff. A run that is a locked shadow (`is_shadow('payroll_runs')`, i.e. 02-2 sheet is the record) posts nothing. Advance recovery: payroll_lines.advance_recovery is split over the payments pro rata (rec = recovery x paid / net) and credited to Staff advances; salary expense = paid + recovered. Void payment -> reversing entry.
* **(b) staff_advance** (employee_advances, mode cash/bank/mobile): Dr Staff advances (1220), Cr cash/bank/mobile. mode `none` posts nothing (money not moved there). Void -> reversal.
* **(c) partner_capital**: contribution Dr cash / Cr owner_capital; return_of_capital Dr owner_capital / Cr cash; loan_in Dr cash / Cr Partner loans; loan_repayment Dr Partner loans / Cr cash; owner_drawing Dr owner_drawings / Cr cash (party type partner). in_kind posts nothing and is reported under `waiting.in_kind`.
  * Count once: the cash_move owner_topup/owner_draw that is a shadow of a partner-capital record (phase51 link, primary=a) is not posted, any copy posted before the link is REVERSED, and it is dropped from `_daybook_lines23`; the partner-capital record takes its place in the day book (same place/day/mode, kinds owner_topup/owner_draw). Primary=b: the cash move posts, the partner-capital copy does not. Unlinked cash moves keep posting as before. If the primary is voided the shadow counts again (nothing lost). Helper `_shadowed52` = `is_shadow` AND primary still live.
  * Re-live after reversal: journal is unique on (source_type, source_id), so a record that comes back to life posts under `id:gN` (helper `_acct_sid52`, generation 0 = plain id, so all existing postings are untouched).
* **Mappings/CoA (idempotent, owner can re-point in the accounts screen via acct_mapping_set):** `salary_exp`->5200 (existing), `staff_advance`->1220 (existing, was unmapped), `partner_loan`->new liability "Partner / owner loans" 2500 (2510 if the owner already took 2500).
* **daybook_vs_journal kinds:** journal payroll_payment=salary, staff_advance=advance, partner_capital=owner_topup/owner_draw/loan_in/...; day-book lines coming from paper forms 02-2/02-3 are now kinds `salary_form` / `advance_form` (day-book only, no journal source); partner capital with no place (no cash-move link) shows as `unplaced_<kind>`. For a link made after posting, the place is read from the link.

## Tests
supabase/phase52_test.sql: **33 pass / 0 fail** (fresh DB a52db through phase52; phase52.sql applied twice, error-free). Covers balanced entries, dry run writes nothing, idempotent re-post, void reverses (payment, advance, partner capital), shadow run not posted, link after posting reverses the cash-move copy, link before posting never posts it, primary=b, void of primary releases the shadow, day book vs journal diff = 0 for salary/advance/owner_topup/owner_draw, closed helpers, storekeeper refused.

## Regression (DB through 51 vs through 52)
phase40 119/0 both, phase49 16/0 both, phase51 23/0 both, phase23 92/0 both, phase42 160/0 both. **phase50: 45/0 -> 44/1**: the single FAIL is T7 "day book vs journal ... only the 02-2 salary differs" which expects the kind name `salary`; it is now `salary_form` (intended rename, same row, same amount). phase50_test.sql is not mine and was not edited; the lead may change that string.

## NOT done / UNVERIFIED
* (d) 10-1 cash handover / 10-3 digital payment: NOT posted. The hub side of a 10-1 handover is not recorded (day book marks it internal), so a one-sided entry would be a guess; needs a hub-receipt pairing decision.
* Paper forms 02-2 (salary receipts) and 02-3 (advances) are still day-book only (no journal entry); shown as salary_form/advance_form diffs. 10-2 submitted-vs-approved timing difference unchanged.
* Partner capital without a cash-move link has no place: journal location null, absent from the per-place day book (unplaced_* diff by design). If an owner enters BOTH an unlinked contribution and an unlinked top-up for one event both post (dup_suspects D4 flags it; linking fixes it).
* Salary figures: payroll structure deductions (tax etc.) are not split to a liability; expense = net paid + advance recovery. Rounding of pro-rata recovery may drift by 0.01.
* acct_post_pending still lists 'staff_advances'/'salary_payments' in `skipped_sources` (phase40 text for tables that never existed); cosmetic, not changed.
* Other readers of cash_moves for owner_topup/draw (cash position reports) were not changed; only the day book and journal follow the shadow rule. Not checked for double counting there.
* Not tested with salary_view-only users (daybook_vs_journal is owner/accounts_manage anyway).
* The 6 scratch DBs a52base/a52db/a52dbx/a52r1/a52r2 may be dropped.
