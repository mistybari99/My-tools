-- RPT-C3 planning history, loaded by phase465..468 tests AFTER rptc3_head.sql (needs phase 465 for the festival calendar). Test data only (test_* names).
-- Day numbers are days before today T (the same weekday every 7 days):
--   T-7  : 3 units (net 300)        T-14 : 5 units (net 500)   <- a festival day (left out of the ordinary average)        T-21 : 4 units (net 400)
--   T-6  : 2 units (net 200)        T-13 : 2 units + a quick sale 50 (net 250)        T-3  : 1 unit (net 100)
--   Festivals: test_fest_old = T-14 (no uplift), test_fest_new = T+1 (uplift 20%).
--   Hand-computed forecast for 3 days from today, window 28:
--     today  : same weekday, ordinary days T-7 and T-21 -> expected 350, low 300, high 400, n 2
--     T+1    : days T-6, T-13 -> expected 225 (low 200, high 250); with the 20% uplift 270
--     T+2    : no past day of that weekday -> no estimate (null)
--     totals : expected 575, low 500, high 650, with uplift 620, days without estimate 1
--     data   : first sale T-21 so the effective window is 21 days; 6 trading days -> coverage 28.6%; 5 ordinary + 1 festival
--   Item W1D-FG units (ordinary days only): today 3.5, T+1 2.0, T+2 none -> expected 5.5, low 5, high 6 (with uplift 5.9)
\set ON_ERROR_STOP on
create schema if not exists tt;
create table if not exists tt.hist (k text primary key, v text);
select not exists (select 1 from tt.hist where k = 'loaded') as h_fresh \gset
\if :h_fresh
insert into tt.hist values ('loaded', '1');
create or replace function tt.k_(p_k text) returns text language sql stable as $$ select v from tt.hist where k = p_k $$;
grant select on tt.hist to authenticated, anon; grant execute on function tt.k_(text) to authenticated, anon;
select id as hfg from items where code = 'W1D-FG' \gset
select stock_production_in(:'hfg'::uuid, 1, 200, now(), null, 'test history stock', gen_random_uuid(), 14) is not null as h_stock \gset
create or replace function tt.sell(p_day int, p_units int, p_extra numeric default 0) returns uuid language plpgsql as $$
declare fg uuid; sid uuid; d date := (now() at time zone 'Asia/Dhaka')::date - p_day; lines_ jsonb; pays jsonb; tot numeric := p_units * 100 + p_extra;
begin
  select id into fg from items where code = 'W1D-FG';
  lines_ := jsonb_build_array(jsonb_build_object('item_id', fg, 'qty', p_units, 'price', 100));
  if p_extra > 0 then lines_ := lines_ || jsonb_build_array(jsonb_build_object('amount', p_extra)); end if;
  sid := (record_sale2(gen_random_uuid(), 1, lines_, 0, jsonb_build_array(jsonb_build_object('mode', 'cash', 'amount', tot)), null, null, 'retail', null, p_extra > 0 and p_units = 0)->>'id')::uuid;
  perform set_config('session_replication_role', 'replica', true);
  update sales set sale_date = d, sold_at = d + time '12:00' where id = sid;
  update sale_payments set paid_at = d + time '12:00' where sale_id = sid;
  update stock_ledger set made_at = d + time '12:00' where ref_type = 'sale' and ref_id = sid::text;
  perform set_config('session_replication_role', 'origin', true);
  return sid;
end $$;
select tt.sell(7, 3) as h1 \gset
select tt.sell(14, 5) as h2 \gset
select tt.sell(21, 4) as h3 \gset
select tt.sell(6, 2) as h4 \gset
select tt.sell(13, 2, 50) as h5 \gset
select tt.sell(3, 1) as h6 \gset
select festival_save(null, jsonb_build_object('name_bn','test_fest_old','name_en','test_fest_old','start_date',tt.today()-14,'end_date',tt.today()-14)) ->> 'id' as fo \gset
select festival_save(null, jsonb_build_object('name_bn','test_fest_new','name_en','test_fest_new','start_date',tt.today()+1,'end_date',tt.today()+1,'uplift_pct','20')) ->> 'id' as fnw \gset
insert into tt.hist values ('fo', :'fo'), ('fnw', :'fnw'), ('h1', :'h1'), ('h2', :'h2'), ('h3', :'h3'), ('h4', :'h4'), ('h5', :'h5'), ('h6', :'h6');
\endif
\set ON_ERROR_STOP off
select 'history ready' as ready;
