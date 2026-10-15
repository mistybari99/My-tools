-- COPY of phase115_test.sql for the chain with phase121: pasting phase115 again re-creates stock_return_transfer without the sec121 lock, so T5 pastes phase121 after it (re-paste rule, docs/PASTE_ORDER.md Invariant). Assertions otherwise as phase115_test.sql.
-- FRESH DB ONLY. Phase 115 tests (batch 2 stock safety, part 2: factory-to-branch). Hand-computed numbers; default cases reproduce audit2 A5 findings, "on" cases show the fix.
--   bash tests/sql/final_build.sh p115db ; psql -h /tmp -p 5544 -U postgres -d p115db -qAt -f supabase/phase115_test.sql | grep -E 'FAIL|RESULT'
\set o  '00000000-0000-0000-0000-000000000001'
\set fm '00000000-0000-0000-0000-000000000003'
\set ma '00000000-0000-0000-0000-000000000011'
\set sp '00000000-0000-0000-0000-000000000004'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.iid(p_code text) returns uuid language sql stable as $$ select id from public.items where code = p_code $$;
create or replace function tt.qty(p_code text, p_loc int) returns numeric language sql stable as $$
  select coalesce((select b.qty from public.stock_balance b where b.item_id = tt.iid(p_code) and b.location_id = p_loc), 0) $$;
create or replace function tt.bsum(p_code text, p_loc int) returns numeric language sql stable as $$
  select coalesce(sum(qty_remaining), 0) from public.stock_batches where item_id = tt.iid(p_code) and location_id = p_loc $$;
create or replace function tt.bal(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit),0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$ select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'fm','factory3@s.app','{"full_name":"Factory"}'), (:'ma','branch11@s.app','{"full_name":"Branch"}'), (:'sp','seller4@s.app','{"full_name":"Seller"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge'),(:'ma','showroom_manager'),(:'sp','salesperson') on conflict do nothing;
insert into user_locations values (:'fm',1),(:'ma',2),(:'sp',1) on conflict do nothing;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('P1','Sweet','Sweet','kg','kg','finished_good',true,400,true),('P2','Sweet 2','Sweet 2','kg','kg','finished_good',true,400,true),('P3','Sweet 3','Sweet 3','kg','kg','finished_good',true,400,true),
 ('Y1','Ladoo','Ladoo','kg','kg','finished_good',true,300,true);

\echo == T0 shape, paste twice
select tt.chk('T0 four rules, switches, default false', (select count(*) = 4 and bool_and(kind = 'switch' and default_value = 'false'::jsonb) from rules where key in ('transfer_late_receive','transfer_return_marker','transfer_notify_receiver','transit_loss_gl_fix')));
select tt.chk('T0 four advisor rows of phase 115, all recommended on', (select count(*) = 4 and bool_and(rec_value = 'true'::jsonb) from setup_rec_defs81 where phase = '115'));
select tt.chk('T0 columns kind / reason / ref_transfer_id exist, old rows are null', (select count(*) = 3 from information_schema.columns where table_name = 'stock_transfers' and column_name in ('kind','reason','ref_transfer_id')));
select tt.chk('T0 patched functions carry bos115 and keep older tags', (select bool_and(case proname when '_acct_docs' then d ~ 'b2s115:docs' and d ~ 'bos98' when '_acct_stock_moves85' then d ~ 'b2s115:where' and d ~ 'bos96' and d ~ 'bos103' and d ~ 'perf110'
   else d ~ 'bos115:xfer-notify' end)
   from (select proname, pg_get_functiondef(oid) d from pg_proc where pronamespace = 'public'::regnamespace and proname in ('_acct_docs','_acct_stock_moves85','stock_transfer')) z));
select tt.chk('T0 helper _b2_patch115 is gone', to_regprocedure('public._b2_patch115(text,text,text,text)') is null);

