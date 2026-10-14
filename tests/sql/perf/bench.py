#!/usr/bin/env python3
"""EXPLAIN ANALYZE benchmark harness (psql subprocess). usage: bench.py <db> <label> [case-substring] [--runs N]
Every run is its own transaction that is rolled back. Median of N timed runs after 1 warm-up."""
import subprocess, sys, re, json, statistics, os

DB = sys.argv[1]; LABEL = sys.argv[2]
FILT = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith('--') else None
RUNS = 5
if '--runs' in sys.argv: RUNS = int(sys.argv[sys.argv.index('--runs') + 1])
OWN = '00000000-0000-0000-0000-0000000000a1'; SEL = '00000000-0000-0000-0000-0000000000a2'; MGR = '00000000-0000-0000-0000-0000000000a3'
IT = lambda n: f"(select id from seedtmp.it where i={n})"

def sale(items, loc=1, qty=2, extra_sel=''):
    ids = ','.join(str(i) for i in items)
    return (f"with l as (select jsonb_agg(jsonb_build_object('item_id', id,'qty',{qty})) j, sum({qty}*price) t from seedtmp.it where i in ({ids})) "
            f"select record_sale2(gen_random_uuid(),{loc},l.j,0,jsonb_build_array(jsonb_build_object('mode','cash','amount',l.t)),null,null,'retail',null,false) from l")

CASES = []
def case(name, sql, user=OWN, prelude='', final_only=False, profile=False, audit=False, group='', runs=None):
    CASES.append(dict(name=name, sql=sql, user=user, prelude=prelude, final_only=final_only, profile=profile, audit=audit, group=group, runs=runs))

# ---- POS paths
case('record_sale2: 3 lines, resale items, as salesperson', sale([300, 310, 320]), SEL, profile=True, audit=True, group='pos')
case('record_sale2: 3 lines, made items with open batches (FEFO loop)', sale([160, 170, 180]), SEL, profile=True, audit=True, group='pos')
case('record_sale2: 3 lines of big items (20k ledger rows each)', "with l as (select jsonb_agg(jsonb_build_object('item_id', id,'qty',2)) j from seedtmp.it where i in (1,2,3)) select record_sale2(gen_random_uuid(),1,l.j,0,jsonb_build_array(jsonb_build_object('mode','cash','amount',300)),null,null,'retail',null,false) from l", SEL,
     prelude="set local session_replication_role=replica; update items set sellable=true, sell_price=50, item_type='resale' where id in (select id from seedtmp.it where i in (1,2,3)); set local session_replication_role=origin;", group='pos')
case('record_sale2: 3 lines, as owner', sale([300, 310, 320]), OWN, group='pos')
case('record_sale2 + invoice_share_log92 + drawer_event_log (whole POS tail)',
     "with l as (select jsonb_agg(jsonb_build_object('item_id', id,'qty',2)) j, sum(2*price) t from seedtmp.it where i in (330,340,350)), "
     "r as (select record_sale2(gen_random_uuid(),1,l.j,0,jsonb_build_array(jsonb_build_object('mode','cash','amount',l.t)),null,null,'retail',null,false) x from l) "
     "select invoice_share_log92((x->>'id')::uuid,'print'), drawer_event_log(gen_random_uuid(),'auto_open',1,x->>'receipt',null,'cash') from r", SEL, final_only=True, group='pos')
case('invoice_share_log92 alone (existing sale)', "select invoice_share_log92((select id from sales where location_id=1 order by sold_at desc limit 1),'print')", SEL, final_only=True, group='pos')
case('drawer_event_log alone', "select drawer_event_log(gen_random_uuid(),'auto_open',1,'1',null,'cash')", SEL, final_only=True, group='pos')
case('is_shadow(entries, id) x 1000 (scalar calls)', "select count(*) from (select is_shadow('entries', md5(g::text)) from generate_series(1,1000) g) z", OWN, final_only=False, group='pos')
case('stock_post: sale_out on big item (20k rows)', f"select stock_post({IT(1)},1,-1,'sale_out','sale','bench',null,null,now(),null,null,'full',null,gen_random_uuid())", OWN, profile=True, audit=True, group='stock')
case('stock_post: purchase_in on big item', f"select stock_post({IT(2)},1,50,'purchase_in','purchase','bench',12.5,null,now(),null,null,'full',null,gen_random_uuid())", OWN, profile=True, audit=True, group='stock')
case('stock_post: sale_out finished item with open batches', f"select stock_post({IT(160)},1,-1,'sale_out','sale','bench',null,null,now(),null,null,'full',null,gen_random_uuid())", OWN, group='stock')
case('stock_post: production_in (item with batches)', f"select stock_post({IT(160)},1,10,'production_in','production','bench',12,null,now(),null,null,'none',null,gen_random_uuid())", OWN, group='stock')
case('production_post: 8 ingredients, 1 batch', "select production_post(1,(select id from recipes order by id limit 1),1,gen_random_uuid(),null,null)", OWN, profile=True, audit=True, group='stock')
case('production_post: 8 ingredients, 4 batches, loc 3', "select production_post(3,(select id from recipes order by id offset 4 limit 1),4,gen_random_uuid(),null,null)", OWN, group='stock')

