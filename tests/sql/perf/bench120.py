#!/usr/bin/env python3
# bench120.py <db> <label> [name-filter]
# Time + md5 of the heavy functions of phases 112..118 (stock_recon_statement, factory_branch_statement, stock_sales_unmatched, net_profit_report, profit_truth112,
# production_variance116, production_cost_queue116, pool_vs_gl117, overhead_trueup117, customer_dues_net113) for 1 day / 1 month / 1 year, as the owner.
# Each case runs 4 times in one session; the first run is the warm-up, min and median of the other 3 are printed with the first 10 characters of the md5 of the result
# (the md5 is how before/after equality is read off). Result file: $BENCH_OUT/bench_<label>.json (default /tmp). Needs the seeds seed.sql + seed_post.sql + seed_c4.sql.
# usage: python3 bench120.py perf_c4 before ; python3 bench120.py perf_c4_after after
import subprocess, sys, re, json, os
db, label = sys.argv[1], sys.argv[2]; flt = sys.argv[3] if len(sys.argv) > 3 else ''
OWN = '00000000-0000-0000-0000-0000000000a1'
rng = {'1d': ("current_date-1", "current_date-1"), '1m': ("current_date-30", "current_date-1"), '1y': ("current_date-365", "current_date-1")}
mon = {'1d': "date_trunc('month',current_date)::date", '1m': "date_trunc('month',current_date-30)::date", '1y': "date_trunc('month',current_date-365)::date"}
cases = []
for r, (F, T) in rng.items():
    cases += [
     ('stock_recon_statement', r, f"stock_recon_statement({F},{T},null,null,null,2000)"),
     ('stock_recon_statement_loc1', r, f"stock_recon_statement({F},{T},1,null,null,2000)"),
     ('stock_recon_statement_cat', r, f"stock_recon_statement({F},{T},null,null,'cat7',2000)"),
     ('stock_sales_unmatched', r, f"stock_sales_unmatched({F},{T})"),
     ('factory_branch_statement', r, f"factory_branch_statement({F},{T},null,null,null,2000)"),
     ('net_profit_report', r, f"net_profit_report({F},{T})"),
     ('profit_truth112', r, f"profit_truth112({F},{T})"),
     ('production_variance116', r, f"production_variance116(1,{F},{T},true)"),
     ('production_cost_queue116', r, f"production_cost_queue116(1,{F},{T})"),
     ('pool_vs_gl117', r, f"pool_vs_gl117(1,{mon[r]})"),
     ('overhead_trueup117', r, f"overhead_trueup117(1,{mon[r]})"),
    ]
cases += [('customer_dues_net113', '-', "customer_dues_net113()"), ('customer_dues(old)', '-', "customer_dues()")]
out = {}
for name, r, call in cases:
    if flt and flt not in name: continue
    sql = f"select set_config('request.jwt.claim.sub','{OWN}',false) is not null;\n\\timing on\n" + (f"select md5(({call})::text);\n" * 4 if name.startswith(('customer_dues_net', 'customer_dues(old')) is False else "")
    if name.startswith('customer_dues'):
        q = 'customer_dues_net113()' if 'net' in name else 'customer_dues()'
        sql = f"select set_config('request.jwt.claim.sub','{OWN}',false) is not null;\n\\timing on\n" + (f"select md5(string_agg(x::text, '|' order by x::text)) from {q} x;\n" * 4)
    p = subprocess.run(['psql','-h','/tmp','-p','5544','-U','postgres','-d',db,'-X','-At','-q'], input=sql, capture_output=True, text=True)
    txt = p.stdout + p.stderr
    times = [float(x) for x in re.findall(r'Time: ([0-9.]+) ms', txt)][-3:]  # drop first (warm-up)
    md5s = re.findall(r'^([0-9a-f]{32})$', txt, re.M)
    err = re.findall(r'ERROR:.*', txt)
    res = dict(min=min(times) if times else None, med=sorted(times)[len(times)//2] if times else None, md5=md5s[-1][:10] if md5s else None, err=err[0][:80] if err else None)
    out[f'{name}|{r}'] = res
    print(f"{label:6} {name:30} {r:3} min={res['min']} med={res['med']} md5={res['md5']} {res['err'] or ''}", flush=True)
json.dump(out, open(os.path.join(os.environ.get('BENCH_OUT', '/tmp'), f'bench_{label}.json'), 'w'), indent=1)