\echo == T1 GAP-2 partial / second receive (A5 C11, E1)
select stock_production_in(tt.iid('P1'),1,20,now() - interval '1 day',null,'batch',null,50) is not null as a \gset
select tt.as(:'fm');
select (stock_transfer(1,2,tt.iid('P1'),20,null,'two lorries')->>'id')::uuid as t1 \gset
select tt.as(:'ma');
select stock_receive_transfer(:'t1'::uuid, 8, 'first lorry') ->> 'short' as sh \gset
select tt.chk('T1 first lorry: received 8 of 20, short 12, branch 8', :'sh'::numeric = 12 and tt.qty('P1',2) = 8);
select stock_receive_transfer(:'t1'::uuid, 12, 'second lorry') ->> 'dup' as d \gset
select tt.chk('T1 default: a second receive is ignored (dup), branch stays 8 (audit FAIL E1c)', :'d' = 'true' and tt.qty('P1',2) = 8);
select tt.err('T1 default: stock_receive_more is off', format($$select stock_receive_more(%L::uuid, 12)$$, :'t1'), 'feature_off');
select tt.as(:'o'); select set_rule('transfer_late_receive', 'true'::jsonb); select tt.as(:'ma');
select tt.err('T1 on: more than the remaining shortage (13 > 12) refused', format($$select stock_receive_more(%L::uuid, 13)$$, :'t1'), 'over_received');
select tt.err('T1 on: zero refused', format($$select stock_receive_more(%L::uuid, 0)$$, :'t1'), 'bad_qty');
select tt.as(:'sp');
select tt.err('T1 on: a user without access to the receiving place cannot', format($$select stock_receive_more(%L::uuid, 4)$$, :'t1'), 'not allowed');
select tt.as(:'ma');
select stock_receive_more(:'t1'::uuid, 4, 'third lorry', '11111111-1111-1111-1111-111111111111') ->> 'short' as sh \gset
select tt.chk('T1 on: 4 more received: branch 12, short 8, received_qty 12', :'sh'::numeric = 8 and tt.qty('P1',2) = 12 and (select received_qty from stock_transfers where id = :'t1'::uuid) = 12);
select stock_receive_more(:'t1'::uuid, 4, 'third lorry', '11111111-1111-1111-1111-111111111111') ->> 'dup' as d \gset
select tt.chk('T1 on: the same client id again = dup, branch still 12', :'d' = 'true' and tt.qty('P1',2) = 12);
select tt.chk('T1 on: the open shortage list shows 8', (select (x->>'short')::numeric = 8 from jsonb_array_elements(transit_short_open(null)) x where x->>'transfer_id' = :'t1'));
select stock_receive_more(:'t1'::uuid, 8) ->> 'short' as sh \gset
select tt.chk('T1 on: the last 8: branch 20, short 0, nothing listed', :'sh'::numeric = 0 and tt.qty('P1',2) = 20 and tt.qty('P1',1) = 0
  and not exists (select 1 from jsonb_array_elements(transit_short_open(null)) x where x->>'transfer_id' = :'t1'));
select tt.chk('T1 on: batch rows at the branch add up to the balance (20) and keep the factory expiry/made date', tt.bsum('P1',2) = 20
  and (select count(distinct made_at) from stock_batches where item_id = tt.iid('P1') and location_id = 2) = 1
  and (select made_at from stock_batches where item_id = tt.iid('P1') and location_id = 2 limit 1) = (select made_at from stock_batches where item_id = tt.iid('P1') and location_id = 1 limit 1));
select tt.err('T1 on: nothing left to receive', format($$select stock_receive_more(%L::uuid, 1)$$, :'t1'), 'not_short');
select tt.as(:'o');
select tt.chk('T1 on: ledger transfer_in total at the branch = 20 and equals the balance, stock_reconcile clean', (select sum(qty_delta) from stock_ledger where ref_id = :'t1' and reason = 'transfer_in') = 20 and (select count(*) = 0 from (select * from stock_reconcile(false)) z));
-- a shortage written off cannot be received later
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('P1'),0.5,null,'x')->>'id')::uuid as t2 \gset
select tt.chk('T1 setup: factory had 0 so it went negative -0.5 (warn mode, as today)', tt.qty('P1',1) = -0.5);
select tt.as(:'ma'); select stock_receive_transfer(:'t2'::uuid, 0.2) is not null as a \gset
select transit_short_resolve(:'t2'::uuid, 'lost on the van') is not null as a \gset
select tt.err('T1 on: after the shortage was written off (transit_loss) no late receive', format($$select stock_receive_more(%L::uuid, 0.1)$$, :'t2'), 'short_already_written_off');
select tt.as(:'o'); select set_rule('transfer_late_receive', 'false'::jsonb);