# ---- accounting
case('_acct_docs(start): row count (500 pending + posted history)', "select count(*) from _acct_docs(_acct_start())", OWN, group='acct')
case('acct_post_pending(dry, 500)', "select acct_post_pending(true, 500) - 'preview'", OWN, group='acct')
case('acct_post_pending(real, 500 docs posted)', "select acct_post_pending(false, 500) - 'preview'", OWN, profile=True, group='acct')
case('acct_post_pending(real) idle: nothing pending', "select acct_post_pending(false, 500) - 'preview'", OWN,
     prelude="select acct_post_pending(false, 5000) is not null;", group='acct')
case('acct_autopost_tick() with 500 pending', "select acct_autopost_tick()", OWN, final_only=True, group='acct')
case('acct_autopost_tick() idle', "select acct_autopost_tick()", OWN, prelude="select acct_post_pending(false, 5000) is not null;", final_only=True, group='acct')
case('_cogs_lines72 365d (cost source of reports)', "select count(*), sum(led_cogs+fb_cogs) from _cogs_lines72(current_date-365, current_date, array[1,2,3])", OWN, group='acct', runs=1)

# ---- reports
case('biz_daily 30d', "select count(*), sum(revenue) from biz_daily(current_date-30, current_date, null)", OWN, group='report')
case('biz_daily 365d', "select count(*), sum(revenue) from biz_daily(current_date-365, current_date, null)", OWN, group='report', runs=3)
case('_p27_pl 365d', "select count(*), sum(o_net) from _p27_pl(current_date-365, current_date, array[1,2,3])", OWN, group='report', runs=3)
case('biz_items 30d', "select count(*), sum(revenue) from biz_items(current_date-30, current_date, null)", OWN, group='report')
case('biz_items 365d', "select count(*), sum(revenue) from biz_items(current_date-365, current_date, null)", OWN, group='report', runs=3)
case('items_with_cost()', "select count(*) from items_with_cost()", OWN, group='report')
case('report_run item_sales 365d group item (rpt_agg_sql + cost)', "select jsonb_array_length(report_run('item_sales', jsonb_build_object('from',(current_date-365)::text,'to',current_date::text,'locations',jsonb_build_array(1,2,3)), 'item') -> 'rows')", OWN, group='report')
case('report_run item_sales 30d group item', "select jsonb_array_length(report_run('item_sales', jsonb_build_object('from',(current_date-30)::text,'to',current_date::text,'locations',jsonb_build_array(1,2,3)), 'item') -> 'rows')", OWN, group='report')
case('report_run sales_summary 365d group day', "select report_run('sales_summary', jsonb_build_object('from',(current_date-365)::text,'to',current_date::text,'locations',jsonb_build_array(1,2,3)), 'day') -> 'totals'", OWN, group='report')
case('report_run category_sales 365d', "select report_run('category_sales', jsonb_build_object('from',(current_date-365)::text,'to',current_date::text,'locations',jsonb_build_array(1,2,3)), 'category') -> 'totals'", OWN, group='report')
case('inventory_vs_gl(today)', "select inventory_vs_gl(current_date, null)", OWN, final_only=True, group='report')
case('stock_reconcile(dry run)', "select count(*) from stock_reconcile(false)", OWN, group='report')
case('urgent_alerts()', "select jsonb_array_length(urgent_alerts(null))", OWN, group='report')

