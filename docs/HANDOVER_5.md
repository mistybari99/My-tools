# HANDOVER 5 - P1 done (needs owner OK), read first
Branch ccr-9ef9353a-q2wsec (PR #2 draft). Read HANDOVER_4 (scope, owner style) and ERP_AUDIT_ROADMAP.md §11-13 first.

## What P1 built (SQL pasted by owner in this order, paste-twice safe): phase48 -> 49 -> 50 -> 51 (after phase47)
- **48 engine**: `path_domains` (7 places where two paths exist), `path_switch` (owner: path A open/locked, path B open/locked, primary a|b|first; per place or all places),
  `shadow_links` (append-only trail), `path_guard / path_winner / is_shadow / shadow_link_add`, owner `path_switch_set / path_switches`, `shadow_report / shadow_count_once_check`.
  `first` is allowed only for payroll, expense, owner_money. Stock/production: a or b. While rule `forms_post_to_ledger` is ON the stock default flips to b (today's behaviour kept).
- **49 reports (read only)**: `daybook_vs_journal(from,to,loc)`, `dup_suspects(from,to)` (D1 payroll, D2 stock, D3 production, D4 owner money, D8 handover).
- **50 payroll + expense**: app run is primary (default), 02-2 becomes a locked shadow (not counted in day book; reports still read the form because the app run is not in P&L/salary reports yet).
  Voided run releases the form. Quick expense (`quick_expenses`, `quick_expense_add/void/day/close_day`): counts at once in day book, journal, P&L, expense trend; one click at day end makes a draft 10-2 = locked shadow.
  Functions re-created with `bos50` marks: _daybook_lines, _daybook_skipped, _daybook_lines23, _acct_docs, _p27_pl, _r3q_e2_expense_trend.
- **51 stock/production/owner money**: screen primary -> form lines skipped `covered_by_screen`; form primary -> screen refused; locked path refuses new records.
  `owner_money_link(capital, cash_move)` pairs partner capital with owner top-up/draw (cash move still counted until P2 posts partner capital). `bos51` marks in entry_post_ledger, _elp_post_line.
- **UI**: `#/paths` (owner: switches, reports) and `#/quickexp` (day-book quick expense, day-end 10-2) in web/paths.js.
- **Kit**: tools/kit_match.py -> docs/KIT_MATCH.md (suspect list, ~500 paper-only / ~700 app-only labels; needs human review; 0-1 = location settings screens).

## Tests
SQL: phase48 54, phase49 16, phase50 45, phase51 23 pass. Older suites 10,13,20-28,40,42,44-47 unchanged vs baseline (known baseline fails: 10 T12, 21, 22).
Local DB: `su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg5544 -o '-p 5544 -k /tmp' -l /tmp/pg5544.log start"` (initdb first; create roles anon/authenticated/service_role).

## Hazards / not done
- Re-pasting an OLD phase (13, 20, 23, 27, 40, 42) overwrites the patched functions: paste phase50 + phase51 again afterwards.
- Not covered by the shadow filter (still read all 10-2 / 02-2): _r3q_e3_weak_control, biz_suggest, report_run2_core, salary_report, _r3q_t3_payroll, _p27_pl salary part (intended: app payroll is not there yet).
- Payroll/partner capital/advances still have no journal source (P2 gap #6). Web: new screens not browser-tested on a phone; web tests for paths.js not written.
- setup-sql.html (public repo) not rebuilt for 48-51.
- P2 next (accounts + attendance), then P3. Ask owner before each part.

## P2 / P3 (built by 6 agents, integrated by lead) - paste order after phase51: 52, 53, 54, 60, 61, 62
| phase | gaps | report | route |
|---|---|---|---|
| 52 | #6 journal auto-post: payroll payments, advances, partner capital (owner money posts once) | docs/briefs_p2p3/p2a_REPORT.md | accounts screen |
| 53 | #1-#5 bank reconcile, year close, VAT report, assets+depreciation, budgets | p2b_REPORT.md | #/finance2 |
| 54 | #29 attendance counted once + self punch + mark others, #20 equation check (#19 already existed in entry.js) | p2c_REPORT.md | #/attend2, #/eqcheck |
| 60 | #7-#10 reorder, wastage by reason, batch/expiry, QC | p3a_REPORT.md | #/stockx |
| 61 | #11-#14 online orders, 20-x link, benefits, BI export | p3b_REPORT.md | #/onlineorders #/saleforms #/benefitsx #/biexport |
| 62 | #21-#23 SMS queue, payment recon, accounting export; #30 assistant = owner + assistant_use grant only | p3c_REPORT.md | #/integrations |
SQL tests (fresh DB through 62): 48:54 49:16 50:45 51:23 52:33 53:112 54:84 60:62 61:114 62:74, all pass. phase47_test 2 old asserts (role list / head management open the assistant) now fail ON PURPOSE (phase62 tightens #30).
Open: #16 PIN postponed; #17 restore drill, #18 2FA not built; none of the web pages seen on a real phone; setup-sql.html not rebuilt; owner must decide the notes in each report ("Not done").
