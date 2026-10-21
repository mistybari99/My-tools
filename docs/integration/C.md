# Integration note: builder C (phase82) - salary accrual, Monthly Close, partner profit share

Files: `supabase/phase82.sql`, `supabase/phase82_test.sql` (101 checks, all pass on a local DB built through phase79), `web/monthclose.js`, `tests/web/monthclose_test.js`.
Paste order: after phase79 (and after phase80/81 if present). Paste-twice safe. Nothing existing was edited.
Until hooks 1-3 are installed the accrual stays dormant (`_c_hooks_ok()` is false, every run stays cash basis), so a half-integrated database cannot count salary twice.

## 1. Hooks in shared functions (mechanical text edits)

`_acct_docs(date)` (latest body: phase79 or later):
1. At the very end, before the closing `end $function$;`, add one line: `return query select * from public._c_docs(p_start);`
2. In the `payroll_payment` block (bos52), replace every `public.is_shadow('payroll_runs', p.run_id::text)` with `public._c_run_skip(p.run_id)` (3 places). `_c_run_skip` = shadow OR accrual basis, so an accrual run is never also posted the old way.
3. In the same block, replace `public._acct_paykey(p.mode), 'c', p.amount` with `public._c_salary_paykey(p.mode), 'c', p.amount` (1 place). This makes the salary source setting apply to cash-basis payments too.

The exact edits are executed by the `T2` block of `phase82_test.sql`; if the integrated body differs, re-run that test.

`_p27_pl(d1,d2,locs)` (P&L salary column `o_sal`), optional but needed for the P&L to see app payroll:
4. In CTE `sa`, add `and not public.is_shadow('entries', e.id::text)` to the 21-1 filter, and add the app-run salary from `public.c_salary_by_month(d1, d2, locs)` (returns `m, loc, amt` = net pay + advance recovery of approved/paid, non-shadow runs) to the monthly sum. Skip it if `_p27_pl` already reads the journal salary account.

No hook is needed in `acct_post_pending`: it loops `_acct_docs`. `c_post_pending()` is a standalone poster for the same sources (owner / accounts_manage), used by the Monthly Close screen.
Day book and `biz_daily`: no change. `biz_daily` (phase72) is sales and COGS only, so the daily profit never carried salary. `c_daily_profit()` is the daily view that keeps it out on purpose.

## 2. web/ia.js registration (and index.html)

Add `<script src="monthclose.js"></script>` after `parallel.js`, and one line in `web/ia.js`:

```js
rec('monthclose', 'acc', ['মাস শেষের হিসাব', 'Monthly Close', 'Monthly Close (মাস শেষ)'], { icon: 'book', ok: (c) => c.own || c.GF.accounts_manage === true, home: { acc: 11 },
  kw: ['month close', 'monthly close', 'month end', 'salary accrual', 'accrued salary', 'payroll accrual', 'partner share', 'profit split', 'close the month', 'মাস শেষ', 'মাসিক ক্লোজ', 'বেতন জমা', 'মাসের হিসাব', 'অংশীদারের ভাগ'],
  verbs: ['close the month', 'মাস বন্ধ করুন'] }),
```
Group `acc`; `home: { acc: 11 }` is the next free slot (4, 5, 7-10 are used). Run `ia_test`, nav, nav2, control, favsync, settings2 after adding (not run here: ia.js is not edited by this branch).

## 3. Added objects

Tables: `c_month_close_log` (append-only close / reopen trail, read for accounts_manage).
Accounts: 2600 Partner profit payable (credit), 3400 Partner profit share (appropriation, debit equity); code +10 if taken (found by name).
Mappings: `salary_accrued` (2200), `partner_payable` (2600), `partner_ps_share|royalty|fee|return|payback|guarantee` (3400; the owner may re-point royalty / fee to an expense account).
Journal sources (via `_c_docs`): `payroll_accrual` (id `run:place`), `payroll_pay_accr` (payment id), `partner_settle` (settlement id), `partner_settle_pay` (payment id).
Browser functions: `c_post_pending`, `c_month_close_preview`, `c_month_close`, `c_month_reopen`, `c_month_closes`, `c_daily_profit`, `c_partner_month_split`, `c_partner_share_report`, `c_partner_payable_check`, `c_salary_pay_default`.
Internal (closed): `_c_docs`, `_c_run_basis`, `_c_accrual_covers`, `_c_run_skip`, `_c_salary_paykey`, `_c_settle_basis`, `_c_hooks_ok`, `_c_accrual_from`, `_c_accrual_lines`, `_c_close_state`, `_c_split`, `_c_me`, `c_salary_by_month`.

Postings: accrual `Dr 5200 (net + advance recovery) / Cr 2200 (net) / Cr 1220 (recovery)`, dated month end (not after today), one entry per run and place. Payment `Dr 2200 / Cr cash|bKash|bank`. Settlement approved `Dr 3400 / Cr 2600`; settlement payment `Dr 2600 / Cr cash|bank|wallet`. Every entry passes `_acct_write` (Dr = Cr or refused).

## 4. Owner decisions, exposed as settings (table `rules`; the owner edits them in Monthly Close)

| Rule | Safe default | Meaning |
|---|---|---|
| `salary_pay_source` | `by_payment` | Salary is paid from: by_payment (mode chosen when paying) / cash / mobile (bKash) / bank. Q1. |
| `payroll_accrual_on` | off | Off = salary is a cost on the pay day as today. On = monthly accrual. |
| `payroll_accrual_from` | blank | First month of accrual. Blank = nothing accrued even if on (no invented date). |
| `salary_in_daily_off` | on | Daily profit leaves salary out. Differs from the plan text (default off) because the owner said salary is not a daily expense. |
| `partner_settlement_post_on` | off | Off = settlements post nothing, as today. |
| `partner_accrue_at` | `approval` | When partner profit is booked: approval (debt booked when approved) or payment (booked only when paid). Q4. A settlement keeps the basis it was first posted with. |

Behaviours to know: a run keeps its basis once anything is posted (switching a rule never reverses posted entries); a reversal is dated the void day, so a run voided after month end shows a difference that the Monthly Close preview flags (`salary_journal_differs_from_runs`); the close does not lock the period (set rule `period_closed_until` separately); `c_partner_month_split` is a preview by the agreements' share percent, the settlement is what posts.
