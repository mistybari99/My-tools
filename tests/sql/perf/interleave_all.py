import re, sys, subprocess, statistics, json, os, time
src = open('bench.py').read()
head = src.split('results = []')[0]
sys.argv = ['bench.py', 'perf_final', 'x']
ns = {}
exec(head, ns)
CASES = ns['CASES']; run_once = ns['run_once']
dbs = ['perf_base', 'perf_final', 'perf_after']
ROUNDS = int(os.environ.get('ROUNDS', '5'))
SLOWFINAL = re.compile(r'(biz_daily 365d|_p27_pl|biz_items 365d|_cogs_lines72 365d)')      # final: ONE run, no warm-up (100+ s each)
SLOW2 = re.compile(r'(report_run item_sales 365d|report_run sales_summary|report_run category_sales|inventory_vs_gl|unmatched_forms\(\) 365d|biz_items 30d|biz_daily 30d)')   # final: warm-up + 2 runs
FILT = os.environ.get('ONLY')
OUT = os.environ.get('OUT', 'results_inter.json')
out = json.load(open(OUT)) if os.path.exists(OUT) else {}
def cpu_of(o):
    m = re.search(r'@@CPU ([0-9.]+)', o); return float(m.group(1)) if m else None
for c in CASES:
    if FILT and not re.search(FILT, c['name']): continue
    if c['name'] in out and not os.environ.get('REDO'): continue
    name = c['name']
    res = {d: [] for d in dbs}; cpu = {d: [] for d in dbs}
    rounds = 3 if SLOWFINAL.search(name) else ROUNDS
    for d in dbs:
        if d == 'perf_final' and SLOWFINAL.search(name): continue
        t, o = run_once(c, d)      # warm-up (also detects "function does not exist")
        res[d].append(None) if t is None else None
    ok = {d: True for d in dbs}
    # detect missing function in base quickly
    for d in dbs:
        if d == 'perf_final' and SLOWFINAL.search(name): continue
        t, o = run_once(c, d)
        if t is None: ok[d] = False
        else: res[d] = [t]; cpu[d] = [cpu_of(o)]
    for r in range(rounds - 1):
        for d in dbs:
            if not ok[d] or (d == 'perf_final' and SLOWFINAL.search(name)): continue
            if d == 'perf_final' and SLOW2.search(name) and r >= 1: continue
            t, o = run_once(c, d)
            if t is not None: res[d].append(t); cpu[d].append(cpu_of(o))
    if SLOWFINAL.search(name):
        t, o = run_once(c, 'perf_final')
        if t is not None: res['perf_final'] = [t]; cpu['perf_final'] = [cpu_of(o)]
    ld = open('/proc/loadavg').read().split()[0]
    rec = dict(group=c['group'], load=ld)
    for d in dbs:
        v = [x for x in res[d] if x is not None]
        if not v: continue
        cv = [x for x in cpu[d] if x is not None]
        rec[d] = dict(median=statistics.median(v), min=min(v), runs=v, cpu_median=(statistics.median(cv) if cv else None), cpu_runs=cpu[d])
    out[name] = rec
    print(name, 'load', ld, {d[5:]: (round(rec[d]['median'], 1), None if rec[d]['cpu_median'] is None else round(rec[d]['cpu_median'], 1)) for d in dbs if d in rec}, flush=True)
    json.dump(out, open(OUT, 'w'), indent=1)
print('INTER_DONE', flush=True)