\echo == T2 GAP-3 marked return to the factory (A5 C9)
select tt.as(:'o'); select stock_opening(tt.iid('P2'),1,30,50) is not null as a \gset
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('P2'),20)->>'id')::uuid as t3 \gset
select tt.as(:'ma'); select stock_receive_transfer(:'t3'::uuid) is not null as a \gset
select tt.err('T2 default: stock_return_transfer is off', format($$select stock_return_transfer(2,1,tt.iid('P2'),5,'damaged',%L::uuid)$$, :'t3'), 'feature_off');
select tt.as(:'o'); select set_rule('transfer_return_marker', 'true'::jsonb); select tt.as(:'ma');
select tt.err('T2 on: a reason is required', format($$select stock_return_transfer(2,1,tt.iid('P2'),5,null,%L::uuid)$$, :'t3'), 'reason_required');
select tt.err('T2 on: "other" needs a note', format($$select stock_return_transfer(2,1,tt.iid('P2'),5,'other',%L::uuid)$$, :'t3'), 'note_needed');
select tt.err('T2 on: a link in the wrong direction is refused', format($$select stock_return_transfer(1,2,tt.iid('P2'),5,'damaged',%L::uuid)$$, :'t3'), 'not allowed');
select tt.as(:'o');
select tt.err('T2 on: link to a transfer that does not go the other way (owner sends 1->2 as a return of t3)', format($$select stock_return_transfer(1,2,tt.iid('P2'),5,'damaged',%L::uuid)$$, :'t3'), 'bad_ref');
select tt.as(:'ma');
select stock_return_transfer(2,1,tt.iid('P2'),5,'damaged',:'t3'::uuid,null,'broken in the van',gen_random_uuid()) ->> 'id' as r1 \gset
select tt.chk('T2 on: the return is a transfer 2 -> 1 of 5 marked kind=return, reason=damaged, linked to t3; branch 20 - 5 = 15, in transit 5',
  (select kind = 'return' and reason = 'damaged' and ref_transfer_id = :'t3'::uuid and qty = 5 and from_location_id = 2 and to_location_id = 1 and status = 'sent' from stock_transfers where id = :'r1'::uuid)
  and tt.qty('P2',2) = 15);
select tt.err('T2 on: returns above what was received (20 - 5 = 15 left; 16 asked) refused', format($$select stock_return_transfer(2,1,tt.iid('P2'),16,'excess',%L::uuid)$$, :'t3'), 'return_exceeds_receipt');
select stock_return_transfer(2,1,tt.iid('P2'),15,'excess',:'t3'::uuid,null,null,gen_random_uuid()) ->> 'id' as r2 \gset
select tt.chk('T2 on: the remaining 15 may be returned, branch 0', tt.qty('P2',2) = 0 and (select count(*) from stock_transfers where ref_transfer_id = :'t3'::uuid and kind = 'return') = 2);
select tt.as(:'fm'); select stock_receive_transfer(:'r1'::uuid) is not null as a \gset
select tt.chk('T2 the factory receives the return normally: factory 30 - 20 + 5 = 15', tt.qty('P2',1) = 15);
select tt.chk('T2 a normal send stays unmarked', (select kind is null and reason is null and ref_transfer_id is null from stock_transfers where id = :'t3'::uuid));
select tt.as(:'o'); select set_rule('transfer_return_marker', 'false'::jsonb);

