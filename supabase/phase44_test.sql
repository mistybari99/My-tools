-- FRESH DB ONLY. Phase 44 tests (Module D: partnership / profit-sharing deed engine) with worked numeric examples for every rule kind.
--   ORDER="phase8 ... phase28 phase44" bash tests/sql/build_fresh_db.sh a44db ; psql -h /tmp -p 5544 -U postgres -d a44db -qAt -f supabase/phase44_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
-- test helpers: build a deed in one call; amount a party gets in a calculation
create or replace function tt.mk(p_venture bigint, p_title text, p_from date, p_parties jsonb, p_rules jsonb, p_activate boolean default true) returns bigint language plpgsql as $$
declare a bigint; e jsonb;
begin
  a := (partner_agreement_save(null, p_venture, p_title, p_from, null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id')::bigint;
  for e in select value from jsonb_array_elements(p_parties) loop perform partner_agreement_party_set(a, (e->>'p')::bigint, e->>'r', null, null); end loop;
  for e in select value from jsonb_array_elements(p_rules) loop perform partner_rule_save(a, null, e->>'n', e->>'k', e->'c'); end loop;
  if p_activate then perform partner_agreement_activate(a); end if;
  return a;
end $$;
create or replace function tt.amt(c jsonb, p bigint) returns numeric language sql as $$ select coalesce(sum((e->>'amount')::numeric),0) from jsonb_array_elements(c->'party_totals') e where (e->>'party_id')::bigint = p $$;
create or replace function tt.step(c jsonb, n int) returns jsonb language sql as $$ select e from jsonb_array_elements(c->'steps') e where (e->>'step_no')::int = n $$;
create or replace function tt.warn(c jsonb, code text) returns boolean language sql as $$ select exists (select 1 from jsonb_array_elements(c->'warnings') e where e->>'code' = code) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;

\echo == shape
select tt.chk('T0 all 10 tables have RLS, no write grants', (select count(*) from pg_class where relname in ('partner_parties','partner_ventures','partner_agreements','agreement_parties','partner_rules','partner_capital','partner_settlements','partner_settlement_lines','partner_settlement_payments','partner_templates') and relrowsecurity)=10
  and not has_table_privilege('authenticated','partner_settlements','insert') and not has_table_privilege('authenticated','partner_capital','update') and not has_table_privilege('authenticated','partner_rules','delete'));
select tt.chk('T0 anon has no execute and no select', not has_function_privilege('anon','partner_calculate(bigint,date,date,jsonb)','execute') and not has_table_privilege('anon','partner_parties','select'));
select tt.chk('T0 helpers are not callable by users', not has_function_privilege('authenticated','_a44_guard()','execute') and not has_function_privilege('authenticated','_a44_cap(bigint,bigint,date)','execute'));
select tt.chk('T0 switch rule exists and is ON', (select count(*) from rules where key='partners_module_on')=1 and rule_on('partners_module_on'));
select tt.chk('T0 four EXAMPLE templates, inactive', (select count(*) from partner_templates where is_example and not active)=4);

\echo == owner only
set role authenticated; select tt.as(:'o');
select partner_party_save(null,'Owner Party','company','01711000000','o@x.app','REG-1','Dhaka',null,'owner side',true,gen_random_uuid()) ->> 'id' as pa \gset
select partner_party_save(null,'Investor Ivy','individual','01811000000',null,'NID-2',null,null,null,true,gen_random_uuid()) ->> 'id' as pb \gset
select partner_party_save(null,'Investor Eve','individual','01911000000',null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pe \gset
select partner_party_save(null,'Partner Pat','individual',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pc \gset
select partner_party_save(null,'Franchisee Fay','individual',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pd \gset
select tt.as(:'s');
select tt.chk('P1 a manager sees no party', (select count(*) from partner_parties)=0 and (select count(*) from partner_templates)=0);
select tt.err('P1 manager cannot create a party', $$select partner_party_save(null,'X','individual',null,null,null,null,null,null,true)$$, 'not allowed');
select tt.err('P1 manager cannot calculate', $$select partner_calculate(1,'2026-01-01','2026-01-31')$$, 'not allowed');
select tt.err('P1 manager cannot read the overview', $$select partner_overview()$$, 'not allowed');
select tt.err('P1 manager cannot validate a rule', $$select partner_rule_validate('split','{}')$$, 'not allowed');
select tt.err('P1 manager cannot read a statement', format($$select partner_party_statement(%s,'2026-01-01','2026-01-31')$$, :pa), 'not allowed');
select tt.as(:'o');
reset role; update rules set value='false'::jsonb where key='partners_module_on'; set role authenticated;
select tt.err('P2 module OFF blocks even the owner', $$select partner_overview()$$, 'module_off');
reset role; update rules set value=null where key='partners_module_on'; set role authenticated; select tt.as(:'o');
select tt.chk('P2 module ON again', partner_overview() is not null);

\echo == parties and ventures
select partner_party_save(null,'Owner Party','company',null,null,null,null,null,null,true,(select client_id from partner_parties where id=:pa)) ->> 'id' = :'pa' as same \gset
select tt.chk('V1 same client key = same party (idempotent)', :'same'::boolean and (select count(*) from partner_parties)=5);
select tt.err('V1 name is required', $$select partner_party_save(null,' ','individual',null,null,null,null,null,null,true)$$, 'name_required');
select partner_venture_save(null,'কাস্টম ডিল','Custom deal','custom',null,'partnership','2026-01-01',null,'draft',null,gen_random_uuid()) ->> 'id' as v1 \gset
select partner_venture_save(null,'শো-রুম ১','Showroom 1','location',1,'franchise','2026-01-01',null,'draft',null,gen_random_uuid()) ->> 'id' as v2 \gset
select tt.err('V2 a place-venture needs a real place', $$select partner_venture_save(null,'x','x','location',9999,'own',null,null,'draft',null)$$, 'location_not_found');
select tt.err('V2 bad scope refused', $$select partner_venture_save(null,'x','x','nope',null,'own',null,null,'draft',null)$$, 'bad_scope');
select tt.err('V2 end before start refused', $$select partner_venture_save(null,'x','x','custom',null,'own','2026-05-01','2026-04-01','draft',null)$$, 'bad_date');

\echo == rule validation
select tt.err('R0 split must sum to 100', $$select partner_rule_validate('split','{"shares":[{"role":"owner","percent":60},{"role":"partner","percent":30}]}')$$, 'split_not_100');
select tt.err('R0 unknown kind', $$select partner_rule_validate('magic','{}')$$, 'bad_kind');
select tt.err('R0 slabs must increase', $$select partner_rule_validate('tiered_split','{"slabs":[{"upto":200,"shares":[{"role":"owner","percent":100}]},{"upto":100,"shares":[{"role":"owner","percent":100}]}]}')$$, 'slab_order');
select tt.err('R0 only the last slab is open', $$select partner_rule_validate('tiered_split','{"slabs":[{"upto":null,"shares":[{"role":"owner","percent":100}]},{"upto":100,"shares":[{"role":"owner","percent":100}]}]}')$$, 'slab_order');
select tt.err('R0 fee: percent XOR fixed', $$select partner_rule_validate('management_fee','{"role":"manager","percent":5,"fixed":100}')$$, 'bad_config');
select tt.err('R0 royalty percent range', $$select partner_rule_validate('royalty','{"role":"owner","percent":150}')$$, 'bad_config');
select tt.err('R0 rounding step must be a known size', $$select partner_rule_validate('rounding','{"to":7}')$$, 'bad_config');
select tt.err('R0 base must be known', $$select partner_rule_validate('base','{"base":"vibes"}')$$, 'bad_config');
select tt.err('R0 party is required', $$select partner_rule_validate('payback','{"percent":50}')$$, 'bad_config');
select tt.chk('R0 a good config is returned', partner_rule_validate('rounding','{"to":10}') ->> 'to' = '10');

\echo == F: franchise worked example (royalty + monthly fee + split)
select tt.mk(:v1, 'Franchise F', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"franchisee"}]', :pa, :pd)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Royalty 5% of net sales","k":"royalty","c":{"role":"owner","percent":5,"base":"net_sales"}},{"n":"Monthly fee 10000","k":"management_fee","c":{"role":"owner","fixed":10000,"per":"month"}},{"n":"Rest to franchisee","k":"split","c":{"shares":[{"role":"franchisee","percent":100}]}}]'::jsonb) as agf \gset
select partner_calculate(:agf,'2026-01-01','2026-01-31','{"net_sales":400000,"net_profit_before_fees":90000}'::jsonb) as c \gset
select tt.chk('F1 royalty 5% of 400000 = 20000 + fee 10000 = owner 30000', tt.amt(:'c'::jsonb,:pa)=30000);
select tt.chk('F1 franchisee keeps 90000-30000 = 60000', tt.amt(:'c'::jsonb,:pd)=60000 and (:'c'::jsonb ->> 'total_distributable')::numeric=90000);
select tt.chk('F1 steps show the pool: after royalty 70000, after fee 60000', (tt.step(:'c'::jsonb,2)->>'pool_after')::numeric=70000 and (tt.step(:'c'::jsonb,3)->>'pool_after')::numeric=60000 and (tt.step(:'c'::jsonb,2)->>'amount')::numeric=20000);
select tt.chk('F1 trial is flagged as writing nothing, sources say manual', (:'c'::jsonb->>'wrote')='false' and (:'c'::jsonb #>> '{sources,net_sales}')='manual' and :'c'::jsonb->>'status'='ok');
select partner_calculate(:agf,'2026-01-01','2026-02-28','{"net_sales":400000,"net_profit_before_fees":90000}'::jsonb) as c2 \gset
select tt.chk('F2 two months: the fixed monthly fee counts twice (20000)', tt.amt(:'c2'::jsonb,:pa)=20000+20000);
select partner_calculate(:agf,'2026-01-01','2026-01-31') as c3 \gset
select tt.chk('F3 no books for a custom venture and no manual base = incomplete, nothing invented', :'c3'::jsonb->>'status'='incomplete' and tt.warn(:'c3'::jsonb,'manual_only') and tt.warn(:'c3'::jsonb,'base_unavailable') and tt.amt(:'c3'::jsonb,:pd)=0);
select tt.err('F3 an incomplete calculation cannot be saved', format($$select partner_settlement_save(%s,'2026-01-01','2026-01-31',null,null)$$, :agf), 'calc_incomplete');
select tt.err('F3 bad manual key refused', format($$select partner_calculate(%s,'2026-01-01','2026-01-31','{"bogus":1}'::jsonb)$$, :agf), 'bad_manual');
select tt.err('F3 bad range refused', format($$select partner_calculate(%s,'2026-02-01','2026-01-31')$$, :agf), 'bad_range');

\echo == preview writes nothing
select (select count(*) from partner_settlements) + (select count(*) from partner_settlement_lines) + (select count(*) from audit_log) as before_n \gset
select partner_calculate(:agf,'2026-01-01','2026-01-31','{"net_sales":1,"net_profit_before_fees":1}'::jsonb) is not null as x \gset
select tt.chk('PV preview wrote no settlement, no line, no audit row', (select count(*) from partner_settlements) + (select count(*) from partner_settlement_lines) + (select count(*) from audit_log) = :before_n);

\echo == settlement: draft snapshot, overlap, idempotency, approval
select gen_random_uuid() as k1 \gset
select partner_settlement_save(:agf,'2026-01-01','2026-01-31','{"net_sales":400000,"net_profit_before_fees":90000}'::jsonb,'Jan',:'k1') ->> 'id' as sf1 \gset
select tt.chk('S1 draft saved with 3 lines: owner royalty 20000, owner fee 10000, franchisee share 60000',
  (select count(*) from partner_settlement_lines where settlement_id=:sf1)=3
  and (select amount from partner_settlement_lines where settlement_id=:sf1 and kind='royalty')=20000 and (select amount from partner_settlement_lines where settlement_id=:sf1 and kind='fee')=10000
  and (select amount from partner_settlement_lines where settlement_id=:sf1 and kind='share' and party_id=:pd)=60000 and (select total_distributable from partner_settlements where id=:sf1)=90000);
select tt.chk('S1 snapshot holds the full waterfall', (select jsonb_array_length(calc->'steps') from partner_settlements where id=:sf1)=4);
select partner_settlement_save(:agf,'2026-01-01','2026-01-31','{"net_sales":400000,"net_profit_before_fees":90000}'::jsonb,'Jan',:'k1') ->> 'id' = :'sf1' as same \gset
select tt.chk('S2 same client key = same settlement', :'same'::boolean and (select count(*) from partner_settlements where agreement_id=:agf)=1);
select tt.err('S2 the same period again is refused', format($$select partner_settlement_save(%s,'2026-01-01','2026-01-31','{"net_sales":1,"net_profit_before_fees":1}'::jsonb,null,gen_random_uuid())$$, :agf), 'period_overlap');
select tt.err('S2 a half-overlapping period is refused', format($$select partner_settlement_save(%s,'2026-01-15','2026-02-15','{"net_sales":1,"net_profit_before_fees":1}'::jsonb,null,gen_random_uuid())$$, :agf), 'period_overlap');
select tt.err('S2 a future period is refused', format($$select partner_settlement_save(%s,'2026-11-01','2026-12-31','{"net_sales":1,"net_profit_before_fees":1}'::jsonb,null,gen_random_uuid())$$, :agf), 'bad_date');
select tt.err('S2 before the deed starts is refused', format($$select partner_settlement_save(%s,'2025-11-01','2025-11-30','{"net_sales":1,"net_profit_before_fees":1}'::jsonb,null,gen_random_uuid())$$, :agf), 'outside_deed_dates');
select partner_settlement_save(:agf,'2026-02-01','2026-02-28','{"net_sales":100000,"net_profit_before_fees":20000}'::jsonb,'Feb',gen_random_uuid()) ->> 'id' as sf2 \gset
select tt.chk('S2 the next month is fine (Feb: royalty 5000 + fee 10000, franchisee 5000)', (select sum(amount) from partner_settlement_lines where settlement_id=:sf2 and party_id=:pa)=15000 and (select amount from partner_settlement_lines where settlement_id=:sf2 and party_id=:pd)=5000);
select tt.err('S3 pay needs an approved settlement', format($$select partner_settlement_pay((select id from partner_settlement_lines where settlement_id=%s and kind='fee'),1000,'cash','2026-02-05',null)$$, :sf1), 'not_approved');
select partner_settlement_approve(:sf1) ->> 'status' as st \gset
select tt.chk('S3 approved', :'st'='approved' and (select approved_by from partner_settlements where id=:sf1) is not null);
select tt.err('S3 approving twice is refused', format($$select partner_settlement_approve(%s)$$, :sf1), 'not_draft');
reset role;
select tt.err('S4 approved settlement: the calculation cannot be edited (even by the DB owner)', format($$update partner_settlements set calc = '{}'::jsonb where id=%s$$, :sf1), 'settlement_immutable');
select tt.err('S4 approved settlement: the total cannot be edited', format($$update partner_settlements set total_distributable = 1 where id=%s$$, :sf1), 'settlement_immutable');
select tt.err('S4 approved settlement: the period cannot be edited', format($$update partner_settlements set period_to = '2026-02-15' where id=%s$$, :sf1), 'settlement_immutable');
select tt.err('S4 a settlement line amount cannot be edited', format($$update partner_settlement_lines set amount = 1 where settlement_id=%s$$, :sf1), 'settlement_immutable');
select tt.err('S4 a settlement cannot be deleted', format($$delete from partner_settlements where id=%s$$, :sf1), 'append_only');
set role authenticated; select tt.as(:'o');
select partner_settlement_pay(l.id, 4000, 'cash', '2026-02-05', 'v1') ->> 'amount' as p1 from partner_settlement_lines l where l.settlement_id=:sf1 and l.kind='fee' \gset
select tt.chk('S5 part payment of the 10000 fee recorded', :'p1'::numeric=4000 and (select paid_amount from partner_settlement_lines where settlement_id=:sf1 and kind='fee')=4000 and (select status from partner_settlements where id=:sf1)='approved');
select tt.err('S5 overpaying a line is refused', format($$select partner_settlement_pay((select id from partner_settlement_lines where settlement_id=%s and kind='fee'),6001,'cash','2026-02-06',null)$$, :sf1), 'overpay');
select tt.err('S5 payment before the period began refused', format($$select partner_settlement_pay((select id from partner_settlement_lines where settlement_id=%s and kind='fee'),1,'cash','2025-12-31',null)$$, :sf1), 'bad_date');
select tt.err('S5 future payment date refused', format($$select partner_settlement_pay((select id from partner_settlement_lines where settlement_id=%s and kind='fee'),1,'cash',current_date+5,null)$$, :sf1), 'bad_date');
select tt.err('S5 bad mode refused', format($$select partner_settlement_pay((select id from partner_settlement_lines where settlement_id=%s and kind='fee'),1,'barter','2026-02-06',null)$$, :sf1), 'bad_mode');
select tt.err('S5 a settled amount of zero refused', format($$select partner_settlement_pay((select id from partner_settlement_lines where settlement_id=%s and kind='fee'),0,'cash','2026-02-06',null)$$, :sf1), 'bad_amount');
select tt.err('S5 an approved settlement with payments cannot be voided', format($$select partner_settlement_void(%s,'oops')$$, :sf1), 'has_payments');
select partner_settlement_pay(l.id, l.amount - l.paid_amount, 'bank', '2026-02-07', null, gen_random_uuid()) is not null as x from partner_settlement_lines l where l.settlement_id=:sf1 \gset
select tt.chk('S5 all lines paid = settlement paid', (select status from partner_settlements where id=:sf1)='paid' and (select count(*) from partner_settlement_payments)=4);
select tt.err('S5 a paid settlement cannot be voided', format($$select partner_settlement_void(%s,'oops')$$, :sf1), 'cannot_void');
select tt.chk('S6 a draft can be voided with a reason, then the period is free again',
  (select partner_settlement_void(:sf2,'wrong figures') ->> 'status')='void'
  and (select partner_settlement_save(:agf,'2026-02-01','2026-02-28','{"net_sales":100000,"net_profit_before_fees":20000}'::jsonb,'Feb again',gen_random_uuid()) ->> 'status')='draft');
select tt.err('S6 void needs a reason', format($$select partner_settlement_void((select max(id) from partner_settlements where agreement_id=%s),' ')$$, :agf), 'reason_required');

\echo == R: rounding step (to 10, remainder to the largest share)
select tt.mk(:v1, 'Rounding R', '2026-01-01', format('[{"p":%s,"r":"investor"},{"p":%s,"r":"partner"},{"p":%s,"r":"franchisee"}]', :pb, :pc, :pd)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Round to 10","k":"rounding","c":{"to":10,"mode":"nearest"}},{"n":"Split","k":"split","c":{"shares":[{"role":"investor","percent":33.33},{"role":"partner","percent":33.33},{"role":"franchisee","percent":33.34}]}}]'::jsonb) as agr \gset
select partner_calculate(:agr,'2026-01-01','2026-01-31','{"net_profit_before_fees":1000}'::jsonb) as c \gset
select tt.chk('R1 333.30 rounds to 330, 330, and the remainder 10 goes to the largest share = 340', tt.amt(:'c'::jsonb,:pb)=330 and tt.amt(:'c'::jsonb,:pc)=330 and tt.amt(:'c'::jsonb,:pd)=340 and (:'c'::jsonb->>'total_distributable')::numeric=1000);
select partner_calculate(:agr,'2026-01-01','2026-01-31','{"net_profit_before_fees":100.01}'::jsonb) as c \gset
select tt.chk('R1 nothing is lost or created by rounding', (:'c'::jsonb->>'total_distributable')::numeric=100.01);

\echo == PR: priority return with cap, across months, and time-weighted capital
select tt.mk(:v1, 'Priority PR', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"investor"}]', :pa, :pb)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Investor 12% a year, cap 2000","k":"priority_return","c":{"role":"investor","percent_per_year":12,"cap":2000}},{"n":"Rest to owner","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agpr \gset
select partner_capital_add(:agpr,:pb,'contribution',100000,'2025-12-01','bank','seed','CH-1',gen_random_uuid()) ->> 'id' as cap1 \gset
select partner_calculate(:agpr,'2026-01-01','2026-01-31','{"net_profit_before_fees":5000}'::jsonb) as c \gset
select tt.chk('PR1 Jan: 100000 x 12% x 31/365 = 1019.18 to the investor, owner 3980.82', tt.amt(:'c'::jsonb,:pb)=1019.18 and tt.amt(:'c'::jsonb,:pa)=3980.82);
select partner_settlement_save(:agpr,'2026-01-01','2026-01-31','{"net_profit_before_fees":5000}'::jsonb,null,gen_random_uuid()) is not null as x \gset
select partner_calculate(:agpr,'2026-02-01','2026-02-28','{"net_profit_before_fees":5000}'::jsonb) as c \gset
select tt.chk('PR2 Feb: 28/365 -> 920.55 (cap room left 980.82, so not capped yet)', tt.amt(:'c'::jsonb,:pb)=920.55 and tt.amt(:'c'::jsonb,:pa)=4079.45);
select partner_settlement_save(:agpr,'2026-02-01','2026-02-28','{"net_profit_before_fees":5000}'::jsonb,null,gen_random_uuid()) is not null as x \gset
select partner_calculate(:agpr,'2026-03-01','2026-03-31','{"net_profit_before_fees":5000}'::jsonb) as c \gset
select tt.chk('PR3 Mar: the cap of 2000 leaves only 2000-1019.18-920.55 = 60.27', tt.amt(:'c'::jsonb,:pb)=60.27 and tt.amt(:'c'::jsonb,:pa)=4939.73);
select partner_settlement_save(:agpr,'2026-03-01','2026-03-31','{"net_profit_before_fees":5000}'::jsonb,null,gen_random_uuid()) is not null as x \gset
select partner_calculate(:agpr,'2026-04-01','2026-04-30','{"net_profit_before_fees":5000}'::jsonb) as c \gset
select tt.chk('PR4 Apr: the cap is used up = 0 to the investor, owner keeps 5000', tt.amt(:'c'::jsonb,:pb)=0 and tt.amt(:'c'::jsonb,:pa)=5000);
select partner_calculate(:agpr,'2026-05-01','2026-05-31','{"net_profit_before_fees":-100}'::jsonb) as c \gset
select tt.chk('PR5 a loss pays no return and warns', tt.amt(:'c'::jsonb,:pb)=0 and tt.warn(:'c'::jsonb,'no_profit'));
select tt.mk(:v1, 'Priority PR2 time-weighted', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"investor"}]', :pa, :pb)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Investor 12% a year","k":"priority_return","c":{"role":"investor","percent_per_year":12}},{"n":"Rest","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agpr2 \gset
select partner_capital_add(:agpr2,:pb,'contribution',100000,'2025-12-01','bank',null,null,gen_random_uuid()) is not null as x \gset
select partner_capital_add(:agpr2,:pb,'contribution',100000,'2026-01-16','bank','second tranche',null,gen_random_uuid()) is not null as x \gset
select partner_calculate(:agpr2,'2026-01-01','2026-01-31','{"net_profit_before_fees":10000}'::jsonb) as c \gset
select tt.chk('PR6 capital is time-weighted: (31 x 100000 + 16 x 100000) x 12% / 365 = 1545.21', tt.amt(:'c'::jsonb,:pb)=1545.21 and tt.amt(:'c'::jsonb,:pa)=8454.79);

\echo == CU: fixed monthly return with catch-up
select tt.mk(:v1, 'Catch-up CU', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"investor"}]', :pa, :pb)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Investor 1000 a month with catch-up","k":"priority_return","c":{"role":"investor","fixed_monthly":1000,"catch_up":true}},{"n":"Rest","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agcu \gset
select partner_calculate(:agcu,'2026-01-01','2026-01-31','{"net_profit_before_fees":600}'::jsonb) as c \gset
select tt.chk('CU1 Jan: only 600 profit -> investor 600, shortfall 400 carried, owner 0', tt.amt(:'c'::jsonb,:pb)=600 and tt.amt(:'c'::jsonb,:pa)=0 and (tt.step(:'c'::jsonb,2)->>'shortfall_out')::numeric=400);
select partner_settlement_save(:agcu,'2026-01-01','2026-01-31','{"net_profit_before_fees":600}'::jsonb,null,gen_random_uuid()) is not null as x \gset
select partner_calculate(:agcu,'2026-02-01','2026-02-28','{"net_profit_before_fees":5000}'::jsonb) as c \gset
select tt.chk('CU2 Feb: 1000 due + 400 caught up = 1400, owner 3600, nothing left owing', tt.amt(:'c'::jsonb,:pb)=1400 and tt.amt(:'c'::jsonb,:pa)=3600 and (tt.step(:'c'::jsonb,2)->>'shortfall_out')::numeric=0);
select partner_calculate(:agcu,'2026-02-01','2026-03-31','{"net_profit_before_fees":9000}'::jsonb) as c \gset
select tt.chk('CU3 a two-month period: 2 x 1000 + 400 = 2400', tt.amt(:'c'::jsonb,:pb)=2400);

\echo == PB: payback, then a lower share (and the party statement)
select tt.mk(:v1, 'Payback PB', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"investor"}]', :pa, :pe)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Investor takes all until paid back, then 30%","k":"payback","c":{"role":"investor","percent":100,"then_percent":30}},{"n":"Rest to owner","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agpb \gset
select partner_capital_add(:agpb,:pe,'contribution',10000,'2025-12-01','cash','capital',null,gen_random_uuid()) is not null as x \gset
select partner_calculate(:agpb,'2026-01-01','2026-01-31','{"net_profit_before_fees":6000}'::jsonb) as c \gset
select tt.chk('PB1 Jan: all 6000 profit pays back the investor (10000 outstanding), owner 0', tt.amt(:'c'::jsonb,:pe)=6000 and tt.amt(:'c'::jsonb,:pa)=0 and (tt.step(:'c'::jsonb,2)->'detail'->>'outstanding_after')::numeric=4000);
select partner_settlement_save(:agpb,'2026-01-01','2026-01-31','{"net_profit_before_fees":6000}'::jsonb,null,gen_random_uuid()) ->> 'id' as spb1 \gset
select partner_calculate(:agpb,'2026-02-01','2026-02-28','{"net_profit_before_fees":8000}'::jsonb) as c \gset
select tt.chk('PB2 Feb: 4000 finishes the payback, then 30% of the other 4000 = 1200 -> investor 5200, owner 2800', tt.amt(:'c'::jsonb,:pe)=5200 and tt.amt(:'c'::jsonb,:pa)=2800);
select partner_settlement_save(:agpb,'2026-02-01','2026-02-28','{"net_profit_before_fees":8000}'::jsonb,null,gen_random_uuid()) ->> 'id' as spb2 \gset
select partner_calculate(:agpb,'2026-03-01','2026-03-31','{"net_profit_before_fees":5000}'::jsonb) as c \gset
select tt.chk('PB3 Mar: capital is back, so the lower 30% applies: investor 1500, owner 3500', tt.amt(:'c'::jsonb,:pe)=1500 and tt.amt(:'c'::jsonb,:pa)=3500);
select tt.mk(:v1, 'Payback PB2 half', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"investor"}]', :pa, :pb)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Investor 50% until paid back, then 20%","k":"payback","c":{"role":"investor","percent":50,"then_percent":20}},{"n":"Rest","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agpb2 \gset
select partner_capital_add(:agpb2,:pb,'contribution',10000,'2025-12-01','cash',null,null,gen_random_uuid()) is not null as x \gset
select partner_calculate(:agpb2,'2026-01-01','2026-01-31','{"net_profit_before_fees":30000}'::jsonb) as c \gset
select tt.chk('PB4 50% of 30000 = 15000 > 10000 outstanding: payback 10000 uses 20000 of profit; 20% of the other 10000 = 2000 -> investor 12000, owner 18000', tt.amt(:'c'::jsonb,:pb)=12000 and tt.amt(:'c'::jsonb,:pa)=18000);
select partner_settlement_approve(:spb1) is not null as x \gset
select partner_settlement_approve(:spb2) is not null as x \gset
select l.id as lpb1 from partner_settlement_lines l where l.settlement_id=:spb1 and l.party_id=:pe and l.kind='payback' \gset
select l.id as lpb2 from partner_settlement_lines l where l.settlement_id=:spb2 and l.party_id=:pe and l.kind='payback' \gset
select partner_settlement_pay(:lpb1, 6000, 'bank', '2026-02-05', 'chq-1') is not null as x \gset
select tt.chk('PB5 paying the only line of Jan marks Jan paid', (select status from partner_settlements where id=:spb1)='paid');
select partner_settlement_pay(:lpb2, 1000, 'mobile', '2026-02-20', 'bkash') is not null as x \gset
select partner_party_statement(:pe, '2025-12-01', '2026-02-28') as st \gset
select tt.chk('PB6 statement: capital 10000 in, none before', (:'st'::jsonb->>'capital_opening')::numeric=0 and (:'st'::jsonb->>'capital_closing')::numeric=10000 and jsonb_array_length(:'st'::jsonb->'capital_movements')=1);
select tt.chk('PB6 statement: shares due Jan payback 6000 + Feb payback 4000 + Feb share 1200 = 11200 in 3 lines', jsonb_array_length(:'st'::jsonb->'shares_due')=3 and (:'st'::jsonb->>'due_in_period')::numeric=11200);
select tt.chk('PB6 statement: paid 6000 + 1000 = 7000 and balance owed 4200', (:'st'::jsonb->>'paid_in_period')::numeric=7000 and (:'st'::jsonb->>'balance_owed')::numeric=4200 and jsonb_array_length(:'st'::jsonb->'payments')=2);
select partner_party_statement(:pe, '2026-03-01', '2026-03-31') as st2 \gset
select tt.chk('PB6 a later statement opens with the capital and still owes 4200', (:'st2'::jsonb->>'capital_opening')::numeric=10000 and (:'st2'::jsonb->>'balance_owed')::numeric=4200 and (:'st2'::jsonb->>'due_in_period')::numeric=0);
select tt.chk('PB6 statement carries the contact details for printing', :'st'::jsonb #>> '{party,name}' = 'Investor Eve' and :'st'::jsonb #>> '{party,mobile}' = '01911000000');
select partner_capital_balances(:agpb) as bal \gset
select tt.chk('PB7 balances: capital 10000, paid back 10000, nothing outstanding', (select (e->>'balance')::numeric=10000 and (e->>'paid_back')::numeric=10000 and (e->>'outstanding_payback')::numeric=0 from jsonb_array_elements(:'bal'::jsonb) e where (e->>'party_id')::bigint=:pe));
select partner_overview() as ov \gset
select tt.chk('PB8 overview: owed total = 4000 (Feb payback) - 1000 paid + Feb owner/fee lines etc.', (:'ov'::jsonb->>'owed_total')::numeric > 0 and jsonb_array_length(:'ov'::jsonb->'ventures')=2);

\echo == T: tiered split
select tt.mk(:v1, 'Tiered T', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"partner"}]', :pa, :pc)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Slabs","k":"tiered_split","c":{"slabs":[{"upto":100000,"shares":[{"role":"owner","percent":70},{"role":"partner","percent":30}]},{"upto":200000,"shares":[{"role":"owner","percent":50},{"role":"partner","percent":50}]},{"upto":null,"shares":[{"role":"owner","percent":30},{"role":"partner","percent":70}]}]}}]'::jsonb) as agt \gset
select partner_calculate(:agt,'2026-01-01','2026-01-31','{"net_profit_before_fees":250000}'::jsonb) as c \gset
select tt.chk('T1 250000: first 100000 at 70/30, next 100000 at 50/50, last 50000 at 30/70 -> owner 135000, partner 115000', tt.amt(:'c'::jsonb,:pa)=135000 and tt.amt(:'c'::jsonb,:pc)=115000);
select tt.chk('T1 the steps show every slab', jsonb_array_length(tt.step(:'c'::jsonb,2)->'detail'->'slabs')=3);
select partner_calculate(:agt,'2026-01-01','2026-01-31','{"net_profit_before_fees":80000}'::jsonb) as c \gset
select tt.chk('T2 80000 stays inside the first slab: owner 56000, partner 24000', tt.amt(:'c'::jsonb,:pa)=56000 and tt.amt(:'c'::jsonb,:pc)=24000);

