# Integration notes: Builder B (phase81): G4 cash short, G5 customer advance, G6 transit short

Files: `supabase/phase81.sql`, `supabase/phase81_test.sql`, `web/shortages.js`, `tests/web/shortages_test.js`. No existing file was edited. Paste phase81 after phase79 (and after phase80 if it exists; they are independent). Paste-twice safe.

## 1. Hooks the integrator must add (shared functions are not edited by B)

1. **`_acct_docs(date)`** (latest body: phase79, or phase80 if it re-creates it). Add ONE line just before the final `end`:
   ```sql
   return query select * from public._b_docs(p_start); /* bos81 */
   ```
   `_b_docs(date)` has exactly the same result columns as `_acct_docs` (a test compares them). This makes `acct_post_pending`, `acct_post_pending(p_dry)` and the preview pick up the new sources: `cash_short`, `transit_claim`, `transit_recover`, `transit_writeoff`. Verified on a scratch copy: after the hook, `acct_post_pending()` posted an approved cash short (`by_type: {"cash_short": 1}`) and a second run posted 0.
   Until the hook is in, `public.b_post_pending(p_dry)` posts these sources itself (same rules: skips waiting rows, reverses voided ones). Both can coexist: the unique index `je_source_uq` stops a double post.
   Re-pasting an older phase that re-creates `_acct_docs` removes the hook: paste the hook version last, and add `bos81` to the tag test of phase79 style.
2. **Day book / P&L / balance sheet**: nothing to hook for the balance sheet and trial balance (they read journal lines). Cash short posts to 5800 (expense), so any P&L that reads the journal shows it. A P&L that reads source documents (`_p27_pl`) does not see these entries; if the owner wants them there, `_p27_pl` must read account 5800 and the transit loss (5100) from the journal. Not done by B.
3. **Day book for transit**: transfers still post no journal (unchanged). Claim/recover/write-off are journal-only events; nothing for `_daybook_lines`. Recovered money in cash (`transit_recover` with mode cash) does not appear in the day book; if wanted, `_daybook_lines` needs a line from `shortage_transit_events` where `kind='recover'`.
4. Nothing to hook for `entry_post_ledger`, `stock_receive_transfer` or `submit_entry`: rows are made by triggers (`exceptions` insert -> case, `stock_transfers` update to received -> shortage row).

## 2. Web registration (web/ia.js and web/index.html, owned by the integrator)

index.html: add `<script src="shortages.js"></script>` next to the other screen scripts.

ia.js, one record (group `acc`, same group as cashmoves; the server is the authority, `ok` only mirrors it):
```js
rec('shortages', 'acc', ['কম / বেশি ও পথে কম মাল', 'Shortages', 'কম / বেশি ও পথে কম'], { icon: 'money', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true,
  kw: ['short', 'over', 'cash short', 'cash over', 'transit', 'carrier', 'claim', 'write off', 'lost in transit', 'shortage', 'কম', 'বেশি', 'ক্যাশ কম', 'পথে কম', 'বাহক', 'ক্ষতি', 'দাবি'],
  verbs: ['approve cash short', 'claim from carrier', 'write off lost goods'] }),
```
No Home tile, no bottom-bar slot. Optional `cnt` badge: open cash cases + open/claimed transit rows. Run `node tests/web/ia_test.js` and the nav tests after adding. Route name `shortages`. Put it in the `lang_en_test.js` file list if desired (all 67 English strings are Bangla-free, checked).

## 3. Added objects

Tables: `shortage_cash_cases`, `shortage_transit`, `shortage_transit_events` (append-only, RLS read by `_acct_view()` + place, no direct writes).
Chart: account `1240 Receivable from carrier` (falls back to 1245 if 1240 is used). Mappings: `cash_short` -> 5800, `transit_loss` -> 5100, `carrier_claim` -> 1240.
Triggers: `exceptions_cash_case` (on exceptions insert, flag `cash_short_over`), `stock_transfers_short` (on stock_transfers update to received with less received), audit triggers, event immutability.
Functions (owner/decider only unless noted): `cash_short_list` (view), `cash_short_decide(id, approve, note, employee, force)`, `cash_short_void`, `cash_short_backfill`, `transit_short_list` (view), `transit_short_set_cost`, `transit_short_claim`, `transit_short_recover`, `transit_short_writeoff`, `transit_short_backfill`, `b_post_pending`, `cust_advance_check` (read-only), internal `_b_docs`, `_b_cash_lines`, `_b_transit_lines`, `_b_transit_make`, `_b_transit_pick`, `_b_may_decide`, `_b_assert_balanced`, `_b_need_map`, `_b_check_date`.
Journal: short Dr 5800 / Cr 1110 (over reversed), on count date. Claim Dr 1240 / Cr 1310|1320|1330 by item type (sending place). Recover Dr cash|bank|mobile / Cr 1240. Write-off Dr 5100 / Cr inventory, or Cr 1240 after a claim (outstanding only). Unknown cost: nothing can be decided until the owner enters a cost.
G5: the posting already existed (phase40/52/79). B added only the read-only `cust_advance_check()` (journal 2300 vs cash moves per customer) and tests.
Backfill for pre-existing data is NOT automatic: owner runs `select cash_short_backfill(); select transit_short_backfill();` once, if wanted.

## 4. Open owner decisions, exposed as rules (Rules screen, module `books`)

| Rule key | English label | Choices | Safe default |
|---|---|---|---|
| `cash_short_post_on` | Post an approved cash short/over to the books | on/off | OFF (approved cases wait) |
| `cash_short_treatment` | How a cash SHORT is booked | `expense` (5800) / `staff_receivable` (1220, named employee) | expense (an over always goes to 5800) |
| `short_decider` | Who decides cash short and transit short cases | `owner` / `accounts_manager` | owner (nobody decides a count they made) |
| `transit_short_bearer` | Who bears goods short in transit | `ask` / `carrier` (claim first) / `shop` (no claim) | ask |

Q2 (monthly or daily cost) is covered by the posting date = count date plus the on/off switch; a monthly lump would be a different design and is not built.

## 5. Tests

`supabase/phase81_test.sql`: 110 pass / 0 fail on a fresh local Postgres (port 5546) built through phase79, phase81 pasted twice. `tests/web/shortages_test.js`: 35 assertions, 0 failures (Playwright, route injected by the test because ia.js is not edited). Not browser-tested on a real phone. phase80 was NOT in the test database (not present in this worktree); interplay with phase80 is UNTESTED.