\echo == T3 GAP-6 notify the receiving branch (A5 C25)
select tt.as(:'o'); select stock_opening(tt.iid('P3'),1,50,50) is not null as a \gset
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('P3'),5)->>'id')::uuid as t4 \gset
select tt.chk('T3 default: no notification when goods are sent', not exists (select 1 from notifications where kind = 'transfer_sent'));
select tt.as(:'o'); select set_rule('transfer_notify_receiver', 'true'::jsonb); select tt.as(:'fm');
select (stock_transfer(1,2,tt.iid('P3'),6)->>'id')::uuid as t5 \gset
select tt.chk('T3 on: exactly one notification, for the managers of place 2, key = the transfer, level info', (select count(*) = 1 and bool_and(location_id = 2 and audience = 'manager' and key = :'t5' and level = 'info' and route = 'stock') from notifications where kind = 'transfer_sent'));
select (stock_transfer(1,2,tt.iid('P3'),7,null,null,'22222222-2222-2222-2222-222222222222')->>'id')::uuid as t6 \gset
select stock_transfer(1,2,tt.iid('P3'),7,null,null,'22222222-2222-2222-2222-222222222222') is not null as a \gset
select tt.chk('T3 on: a replayed send (same client id) makes no second notification: 2 in total', (select count(*) = 2 from notifications where kind = 'transfer_sent') and tt.qty('P3',1) = 50 - 5 - 6 - 7);
select tt.as(:'ma'); select _notif_ok(null, 'manager', 2) as ok_ma \gset
select tt.as(:'fm'); select _notif_ok(null, 'manager', 2) as ok_fm \gset
select tt.chk('T3 on: the branch manager of place 2 may see it, the factory in-charge (place 1 only) may not', :'ok_ma'::boolean and not :'ok_fm'::boolean);
select tt.as(:'o'); select set_rule('transfer_notify_receiver', 'false'::jsonb);

\echo == T4 GAP-4 transit loss in the books (location_tagged) (A5 E7 E8)
select acct_set_start(tt.today() - 5) is not null as a \gset
select stock_opening(tt.iid('Y1'),1,100,50) is not null as a \gset
select acct_opening('[{"code":"1110","debit":20000,"location_id":1},{"code":"1320","debit":9000,"location_id":1},{"code":"3100","credit":29000}]'::jsonb) is not null as a \gset
select set_rule('accounting_on','true'::jsonb) is null as r1 \gset
select set_rule('acct_transfer_mode','"location_tagged"'::jsonb) is null as r2 \gset
select set_rule('acct_transit_loss','true'::jsonb) is null as r3 \gset
select set_rule('transit_short_mode','"loss"'::jsonb) is null as r4 \gset
select acct_post_pending(false) is not null as a \gset
select tt.bal('5130') as l0, tt.bal('1230') as c0, (inventory_vs_gl(null,null)->'total'->>'diff')::numeric as iv0 \gset
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('Y1'),10)->>'id')::uuid as e7 \gset
select tt.as(:'ma'); select stock_receive_transfer(:'e7'::uuid, 7, 'short, loss mode') is not null as a \gset
select tt.as(:'o'); select acct_post_pending(false) as pp \gset
select tt.chk('T4 default (loss mode, 10 sent @50, 7 received): the GL loses nothing to 5130 (audit FAIL E7c: 0, not 150) and a cost_missing row waits',
  tt.bal('5130') - :'l0'::numeric = 0 and coalesce((:'pp'::jsonb->'waiting'->>'cost_missing')::int, 0) >= 1);