\echo == L: loss carry-forward
select tt.mk(:v1, 'Loss L', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"partner"}]', :pa, :pc)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Carry losses","k":"loss_carry_forward","c":{}},{"n":"60/40","k":"split","c":{"shares":[{"role":"owner","percent":60},{"role":"partner","percent":40}]}}]'::jsonb) as agl \gset
select partner_calculate(:agl,'2026-01-01','2026-01-31','{"net_profit_before_fees":-3000}'::jsonb) as c \gset
select tt.chk('L1 Jan: loss of 3000 -> nothing shared, 3000 carried forward', tt.amt(:'c'::jsonb,:pa)=0 and (:'c'::jsonb->>'carry_out')::numeric=3000 and (:'c'::jsonb->>'total_distributable')::numeric=0);
select partner_settlement_save(:agl,'2026-01-01','2026-01-31','{"net_profit_before_fees":-3000}'::jsonb,'loss month',gen_random_uuid()) ->> 'id' as sl1 \gset
select tt.chk('L1 the loss settlement is saved with no lines and carries 3000', (select count(*) from partner_settlement_lines where settlement_id=:sl1)=0 and (select carry_out from partner_settlements where id=:sl1)=3000);
select partner_calculate(:agl,'2026-02-01','2026-02-28','{"net_profit_before_fees":10000}'::jsonb) as c \gset
select tt.chk('L2 Feb: 10000 - 3000 carried = 7000 -> owner 4200, partner 2800, carry cleared', tt.amt(:'c'::jsonb,:pa)=4200 and tt.amt(:'c'::jsonb,:pc)=2800 and (:'c'::jsonb->>'carry_in')::numeric=3000 and (:'c'::jsonb->>'carry_out')::numeric=0);
select partner_calculate(:agl,'2026-02-01','2026-02-28','{"net_profit_before_fees":2000}'::jsonb) as c \gset
select tt.chk('L3 Feb with only 2000: it all goes to the old loss, 1000 still carried', tt.amt(:'c'::jsonb,:pa)=0 and (:'c'::jsonb->>'carry_out')::numeric=1000);
select partner_calculate(:agl,'2026-02-01','2026-02-28','{"net_profit_before_fees":10000,"carry_in":1000}'::jsonb) as c \gset
select tt.chk('L4 the owner may type the carried loss: 10000 - 1000 = 9000 -> 5400 / 3600', tt.amt(:'c'::jsonb,:pa)=5400 and tt.amt(:'c'::jsonb,:pc)=3600);

