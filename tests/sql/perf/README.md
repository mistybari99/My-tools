# tests/sql/perf - performance seed, benches and result-equality (phase110)

Everything here runs on a **scratch** Postgres 16 (socket `/tmp`, port 5544, user `postgres`). Nothing touches a live database. Test data only.

| file | what |
|---|---|
| `seed.sql` | the synthetic shop of the independent performance review: 500 items, 3 places, 20,500 sales x 3 lines over 365 days, 184k stock-ledger rows (5 big raw items with 20k rows each), 5,000 purchase bills, 3,000 production runs x 8 ingredients, journal posted by the real `acct_post_pending` (accounting start 140 days back), 3,000 stock-issue forms. Triggers are bypassed (replica role) so it loads in about 20 s. |
| `seed_post.sql` | posts the journal for the seed (`acct_post_pending`, 5 rounds) |
| `seed_pending.sql` | 500 more sales that stay UNPOSTED (autopost tick and batch tests) |
| `seed_inbox.sql` | 30,000 inbox messages (phase 99+ only; skip it on a pre-phase-72 database) |
| `seed_facts.sql` | `report_fact_rebuild()` (61.5k report fact rows, the seed bypasses the trigger) |
| `bench.py` | EXPLAIN (ANALYZE, TIMING OFF) harness of 50 cases (POS, stock, accounting, reports, new screens); `bench.py <db> <label> [filter] [--runs N]` |
| `interleave_all.py` | the review's runner: same cases on 3 databases, rounds interleaved (edit the `dbs` list) |
| `budget.py` | the phase110 time budget: median of 5, CPU and wall, optional before-phase110 and pre-phase-72 columns, exit 1 over budget |
| `equality.sql` / `equality.sh` | **result equality**: md5 of every result of biz_daily, biz_items, _p27_pl, _cogs_lines72, items_with_cost, _item_cost_eff88, report_run (6 reports, rows / totals / columns), inventory_vs_gl, unmatched_forms, _acct_docs, _acct_stock_moves85, acct_post_pending (dry), inbox_list, the journal and trial balance after a real post - in all three cost modes. Run on a database before phase110 and on a clone after it; the EQ lines must be identical. |
| `index_effect.py` | what each index buys: the target statement with the index, then with the index dropped inside a rolled-back transaction |
| `seed_c4.sql` | (step C4) scales the seed to the owner's size: 1,369 items / 229 categories, +30,000 sales over 2 years (before the accounting start), +3,000 production runs, 5,963 transfers (returns, cancelled, in transit, short), give-backs, 15,000 quick expenses, card settlements, recipe standards, monthly cost pools. Run it after seed.sql + seed_post.sql (+ seed_pending / seed_inbox / seed_facts); works on a build with or without phases 112..118. |
| `bench120.py` | (step C4) time + md5 of the phase112..118 reports for 1 day / 1 month / 1 year: `python3 bench120.py <db> <label> [filter]` |
| `equality120.sh` | (step C4) md5 of stock_recon_statement / factory_branch_statement / stock_sales_unmatched / `_rc118_buckets` / `_rc118_gap` over a grid of periods, places, items and categories; run on a db before phase120 and on a clone after it, `diff` must be empty |
| `ref_proposed_indexes.sql`, `ref_proposed_patches.sql`, `ref_results_review.json` | the review's proposals and raw numbers (reference only; phase110.sql is the shipped version) |

## Reproduce (about 15 minutes, most of it the old slow reports)

```bash
cd <repo root>
ORDER="phase8 phase9 ... phase108"   # the canonical order of docs/PASTE_ORDER.md up to phase108 WITHOUT phase110 (bash tests/sql/run_all_sql.sh prints it as 'paste order: ...')
bash tests/sql/final_build.sh perf_pre "$ORDER"                      # BEFORE: everything except phase110
cd tests/sql/perf
for f in seed.sql seed_post.sql seed_pending.sql seed_inbox.sql seed_facts.sql; do psql -h /tmp -p 5544 -U postgres -d perf_pre -q -f $f; done
psql -h /tmp -p 5544 -U postgres -qc "create database perf_post template perf_pre"
psql -h /tmp -p 5544 -U postgres -d perf_post -v ON_ERROR_STOP=1 -qf ../../../supabase/phase110.sql      # AFTER

bash equality.sh perf_pre eq_pre.txt      # slow: the old year reports take 150 s each
bash equality.sh perf_post eq_post.txt    # 40 s
diff eq_pre.txt eq_post.txt && echo IDENTICAL

python3 budget.py perf_post --pre perf_pre --base perf_b71            # perf_b71 = the same seed on a build up to phase71 (no seed_inbox.sql)
python3 index_effect.py perf_post <a-db-with-2M-audit_log-rows>       # audit_log targets are skipped without the second argument
```

`supabase/phase110_test.sql` (44+ checks, fresh database) compares every patched function with its previous body on small fixtures, in all three `report_cost_source` modes, and pastes phase110 three times.

## Notes

- The review box was loaded (load average 20-35): read the CPU columns, not the wall times. Small POS numbers carry about +-20 % noise.
- `equality.sql` runs everything inside rolled-back transactions; it uses the date of the last sale as "today", so it also works on the e2e scenario database (`tests/sql/e2e/run.sh`).
- 2 M `audit_log` rows were built in a separate copy by the review (`aud_fill.sql`, not kept): the two audit indexes are only measurable at that size.
