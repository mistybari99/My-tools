-- E2E scaffold. usage: psql -v mode=rec|def -f 00_common.sql ...  (all files run in ONE psql session via run.sh)
\set ON_ERROR_STOP off
\set QUIET on
\set o  '00000000-0000-0000-0000-000000000001'
\set bu '00000000-0000-0000-0000-000000000002'
\set fm '00000000-0000-0000-0000-000000000003'
\set sp '00000000-0000-0000-0000-000000000004'
\set sk '00000000-0000-0000-0000-000000000005'
\set bt '00000000-0000-0000-0000-000000000006'
\set rv '00000000-0000-0000-0000-000000000007'
\set ap '00000000-0000-0000-0000-000000000008'
\set ac '00000000-0000-0000-0000-000000000009'
create schema if not exists tt;
drop table if exists tt.ea; create table tt.ea (n serial, step text, expected text, actual text, ok boolean, note text);
create or replace function tt.as(p_sub text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- numeric expected vs actual (tolerance default 0.005)
create or replace function tt.eq(p_step text, p_exp numeric, p_act numeric, p_tol numeric default 0.005, p_note text default null) returns void language plpgsql as $$
declare ok boolean := p_act is not null and p_exp is not null and abs(p_exp - p_act) <= p_tol;
begin if p_exp is null and p_act is null then ok := true; end if;
  insert into tt.ea (step, expected, actual, ok, note) values (p_step, p_exp::text, p_act::text, ok, p_note); raise notice '% % exp=% act=%', case when ok then 'PASS' else 'FAIL' end, p_step, p_exp, p_act; end $$;
create or replace function tt.is(p_step text, p_exp text, p_act text, p_note text default null) returns void language plpgsql as $$
declare ok boolean := p_exp is not distinct from p_act;
begin insert into tt.ea (step, expected, actual, ok, note) values (p_step, p_exp, p_act, ok, p_note); raise notice '% % exp=% act=%', case when ok then 'PASS' else 'FAIL' end, p_step, p_exp, p_act; end $$;
create or replace function tt.t(p_step text, p_ok boolean, p_exp text default 'true', p_act text default null, p_note text default null) returns void language plpgsql as $$
begin insert into tt.ea (step, expected, actual, ok, note) values (p_step, p_exp, coalesce(p_act, coalesce(p_ok,false)::text), coalesce(p_ok,false), p_note); raise notice '% % %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_step, coalesce(p_act,''); end $$;
-- expected error
create or replace function tt.err(p_step text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; insert into tt.ea (step, expected, actual, ok) values (p_step, 'error '||p_msg, 'NO ERROR', false); raise notice 'FAIL % (no error)', p_step;
exception when others then
  insert into tt.ea (step, expected, actual, ok) values (p_step, 'error '||p_msg, left(sqlerrm,90), sqlerrm like '%'||p_msg||'%'); raise notice '% % (%)', case when sqlerrm like '%'||p_msg||'%' then 'PASS' else 'FAIL' end, p_step, left(sqlerrm,60); end $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$ select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
-- sum of one account (by code) over all posted lines: debit - credit
create or replace function tt.bal(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit),0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.bal_loc(p_code text, p_loc int) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit),0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code and l.location_id = p_loc $$;
create or replace function tt.qty(p_code text, p_loc int default 1) returns numeric language sql stable as $$
  select coalesce((select b.qty from public.stock_balance b join public.items i on i.id=b.item_id where i.code=p_code and b.location_id=p_loc),0) $$;
create or replace function tt.avg(p_code text, p_loc int default 1) returns numeric language sql stable as $$
  select (select b.avg_cost from public.stock_balance b join public.items i on i.id=b.item_id where i.code=p_code and b.location_id=p_loc) $$;
create or replace function tt.iid(p_code text) returns uuid language sql stable as $$ select id from public.items where code=p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on all tables in schema tt to authenticated, anon; grant usage on all sequences in schema tt to authenticated, anon;
\echo == mode = :mode