\echo == G: minimum guarantee, cap, floor, expenses, management fee, fixed base
select tt.mk(:v1, 'Guarantee G1', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"franchisee"}]', :pa, :pd)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Royalty 5%","k":"royalty","c":{"role":"owner","percent":5,"base":"net_sales"}},{"n":"Owner minimum 10000 a month","k":"minimum_guarantee","c":{"role":"owner","amount":10000,"per":"month"}},{"n":"Rest","k":"split","c":{"shares":[{"role":"franchisee","percent":100}]}}]'::jsonb) as agg1 \gset
select partner_calculate(:agg1,'2026-01-01','2026-01-31','{"net_sales":100000,"net_profit_before_fees":40000}'::jsonb) as c \gset
select tt.chk('G1 royalty 5000 < guarantee 10000: 5000 topped up from the pool -> owner 10000, franchisee 30000', tt.amt(:'c'::jsonb,:pa)=10000 and tt.amt(:'c'::jsonb,:pd)=30000 and (:'c'::jsonb->>'total_distributable')::numeric=40000);
select partner_calculate(:agg1,'2026-01-01','2026-01-31','{"net_sales":300000,"net_profit_before_fees":40000}'::jsonb) as c \gset
select tt.chk('G1 royalty 15000 already above the guarantee: no top-up, franchisee 25000', tt.amt(:'c'::jsonb,:pa)=15000 and tt.amt(:'c'::jsonb,:pd)=25000);
select partner_calculate(:agg1,'2026-01-01','2026-01-31','{"net_sales":100000,"net_profit_before_fees":7000}'::jsonb) as c \gset
select tt.chk('G1 the pool (2000) cannot cover the whole guarantee: owner gets 7000, a warning says so', tt.amt(:'c'::jsonb,:pa)=7000 and tt.amt(:'c'::jsonb,:pd)=0 and tt.warn(:'c'::jsonb,'guarantee_short'));
select partner_calculate(:agg1,'2026-01-01','2026-02-28','{"net_sales":100000,"net_profit_before_fees":40000}'::jsonb) as c \gset
select tt.chk('G1 over two months the monthly guarantee doubles to 20000', tt.amt(:'c'::jsonb,:pa)=20000);
select tt.mk(:v1, 'Guarantee G2 outside', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"franchisee"}]', :pa, :pd)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Royalty 5%","k":"royalty","c":{"role":"owner","percent":5,"base":"net_sales"}},{"n":"Owner minimum 10000 funded outside","k":"minimum_guarantee","c":{"role":"owner","amount":10000,"funded_by":"outside"}},{"n":"Rest","k":"split","c":{"shares":[{"role":"franchisee","percent":100}]}}]'::jsonb) as agg2 \gset
select partner_calculate(:agg2,'2026-01-01','2026-01-31','{"net_sales":100000,"net_profit_before_fees":40000}'::jsonb) as c \gset
select tt.chk('G2 outside-funded top-up: owner 10000, franchisee keeps 35000, 5000 shown as outside', tt.amt(:'c'::jsonb,:pa)=10000 and tt.amt(:'c'::jsonb,:pd)=35000 and (:'c'::jsonb->>'outside_total')::numeric=5000 and (:'c'::jsonb->>'total_distributable')::numeric=40000);
select tt.mk(:v1, 'Cap party C1', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"partner"}]', :pa, :pc)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"80/20","k":"split","c":{"shares":[{"role":"owner","percent":80},{"role":"partner","percent":20}]}},{"n":"Owner max 50000","k":"cap","c":{"target":"party","role":"owner","amount":50000}},{"n":"Excess to partner","k":"split","c":{"shares":[{"role":"partner","percent":100}]}}]'::jsonb) as agc1 \gset
select partner_calculate(:agc1,'2026-01-01','2026-01-31','{"net_profit_before_fees":100000}'::jsonb) as c \gset
select tt.chk('C1 owner 80000 capped to 50000; the 30000 excess goes back to the pool and then to the partner: 20000+30000', tt.amt(:'c'::jsonb,:pa)=50000 and tt.amt(:'c'::jsonb,:pc)=50000 and (:'c'::jsonb->>'total_distributable')::numeric=100000);
select tt.mk(:v1, 'Cap pool C2', '2026-01-01', format('[{"p":%s,"r":"owner"}]', :pa)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Pool max 70000","k":"cap","c":{"target":"pool","amount":70000}},{"n":"All to owner","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agc2 \gset
select partner_calculate(:agc2,'2026-01-01','2026-01-31','{"net_profit_before_fees":100000}'::jsonb) as c \gset
select tt.chk('C2 pool capped at 70000: owner 70000, 30000 retained (and the report says so)', tt.amt(:'c'::jsonb,:pa)=70000 and (:'c'::jsonb->>'retained')::numeric=30000);
select tt.mk(:v1, 'Floor F2', '2026-01-01', format('[{"p":%s,"r":"owner"}]', :pa)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Pool at least 5000","k":"floor","c":{"target":"pool","amount":5000}},{"n":"All to owner","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agfl \gset
select partner_calculate(:agfl,'2026-01-01','2026-01-31','{"net_profit_before_fees":1000}'::jsonb) as c \gset
select tt.chk('F2 floor lifts a 1000 pool to 5000 (4000 flagged as funded outside)', tt.amt(:'c'::jsonb,:pa)=5000 and (:'c'::jsonb->>'floor_added')::numeric=4000 and tt.warn(:'c'::jsonb,'floor_topup'));
select tt.mk(:v1, 'Expenses E1', '2026-01-01', format('[{"p":%s,"r":"owner"}]', :pa)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Extra costs allowed","k":"expense_allow","c":{"items":[{"name":"rent","amount":3000},{"name":"wage","amount":2000}]}},{"n":"Personal costs added back","k":"expense_disallow","c":{"items":[{"name":"personal","amount":1000}]}},{"n":"All to owner","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as age1 \gset
select partner_calculate(:age1,'2026-01-01','2026-01-31','{"net_profit_before_fees":50000}'::jsonb) as c \gset
select tt.chk('E1 50000 - 3000 - 2000 + 1000 = 46000', tt.amt(:'c'::jsonb,:pa)=46000);
select tt.mk(:v1, 'Fee M1', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"manager"}]', :pa, :pc)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Manager fee 10% of the pool","k":"management_fee","c":{"role":"manager","percent":10}},{"n":"Rest","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agm1 \gset
select partner_calculate(:agm1,'2026-01-01','2026-01-31','{"net_profit_before_fees":20000}'::jsonb) as c \gset
select tt.chk('M1 manager fee 10% of 20000 = 2000, owner 18000', tt.amt(:'c'::jsonb,:pc)=2000 and tt.amt(:'c'::jsonb,:pa)=18000);
select tt.mk(:v1, 'Fixed FA', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"partner"}]', :pa, :pc)::jsonb,
  '[{"n":"Fixed base 12000","k":"base","c":{"base":"fixed_amount","amount":12000}},{"n":"50/50","k":"split","c":{"shares":[{"role":"owner","percent":50},{"role":"partner","percent":50}]}}]'::jsonb) as agfa \gset
