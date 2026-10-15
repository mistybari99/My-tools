#!/usr/bin/env python3
"""Shows what each phase110 index buys: runs the target statement with the index, then DROPs the index inside a transaction (rolled back) and runs it again.
usage: index_effect.py <seeded-db-after-phase110> [<audit-db with ~2M audit_log rows>]     (scratch Postgres 16, socket /tmp port 5544)
The audit_log targets need a big audit_log: pass a second DB (seed_audit.sql builds one); without it they are skipped."""
import subprocess, sys, re
DB = sys.argv[1]; AUD = sys.argv[2] if len(sys.argv) > 2 else None
OWN = "(select user_id from user_roles where role_code='owner' order by user_id limit 1)"
T = [  # (index, db, statement)
 ('stock_ledger_refid_idx', DB, "select count(*) from _cogs_lines72(current_date-30, current_date, array[1,2,3])"),
 ('stock_ledger_item_loc_reason_idx', DB, "select unmatched_forms(current_date-365, current_date, null)->>'lines_checked'"),
 ('production_runs_idtext_idx', DB, "select inventory_vs_gl(current_date, null)"),
 ('purchase_bills_idtext_idx', DB, "select inventory_vs_gl(current_date, null)"),
 ('stock_ledger_reason_made_idx', DB, "select count(*) from _acct_stock_moves85(_acct_start())"),
 ('stock_ledger_lastcost_idx', DB, "select count(*) from _item_cost_eff88()"),
 ('audit_log_tbl_rec_id_idx', AUD, "select id, action, detail from audit_log where table_name = 'sales' and record_id = (select record_id from audit_log where table_name='sales' order by id desc offset 1000 limit 1) order by id desc limit 50"),
 ('audit_log_view_at_idx', AUD, "select pii_exposure_report94()"),
]
def run(db, drop, stmt):
    sql = f"begin;\nselect set_config('request.jwt.claim.sub', {OWN}::text, true) is not null as _x \\gset\n"
    if drop: sql += f"drop index public.{drop};\n"
    sql += f"explain (analyze, timing off) {stmt};\nrollback;\n"
    best = None; plan = ''
    for _ in range(3):
        o = subprocess.run(['psql','-h','/tmp','-p','5544','-U','postgres','-d',db,'-qAt','-v','ON_ERROR_STOP=1'], input=sql, capture_output=True, text=True).stdout
        m = re.search(r'Execution Time: ([0-9.]+) ms', o)
        if m: best = min(best, float(m.group(1))) if best else float(m.group(1))
        if drop and best and best > 20000: break
    return best
print(f"{'index':36s} {'with ms':>10s} {'without ms':>11s}  ratio")
for ix, db, stmt in T:
    if db is None: print(f"{ix:36s} (skipped: no audit db)"); continue
    a = run(db, None, stmt); b = run(db, ix, stmt)
    print(f"{ix:36s} {a if a is None else round(a,1):>10} {b if b is None else round(b,1):>11}  {'' if not a or not b else round(b/a,1)}x", flush=True)