# ---- new in the 72-101 range (no baseline function)
case('inbox_list(null,null,50)', "select jsonb_array_length(inbox_list(null,null,50))", OWN, final_only=True, group='new')
case('inbox_list(1,new,50) as manager', "select jsonb_array_length(inbox_list(1,'new',50))", MGR, final_only=True, group='new')
case('setup_recommendations()', "select jsonb_array_length(setup_recommendations()->'items')", OWN, final_only=True, group='new')
case('my_option_views() as owner', "select jsonb_array_length(my_option_views())", OWN, final_only=True, group='new')
case('my_option_views() as salesperson', "select jsonb_array_length(my_option_views())", SEL, final_only=True, group='new')
case('option_views_for_user(salesperson)', f"select option_views_for_user('{SEL}')", OWN, final_only=True, group='new')
case('permission_recommendations(salesperson)', f"select permission_recommendations('{SEL}')", OWN, final_only=True, group='new')
case('unmatched_forms() default 30d', "select unmatched_forms()->>'lines_checked'", OWN, final_only=True, group='new')
case('unmatched_forms() 365d', "select unmatched_forms(current_date-365, current_date, null)->>'lines_checked'", OWN, final_only=True, group='new')
case('landed_preview: 1 bill, freight', "select landed_preview(array[(select id from purchase_bills where location_id=1 order by bill_date desc limit 1)], '[{\"charge_type\":\"freight\",\"amount\":100}]'::jsonb)", OWN, final_only=True, group='new')
case('landed_preview: 25 bills', "select landed_preview((select array_agg(id) from (select id from purchase_bills where location_id=1 order by bill_date desc limit 25) z), '[{\"charge_type\":\"freight\",\"amount\":900}]'::jsonb)", OWN, final_only=True, group='new')


def run_once(c, db):
    pre = f"""\\set ON_ERROR_STOP on
begin;
set local track_functions = 'all';
select set_config('request.jwt.claim.sub', '{c['user']}', true) is not null as _x \\gset
{c['prelude']}
select coalesce(max(id),0) as mx from audit_log \\gset
select split_part(pg_read_file('/proc/self/schedstat'),' ',1)::bigint as c0 \\gset
explain (analyze, timing off) {c['sql']};
select '@@CPU ' || round((split_part(pg_read_file('/proc/self/schedstat'),' ',1)::bigint - :c0)/1e6, 2);
"""
    if c['profile']:
        pre += "select '@@FN ' || funcname || ' calls=' || calls || ' total=' || round(total_time::numeric,2) || ' self=' || round(self_time::numeric,2) from pg_stat_xact_user_functions order by self_time desc limit 14;\n"
    if c['audit']:
        pre += "select '@@AUD ' || table_name || ':' || action || ' n=' || count(*) || ' bytes=' || sum(pg_column_size(detail)) from audit_log where id > :mx group by table_name, action order by 1;\n"
        pre += "select '@@AUDTOT ' || count(*) || ' ' || coalesce(sum(pg_column_size(detail)),0) from audit_log where id > :mx;\n"
    pre += "rollback;\n"
    p = subprocess.run(['psql', '-h', '/tmp', '-p', '5544', '-U', 'postgres', '-d', db, '-qAt', '-v', 'ON_ERROR_STOP=1'], input=pre, capture_output=True, text=True)
    out = p.stdout + p.stderr
    m = re.search(r'Execution Time: ([0-9.]+) ms', out)
    if not m: return None, out
    return float(m.group(1)), out

results = []
has = {}
for c in CASES:
    if FILT and FILT.lower() not in c['name'].lower(): continue
    if os.environ.get('EXCL') and re.search(os.environ['EXCL'], c['name']): continue
    t, out = run_once(c, DB)   # warm-up
    if t is None:
        err = [l for l in out.splitlines() if 'ERROR' in l or 'does not exist' in l]
        print(f"{c['name']}: FAIL {err[:1]}", flush=True)
        results.append(dict(name=c['name'], group=c['group'], error=(err[:1] or [out[-200:]])[0], runs=[]))
        continue
    ts = []; last = out
    for _ in range(c['runs'] or RUNS):
        t, last = run_once(c, DB)
        ts.append(t)
    med = statistics.median(ts)
    r = dict(name=c['name'], group=c['group'], median=med, runs=ts)
    fn = [l[5:] for l in last.splitlines() if l.startswith('@@FN ')]
    aud = [l[6:] for l in last.splitlines() if l.startswith('@@AUD ')]
    tot = [l[9:] for l in last.splitlines() if l.startswith('@@AUDTOT ')]
    if fn: r['fn'] = fn
    if aud: r['aud'] = aud
    if tot: r['audtot'] = tot[0]
    results.append(r)
    print(f"{c['name']}: median {med:.1f} ms  runs={[round(x,1) for x in ts]}", flush=True)
json.dump(results, open(f'results_{LABEL}.json', 'w'), indent=1)