select partner_calculate(:agfa,'2026-01-01','2026-01-31') as c \gset
select tt.chk('FA a fixed base needs no books: 6000 each, complete', tt.amt(:'c'::jsonb,:pa)=6000 and tt.amt(:'c'::jsonb,:pc)=6000 and :'c'::jsonb->>'status'='ok');
select tt.chk('FA party refs by id work too', partner_rule_validate('royalty', format('{"party_id":%s,"percent":3}', :pa)::jsonb) is not null);

\echo == books: a real place with costed sales, expenses and salary
reset role;
insert into items (code,name_bn,name_en,category,unit,tracked,is_active,sellable,sell_price) values ('P44-A','এ','Item A','Sweets','kg',true,true,true,100), ('P44-B','বি','Item B (no cost)','Sweets','kg',true,true,true,50);
select id as ia from items where code='P44-A' \gset
select id as ib from items where code='P44-B' \gset
insert into item_costs (item_id, cost_price) values (:'ia',60) on conflict (item_id) do update set cost_price = excluded.cost_price;
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,9801,'2026-01-10','2026-01-10 10:00+06',format('[{"item_id":"%s","qty":10,"price":100,"unit":"kg","amount":1000}]',:'ia')::jsonb,1000,0,1000,'cash',:'s',1000,'done'),
 (gen_random_uuid(),1,9802,'2026-01-11','2026-01-11 10:00+06',format('[{"item_id":"%s","qty":9,"price":100,"unit":"kg","amount":900}]',:'ia')::jsonb,999,0,999,'cash',:'s',999,'void'),
 (gen_random_uuid(),1,9803,'2026-02-10','2026-02-10 10:00+06',format('[{"item_id":"%s","qty":10,"price":50,"unit":"kg","amount":500}]',:'ib')::jsonb,500,0,500,'cash',:'s',500,'done');
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('10-2',1,9811,'2026-01-12','approved','{"lines":[{"head":"transport","amount":100},{"head":"transport","amount":50}]}','[]',:'s','st'),
 ('10-2',1,9812,'2026-01-12','draft','{"lines":[{"head":"transport","amount":5000}]}','[]',:'s','st'),
 ('02-2',1,9821,'2026-01-30','approved','{"pay":[{"name":"TestK - Cook","due":200}]}','[]',:'s','st');
