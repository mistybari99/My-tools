#!/usr/bin/env python3
"""Time budget + before/after table on the seeded databases (scratch Postgres 16, socket /tmp port 5544).
usage:  budget.py <db-after> [--pre <db-before-phase110>] [--base <db-pre-phase72>] [--runs 5] [--only <regex>] [--out budget.json]
Every number is the median of --runs EXPLAIN (ANALYZE, TIMING OFF) executions, each in a transaction that is rolled back (after one warm-up).
'cpu' is the backend CPU time (/proc/self/schedstat), 'wall' the executor time; on a shared box read the CPU column.
Budgets (phase110): biz_daily / biz_items 30 days <= 1 s; every year report <= 5 s; record_sale2 (POS) <= 60 ms; stock paths <= 300 ms.
exit code 1 when a budget is missed (on the --after db)."""
import re, sys, os, json, statistics, subprocess
a = sys.argv[1:]
def opt(n, d=None):
    return a[a.index(n) + 1] if n in a else d
AFTER = a[0]; PRE = opt('--pre'); BASE = opt('--base'); RUNS = int(opt('--runs', '5')); ONLY = opt('--only'); OUT = opt('--out', 'budget.json')
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'bench.py')).read()
head = src.split('results = []')[0]
sys.argv = ['bench.py', AFTER, 'x']
ns = {}
exec(head, ns)
CASES = ns['CASES']; run_once = ns['run_once']
def cpu_of(o):
    m = re.search(r'@@CPU ([0-9.]+)', o); return float(m.group(1)) if m else None
BUDGET = [  # (name regex, limit ms)
    (r'^biz_daily 30d$', 1000), (r'^biz_items 30d$', 1000),
    (r'^(biz_daily 365d|_p27_pl 365d|biz_items 365d|_cogs_lines72 365d)$', 5000),
    (r'^report_run (item_sales 365d|sales_summary 365d|category_sales 365d)', 5000),
    (r'^(inventory_vs_gl|unmatched_forms\(\) 365d)', 3000),
    (r'^record_sale2: ', 60), (r'^(stock_post|production_post)', 300)]
def limit(name):
    for rx, ms in BUDGET:
        if re.search(rx, name): return ms
def measure(c, db, runs):
    w = []; cp = []
    if runs > 1:
        t, o = run_once(c, db)                   # warm-up (also detects a missing function)
        if t is None: return None
    for _ in range(runs):
        t, o = run_once(c, db)
        if t is None: return None
        w.append(t); cp.append(cpu_of(o))
    cp = [x for x in cp if x is not None]
    return dict(wall=statistics.median(w), cpu=statistics.median(cp) if cp else None, runs=w)
rows = []; bad = 0
dbs = [('after', AFTER)] + ([('pre', PRE)] if PRE else []) + ([('base', BASE)] if BASE else [])
print(f"{'case':66s} " + ' '.join(f'{k+" cpu":>11s}' for k, _ in dbs) + f" {'wall after':>11s} {'budget':>8s}  verdict")
for c in CASES:
    if ONLY and not re.search(ONLY, c['name']): continue
    res = {}
    for k, db in dbs:
        if k == 'base' and c['final_only']: continue
        n = 1 if (k == 'pre' and re.search(r'365d|biz_(daily|items) 30d|report_run|inventory_vs_gl|unmatched_forms\(\) 365d', c['name'])) else RUNS   # the old slow cases: one run is enough
        res[k] = measure(c, db, n)
    af = res.get('after')
    lim = limit(c['name']); v = ''
    if af and lim:
        v = 'ok' if af['wall'] <= lim else 'OVER BUDGET'
        if v != 'ok': bad += 1
    f = lambda r: '-' if not r or r['cpu'] is None else f"{r['cpu']:.1f}"
    print(f"{c['name'][:66]:66s} " + ' '.join(f"{f(res.get(k)):>11s}" for k, _ in dbs) + f" {'-' if not af else format(af['wall'], '.1f'):>11s} {lim or '':>8}  {v}", flush=True)
    rows.append(dict(name=c['name'], group=c['group'], budget_ms=lim, **{k: res.get(k) for k, _ in dbs}))
json.dump(rows, open(OUT, 'w'), indent=1)
print('BUDGET', 'FAILED' if bad else 'OK', f'({bad} over)')
sys.exit(1 if bad else 0)