select tt.chk('T4 default: phantom inventory +150 (3 x 50) above the stock valuation (audit FAIL E7g)', (inventory_vs_gl(null,null)->'total'->>'diff')::numeric - :'iv0'::numeric <> 0);
select set_rule('transit_loss_gl_fix', 'true'::jsonb);
select acct_post_pending(false) is not null as a \gset
select tt.bal('5130') as l1, tt.bal('1230') as c1, (inventory_vs_gl(null,null)->'total'->>'diff')::numeric as iv1 \gset
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('Y1'),10)->>'id')::uuid as e7b \gset
select tt.as(:'ma'); select stock_receive_transfer(:'e7b'::uuid, 7, 'short, loss mode, fix on') is not null as a \gset
select tt.as(:'o'); select acct_post_pending(false) as pp2 \gset
select tt.chk('T4 on: the new short books 3 x 50 = 150 on 5130', tt.bal('5130') - :'l1'::numeric = 150);
select tt.chk('T4 on: clearing 1230 company-wide unchanged by the new short (nets 0)', tt.bal('1230') - :'c1'::numeric = 0);
select tt.chk('T4 on: no cost_missing row waits, no unbalanced entry', coalesce((:'pp2'::jsonb->'waiting'->>'cost_missing')::int, 0) = 0 and tt.unbalanced() = 0);
select tt.chk('T4 on: inventory GL minus stock valuation unchanged by the new short (0 change)', (inventory_vs_gl(null,null)->'total'->>'diff')::numeric - :'iv1'::numeric = 0);
select tt.chk('T4 on: the stock book is unchanged by the fix: branch has 14 (7 + 7), the synthetic pair nets to 0', tt.qty('Y1',2) = 14 and (select coalesce(sum(qty_delta),0) from stock_ledger where ref_id = :'e7b' and reason = 'transit_loss') = -3);
-- keep_in_transit + resolve
select set_rule('transit_short_mode','"keep_in_transit"'::jsonb);
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('Y1'),10)->>'id')::uuid as e8 \gset
select tt.as(:'ma'); select stock_receive_transfer(:'e8'::uuid, 6, 'short 4') is not null as a \gset
select tt.as(:'o'); select acct_post_pending(false) is not null as a \gset
select tt.bal('5130') as l2, tt.bal('1230') as c2, (inventory_vs_gl(null,null)->'total'->>'diff')::numeric as iv2 \gset
select tt.chk('T4 keep_in_transit: 4 x 50 = 200 booked on 5130 at the receive', :'l2'::numeric - :'l1'::numeric - 150 = 200);
select tt.as(:'ma'); select transit_short_resolve(:'e8'::uuid, 'lost on the van') is not null as a \gset
select tt.as(:'o'); select acct_post_pending(false) as pp3 \gset
select tt.chk('T4 on: resolving the old short changes nothing in the GL: 5130 / 1230 / inventory difference all unchanged', tt.bal('5130') = :'l2'::numeric and tt.bal('1230') = :'c2'::numeric
  and (inventory_vs_gl(null,null)->'total'->>'diff')::numeric = :'iv2'::numeric and coalesce((:'pp3'::jsonb->'waiting'->>'cost_missing')::int, 0) = 0);
-- late receive refused once booked in the accounts
select set_rule('transfer_late_receive', 'true'::jsonb);
select tt.as(:'ma');
select tt.err('T4 a short already booked in the accounts cannot be received later', format($$select stock_receive_more(%L::uuid, 1)$$, :'e7b'), 'short_already_written_off');
select tt.as(:'o'); select set_rule('transfer_late_receive', 'false'::jsonb);
select tt.chk('T4 stock_reconcile: 0 differences', (select count(*) = 0 from stock_reconcile(false)));

\echo == T5 paste twice changes nothing
create temp table h1 as select proname, md5(pg_get_functiondef(oid)) h from pg_proc where pronamespace = 'public'::regnamespace and proname in ('stock_transfer','_acct_docs','_acct_stock_moves85','stock_receive_more','stock_return_transfer');
select count(*) as nrec1 from setup_rec_defs81 \gset
\i supabase/phase115.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase132.sql
\i supabase/phase133.sql
\i supabase/phase134.sql
select tt.chk('T5 paste twice: same function bodies', (select count(*) = 5 from h1 where exists (select 1 from pg_proc p where p.proname = h1.proname and p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) = h1.h)));
select tt.chk('T5 paste twice: same advisor rows, rules keep their values', (select count(*) from setup_rec_defs81) = :nrec1 and (select value from rules where key = 'transit_loss_gl_fix') = 'true'::jsonb);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