set role authenticated; select tt.as(:'o');
select tt.mk(:v2, 'Books B1 gross profit', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"franchisee"}]', :pa, :pd)::jsonb,
  '[{"n":"Base gross profit","k":"base","c":{"base":"gross_profit"}},{"n":"40/60","k":"split","c":{"shares":[{"role":"owner","percent":40},{"role":"franchisee","percent":60}]}}]'::jsonb) as agb1 \gset
select tt.mk(:v2, 'Books B2 net profit', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"franchisee"}]', :pa, :pd)::jsonb,
  '[{"n":"Base net profit","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"40/60","k":"split","c":{"shares":[{"role":"owner","percent":40},{"role":"franchisee","percent":60}]}}]'::jsonb) as agb2 \gset
select partner_calculate(:agb1,'2026-01-01','2026-01-31') as c \gset
select tt.chk('B1 books Jan: sales 1000 (the void 999 is out), cost 600 -> gross profit 400', (:'c'::jsonb #>> '{bases,gross_sales}')::numeric=1000 and (:'c'::jsonb #>> '{bases,net_sales}')::numeric=1000 and (:'c'::jsonb #>> '{bases,gross_profit}')::numeric=400);
select tt.chk('B1 expenses 150 (draft 5000 out) and salary 200 -> net profit before fees 50', (:'c'::jsonb #>> '{bases,expenses}')::numeric=150 and (:'c'::jsonb #>> '{bases,salary}')::numeric=200 and (:'c'::jsonb #>> '{bases,net_profit_before_fees}')::numeric=50);
select tt.chk('B1 gross profit 400 shared 40/60 = 160 / 240', tt.amt(:'c'::jsonb,:pa)=160 and tt.amt(:'c'::jsonb,:pd)=240 and :'c'::jsonb #>> '{sources,gross_profit}'='books');
select partner_calculate(:agb2,'2026-01-01','2026-01-31') as c \gset
select tt.chk('B2 net profit 50 shared 40/60 = 20 / 30', tt.amt(:'c'::jsonb,:pa)=20 and tt.amt(:'c'::jsonb,:pd)=30);
select partner_calculate(:agb1,'2026-02-01','2026-02-28') as c \gset
select tt.chk('B3 Feb: an item without a cost -> gross profit is NOT guessed (incomplete + warning)', :'c'::jsonb->>'status'='incomplete' and tt.warn(:'c'::jsonb,'uncosted_sales') and (:'c'::jsonb #>> '{bases,net_sales}')::numeric=500);
select tt.err('B3 and it cannot be saved as it is', format($$select partner_settlement_save(%s,'2026-02-01','2026-02-28',null,null)$$, :agb1), 'calc_incomplete');
select partner_calculate(:agb1,'2026-02-01','2026-02-28','{"gross_profit":123}'::jsonb) as c \gset
select tt.chk('B3 with a typed gross profit 123: 40% = 49.20, 60% = 73.80', :'c'::jsonb->>'status'='ok' and tt.amt(:'c'::jsonb,:pa)=49.2 and tt.amt(:'c'::jsonb,:pd)=73.8 and :'c'::jsonb #>> '{sources,gross_profit}'='manual');
select partner_calculate(:agb1,'2026-03-01','2026-03-31') as c \gset
select tt.chk('B4 a month with no books at all: zero, with a note', :'c'::jsonb->>'status'='ok' and (:'c'::jsonb->>'total_distributable')::numeric=0 and tt.warn(:'c'::jsonb,'no_book_rows'));

\echo == drafts: clauses, rule order, activation checks, templates
select partner_agreement_save(null,:v1,'Draft D1','2026-01-01',null,'[{"title_en":"A","text_en":"first"},{"title_en":"B","text_en":"second"},{"title_en":"C","text_en":"third"}]'::jsonb,null,gen_random_uuid()) ->> 'id' as agd \gset
select tt.chk('D1 clauses are numbered 1..3', (select clauses->2->>'no' from partner_agreements where id=:agd)='3');
select partner_agreement_save(:agd,:v1,'Draft D1','2026-01-01',null,'[{"title_en":"C","text_en":"third"},{"title_en":"A","text_en":"first"},{"title_en":"B","text_en":"second"}]'::jsonb,null) is not null as x \gset
select tt.chk('D1 clauses reordered: C, A, B and renumbered', (select clauses->0->>'title_en' from partner_agreements where id=:agd)='C' and (select clauses->2->>'title_en' from partner_agreements where id=:agd)='B' and (select clauses->0->>'no' from partner_agreements where id=:agd)='1');
select tt.err('D1 too many characters in a clause refused', format($$select partner_agreement_save(%s,%s,'t','2026-01-01',null,jsonb_build_array(jsonb_build_object('text_en',repeat('x',20001))),null)$$, :agd, :v1), 'bad_clauses');
select tt.err('D2 activation needs parties', format($$select partner_agreement_activate(%s)$$, :agd), 'no_parties');
select partner_agreement_party_set(:agd,:pa,'owner',50,'n') is not null as x \gset
select tt.err('D2 activation needs rules', format($$select partner_agreement_activate(%s)$$, :agd), 'no_rules');
select partner_rule_save(:agd,null,'Split first','split','{"shares":[{"role":"owner","percent":100}]}') is not null as x \gset
select tt.err('D2 the first step must be the base', format($$select partner_agreement_activate(%s)$$, :agd), 'base_step_first');
select partner_rule_save(:agd,null,'Base','base','{"base":"manual"}') is not null as x \gset
select partner_rules_reorder(:agd,'[2,1]'::jsonb) is not null as x \gset
select tt.chk('D3 rules reordered: Base is step 1, Split step 2', (select name from partner_rules where agreement_id=:agd and step_no=1)='Base' and (select kind from partner_rules where agreement_id=:agd and step_no=2)='split');
select tt.err('D3 an incomplete order is refused', format($$select partner_rules_reorder(%s,'[1]'::jsonb)$$, :agd), 'bad_order');
select partner_rule_save(:agd,2,'Split to a partner nobody holds','split','{"shares":[{"role":"partner","percent":100}]}') is not null as x \gset
select tt.err('D4 a role nobody holds cannot go live', format($$select partner_agreement_activate(%s)$$, :agd), 'party_unresolved');
select partner_rule_save(:agd,2,'Split','split','{"shares":[{"role":"owner","percent":100}]}') is not null as x \gset
select tt.chk('D4 a rule can be retired (active=false), not deleted', (partner_rule_save(:agd,2,'Split','split','{"shares":[{"role":"owner","percent":100}]}',false) ->> 'active')='false' and (select count(*) from partner_rules where agreement_id=:agd)=2);
select partner_rule_save(:agd,2,'Split','split','{"shares":[{"role":"owner","percent":100}]}',true) is not null as x \gset
select partner_agreement_save(null,:v1,'No dates',null,null,'[]'::jsonb,null,gen_random_uuid()) ->> 'id' as agnd \gset
select tt.err('D5 a deed needs an effective date', format($$select partner_agreement_activate(%s)$$, :agnd), 'dates_required');
select partner_agreement_from_template(:v1,'franchise',null,gen_random_uuid()) ->> 'id' as agtp \gset
select tt.chk('D6 template -> draft deed marked EXAMPLE with 4 rules', (select is_example from partner_agreements where id=:agtp) and (select count(*) from partner_rules where agreement_id=:agtp)=4 and (select status from partner_agreements where id=:agtp)='draft' and (select title from partner_agreements where id=:agtp) like 'EXAMPLE%');
select partner_agreement_save(:agtp,:v1,'Franchise of Fay','2026-01-01',null,(select clauses from partner_agreements where id=:agtp),null) is not null as x \gset
select partner_agreement_party_set(:agtp,:pa,'owner',null,null) is not null as x \gset
select partner_agreement_party_set(:agtp,:pd,'franchisee',null,null) is not null as x \gset
select tt.err('D6 example numbers must be confirmed by the owner before going live', format($$select partner_agreement_activate(%s)$$, :agtp), 'example_numbers_not_confirmed');
select partner_calculate(:agtp,'2026-01-01','2026-01-31','{"net_sales":400000,"net_profit_before_fees":90000}'::jsonb) as c \gset
select tt.chk('D6 the template works end to end (a draft can be trial-calculated): owner 30000, franchisee 60000', tt.amt(:'c'::jsonb,:pa)=30000 and tt.amt(:'c'::jsonb,:pd)=60000);
select partner_agreement_activate(:agtp, true) ->> 'status' as st \gset
select tt.chk('D6 activated after confirming', :'st'='active');
select tt.err('D6 unknown template', format($$select partner_agreement_from_template(%s,'nope')$$, :v1), 'template_not_found');

\echo == immutability and amendment revisions
select tt.mk(:v1, 'Amend AM', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"partner"}]', :pa, :pc)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Split","k":"split","c":{"shares":[{"role":"owner","percent":50},{"role":"partner","percent":50}]}}]'::jsonb) as agam \gset
select partner_settlement_save(:agam,'2026-01-01','2026-01-31','{"net_profit_before_fees":1000}'::jsonb,null,gen_random_uuid()) is not null as x \gset
select tt.err('I1 a rule cannot be added to a live deed', format($$select partner_rule_save(%s,null,'x','rounding','{"to":10}')$$, :agam), 'agreement_immutable');
select tt.err('I1 a rule cannot be edited in a live deed', format($$select partner_rule_save(%s,2,'x','split','{"shares":[{"role":"owner","percent":100}]}')$$, :agam), 'agreement_immutable');
select tt.err('I1 rules cannot be reordered in a live deed', format($$select partner_rules_reorder(%s,'[2,1]'::jsonb)$$, :agam), 'agreement_immutable');
select tt.err('I1 parties cannot change in a live deed', format($$select partner_agreement_party_set(%s,%s,'investor',null,null)$$, :agam, :pb), 'agreement_immutable');
select partner_agreement_save(:agam,:v1,'HACKED TITLE','2030-01-01',null,'[{"title_en":"new"}]'::jsonb,'docs/signed.pdf') ->> 'signed_doc_path' as sd \gset
select tt.chk('I1 saving a live deed changes only the signed-paper scan, never title/dates/clauses', :'sd'='docs/signed.pdf' and (select title from partner_agreements where id=:agam)='Amend AM' and (select effective_from from partner_agreements where id=:agam)='2026-01-01' and (select clauses from partner_agreements where id=:agam)='[]'::jsonb);
reset role;
select tt.err('I2 even the DB owner cannot rewrite a live deed title', format($$update partner_agreements set title='x' where id=%s$$, :agam), 'agreement_immutable');
select tt.err('I2 ... nor its clauses', format($$update partner_agreements set clauses='[{"a":1}]'::jsonb where id=%s$$, :agam), 'agreement_immutable');
select tt.err('I2 ... nor a rule inside it', format($$update partner_rules set config='{"base":"net_sales"}'::jsonb where agreement_id=%s and step_no=1$$, :agam), 'agreement_immutable');
select tt.err('I2 ... nor delete a rule', format($$delete from partner_rules where agreement_id=%s$$, :agam), 'append_only');
select tt.err('I2 ... nor delete the deed', format($$delete from partner_agreements where id=%s$$, :agam), 'append_only');
set role authenticated; select tt.as(:'o');
select partner_agreement_amend(:agam, gen_random_uuid()) ->> 'id' as agam2 \gset
select tt.chk('I3 amendment = a NEW draft revision (v2) that supersedes the old one, rules copied', (select version from partner_agreements where id=:agam2)=2 and (select supersedes_id from partner_agreements where id=:agam2)=:agam and (select status from partner_agreements where id=:agam2)='draft' and (select count(*) from partner_rules where agreement_id=:agam2)=2);
select tt.err('I3 one open amendment at a time', format($$select partner_agreement_amend(%s)$$, :agam), 'draft_exists');
select partner_rule_save(:agam2,2,'Split 60/40','split','{"shares":[{"role":"owner","percent":60},{"role":"partner","percent":40}]}') is not null as x \gset
select tt.chk('I3 the old revision is untouched (still 50/50)', (select config->'shares'->0->>'percent' from partner_rules where agreement_id=:agam and step_no=2)='50');
select partner_agreement_save(:agam2,:v1,'Amend AM v2','2026-01-15',null,'[]'::jsonb,null) is not null as x \gset
select tt.err('I4 a revision cannot start inside a period already settled', format($$select partner_agreement_activate(%s)$$, :agam2), 'period_already_settled');
select partner_agreement_save(:agam2,:v1,'Amend AM v2','2026-02-01',null,'[]'::jsonb,null) is not null as x \gset
select partner_agreement_activate(:agam2) ->> 'status' as st \gset
select tt.chk('I4 activating v2 retires v1: status amended, ends the day before', :'st'='active' and (select status from partner_agreements where id=:agam)='amended' and (select effective_to from partner_agreements where id=:agam)='2026-01-31');
select tt.chk('I4 the old revision stays readable (settlement + rules)', (select count(*) from partner_rules where agreement_id=:agam)=2 and (select count(*) from partner_settlements where agreement_id=:agam)=1);
select tt.err('I5 the old revision takes no new settlement', format($$select partner_settlement_save(%s,'2026-02-01','2026-02-28','{"net_profit_before_fees":1}'::jsonb,null,gen_random_uuid())$$, :agam), 'not_active');
select tt.err('I5 the new revision takes none before its start', format($$select partner_settlement_save(%s,'2026-01-01','2026-01-31','{"net_profit_before_fees":1}'::jsonb,null,gen_random_uuid())$$, :agam2), 'outside_deed_dates');
select partner_calculate(:agam2,'2026-02-01','2026-02-28','{"net_profit_before_fees":1000}'::jsonb) as c \gset
select tt.chk('I5 v2 shares 60/40', tt.amt(:'c'::jsonb,:pa)=600 and tt.amt(:'c'::jsonb,:pc)=400);
select partner_settlement_save(:agam2,'2026-02-01','2026-02-28','{"net_profit_before_fees":1000}'::jsonb,null,gen_random_uuid()) is not null as x \gset
select tt.err('I5 overlap is checked across revisions of the same deed', format($$select partner_settlement_save(%s,'2026-02-01','2026-02-28','{"net_profit_before_fees":1}'::jsonb,null,gen_random_uuid())$$, :agam2), 'period_overlap');
select tt.err('I5 only an active deed can be amended', format($$select partner_agreement_amend(%s)$$, :agam), 'not_active');
select partner_agreement_close(:agam2,'deal ended','2026-03-31') ->> 'status' as st \gset
select tt.chk('I6 closing a deed fixes its end date', :'st'='closed' and (select effective_to from partner_agreements where id=:agam2)='2026-03-31');
select tt.err('I6 a closed deed takes no capital', format($$select partner_capital_add(%s,%s,'contribution',10,'2026-03-01','cash',null,null)$$, :agam2, :pa), 'not_active');

\echo == capital ledger
select tt.mk(:v1, 'Capital CAP', '2026-01-01', format('[{"p":%s,"r":"owner"},{"p":%s,"r":"investor"}]', :pa, :pb)::jsonb,
  '[{"n":"Base","k":"base","c":{"base":"net_profit_before_fees"}},{"n":"Rest","k":"split","c":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb) as agcap \gset
select partner_capital_add(:agcap,:pb,'contribution',5000,'2026-01-01','cash','seed',null,gen_random_uuid()) ->> 'id' as k1 \gset
select partner_capital_add(:agcap,:pb,'loan_in',2000,'2026-01-05','bank','loan',null,gen_random_uuid()) is not null as x \gset
select partner_capital_add(:agcap,:pb,'return_of_capital',1000,'2026-01-10','cash','back',null,gen_random_uuid()) ->> 'id' as k3 \gset
select partner_capital_add(:agcap,:pb,'loan_repayment',500,'2026-01-12','mobile','repay',null,gen_random_uuid()) is not null as x \gset
select partner_capital_add(:agcap,:pa,'owner_drawing',300,'2026-01-15','cash','drawing',null,gen_random_uuid()) is not null as x \gset
select tt.chk('C1 investor capital = 5000 + 2000 - 1000 - 500 = 5500; drawings do not touch it', public.partner_capital_balances(:agcap) is not null
  and (select (e->>'balance')::numeric from jsonb_array_elements(partner_capital_balances(:agcap)) e where (e->>'party_id')::bigint=:pb)=5500
  and (select (e->>'drawings')::numeric from jsonb_array_elements(partner_capital_balances(:agcap)) e where (e->>'party_id')::bigint=:pa)=300);
select tt.chk('C1 outstanding payback follows the capital (5500)', (select (e->>'outstanding_payback')::numeric from jsonb_array_elements(partner_capital_balances(:agcap)) e where (e->>'party_id')::bigint=:pb)=5500);
select tt.chk('C1 a balance as of an earlier day (2026-01-04) is 5000', (select (e->>'balance')::numeric from jsonb_array_elements(partner_capital_balances(:agcap,'2026-01-04')) e where (e->>'party_id')::bigint=:pb)=5000);
select tt.err('C2 returning more than the balance is refused', format($$select partner_capital_add(%s,%s,'return_of_capital',9000,'2026-01-20','cash',null,null)$$, :agcap, :pb), 'exceeds_capital');
select tt.err('C2 a future date is refused', format($$select partner_capital_add(%s,%s,'contribution',10,current_date+3,'cash',null,null)$$, :agcap, :pb), 'bad_date');
select tt.err('C2 zero / negative amount refused', format($$select partner_capital_add(%s,%s,'contribution',-5,'2026-01-20','cash',null,null)$$, :agcap, :pb), 'bad_amount');
select tt.err('C2 absurd amount refused', format($$select partner_capital_add(%s,%s,'contribution',1e13,'2026-01-20','cash',null,null)$$, :agcap, :pb), 'bad_amount');
select tt.err('C2 a party outside the deed is refused', format($$select partner_capital_add(%s,%s,'contribution',10,'2026-01-20','cash',null,null)$$, :agcap, :pd), 'party_not_in_deed');
select tt.err('C2 a draft deed takes no capital', format($$select partner_capital_add(%s,%s,'contribution',10,'2026-01-20','cash',null,null)$$, :agd, :pa), 'not_active');
select tt.err('C2 bad kind refused', format($$select partner_capital_add(%s,%s,'gift',10,'2026-01-20','cash',null,null)$$, :agcap, :pb), 'bad_kind');
select gen_random_uuid() as ck \gset
select partner_capital_add(:agcap,:pb,'contribution',100,'2026-01-21','cash',null,null,:'ck') ->> 'id' as ca \gset
select partner_capital_add(:agcap,:pb,'contribution',100,'2026-01-21','cash',null,null,:'ck') ->> 'id' as cb \gset
select tt.chk('C3 same client key = one row', :'ca'=:'cb' and (select count(*) from partner_capital where client_id=:'ck')=1);
select tt.err('C4 void needs a reason', format($$select partner_capital_void(%s,'')$$, :k3), 'reason_required');
select partner_capital_void(:k3,'entered twice') ->> 'status' as vs \gset
select tt.chk('C4 voided return: capital back up by 1000 (5500 + 1000 + the later 100 = 6600)', :'vs'='void' and (select (e->>'balance')::numeric from jsonb_array_elements(partner_capital_balances(:agcap)) e where (e->>'party_id')::bigint=:pb)=6600);
select tt.chk('C4 voiding twice is harmless', (partner_capital_void(:k3,'again') ->> 'status')='void' and (select count(*) from partner_capital where agreement_id=:agcap)=6);
reset role;
select tt.err('C5 a capital row amount cannot be edited', format($$update partner_capital set amount=1 where id=%s$$, :k1), 'append_only');
select tt.err('C5 a capital row cannot be deleted', format($$delete from partner_capital where id=%s$$, :k1), 'append_only');
select tt.err('C5 a void row cannot be revived', format($$update partner_capital set status='posted' where id=%s$$, :k3), 'append_only');
select tt.err('C5 payments cannot be edited', $$update partner_settlement_payments set amount=1$$, 'append_only');
select tt.err('C5 payments cannot be deleted', $$delete from partner_settlement_payments$$, 'append_only');

\echo == audit and owner-only after the fact
select tt.chk('A1 changes are audited', (select count(*) from audit_log where table_name='partner_capital')>=7 and (select count(*) from audit_log where table_name='partner_settlements')>=5 and (select count(*) from audit_log where table_name='partner_agreements')>=5);
set role authenticated; select tt.as(:'s');
select tt.chk('A2 a manager sees no capital, settlement, line, payment, rule or deed', (select count(*) from partner_capital)=0 and (select count(*) from partner_settlements)=0 and (select count(*) from partner_settlement_lines)=0
  and (select count(*) from partner_settlement_payments)=0 and (select count(*) from partner_rules)=0 and (select count(*) from partner_agreements)=0 and (select count(*) from agreement_parties)=0 and (select count(*) from partner_ventures)=0);
select tt.err('A2 a manager cannot pay a line', $$select partner_settlement_pay(1,1,'cash','2026-02-05',null)$$, 'not allowed');
select tt.err('A2 a manager cannot approve', $$select partner_settlement_approve(1)$$, 'not allowed');
select tt.err('A2 a manager cannot record capital', $$select partner_capital_add(1,1,'contribution',1,'2026-02-05','cash',null,null)$$, 'not allowed');
select tt.err('A2 a manager cannot amend or activate', $$select partner_agreement_activate(1)$$, 'not allowed');
select tt.err('A2 a manager cannot write directly', $$insert into partner_parties (name) values ('x')$$, 'permission denied');
reset role;
\echo == RESULT
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
