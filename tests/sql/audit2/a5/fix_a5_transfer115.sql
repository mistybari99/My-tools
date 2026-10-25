-- A5 FIX probes (gap closure by phase115: GAP-2 second/partial receive, GAP-3 marked return to the factory, GAP-6 notify the receiving branch;
-- phase118: GAP-1 factory-to-branch statement).  Self-contained scenario with the A5 audit numbers (hand-computed in the HAND comments), derived from
-- supabase/phase115_test.sql T1..T3, own session on a clone of the template DB.  The batch switches are NOT set here: defaults = OFF -> FAIL = gap
-- open by default; switches_on.txt = ON -> PASS = closed.  (GAP-4 is covered by the old E7/E8 probes, which already PASS with the switches on.)
\i tests/sql/e2e/00_common.sql
\set fm '00000000-0000-0000-0000-000000000003'
\set ma '00000000-0000-0000-0000-000000000011'
create or replace function tt.chk(p_name text, p_ok boolean) returns void language sql as $$ select tt.t(p_name, p_ok) $$;
create or replace function tt.bsum(p_code text, p_loc int) returns numeric language sql stable as $$
  select coalesce(sum(qty_remaining), 0) from public.stock_batches where item_id = tt.iid(p_code) and location_id = p_loc $$;
grant execute on all functions in schema tt to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'fm','factory3@s.app','{"full_name":"Factory"}'), (:'ma','branch11@s.app','{"full_name":"Branch"}'), (:'sp','seller4@s.app','{"full_name":"Seller"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge'),(:'ma','showroom_manager'),(:'sp','salesperson') on conflict do nothing;
insert into user_locations values (:'fm',1),(:'ma',2),(:'sp',1) on conflict do nothing;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('P1','Sweet','Sweet','kg','kg','finished_good',true,400,true),('P2','Sweet 2','Sweet 2','kg','kg','finished_good',true,400,true),('P3','Sweet 3','Sweet 3','kg','kg','finished_good',true,400,true),
 ('Y1','Ladoo','Ladoo','kg','kg','finished_good',true,300,true);
\echo == T0 shape, paste twice
\echo == T1 GAP-2 partial / second receive (A5 C11, E1)
select set_rule('transit_short_mode','"keep_in_transit"'::jsonb) is null as fx_mode \gset  -- GAP-2 is about the keep_in_transit mode (in loss mode the short is written off at the receive, so a late receive is refused by design)
select stock_production_in(tt.iid('P1'),1,20,now() - interval '1 day',null,'batch',null,50) is not null as a \gset
select tt.as(:'fm');
select (stock_transfer(1,2,tt.iid('P1'),20,null,'two lorries')->>'id')::uuid as t1 \gset
select tt.as(:'ma');
select stock_receive_transfer(:'t1'::uuid, 8, 'first lorry') ->> 'short' as sh \gset
select tt.chk('FX5-GAP-2 T1 first lorry: received 8 of 20, short 12, branch 8', :'sh'::numeric = 12 and tt.qty('P1',2) = 8);
select tt.as(:'o');  select tt.as(:'ma');
select tt.err('FX5-GAP-2 T1 more than the remaining shortage (13 > 12) refused', format($$select stock_receive_more(%L::uuid, 13)$$, :'t1'), 'over_received');
select tt.err('FX5-GAP-2 T1 zero refused', format($$select stock_receive_more(%L::uuid, 0)$$, :'t1'), 'bad_qty');
select tt.as(:'sp');
select tt.err('FX5-GAP-2 T1 a user without access to the receiving place cannot', format($$select stock_receive_more(%L::uuid, 4)$$, :'t1'), 'not allowed');
select tt.as(:'ma');
select stock_receive_more(:'t1'::uuid, 4, 'third lorry', '11111111-1111-1111-1111-111111111111') ->> 'short' as sh \gset
select tt.chk('FX5-GAP-2 T1 4 more received: branch 12, short 8, received_qty 12', :'sh'::numeric = 8 and tt.qty('P1',2) = 12 and (select received_qty from stock_transfers where id = :'t1'::uuid) = 12);
select stock_receive_more(:'t1'::uuid, 4, 'third lorry', '11111111-1111-1111-1111-111111111111') ->> 'dup' as d \gset
select tt.chk('FX5-GAP-2 T1 the same client id again = dup, branch still 12', :'d' = 'true' and tt.qty('P1',2) = 12);
select tt.chk('FX5-GAP-2 T1 the open shortage list shows 8', (select (x->>'short')::numeric = 8 from jsonb_array_elements(transit_short_open(null)) x where x->>'transfer_id' = :'t1'));
select stock_receive_more(:'t1'::uuid, 8) ->> 'short' as sh \gset
select tt.chk('FX5-GAP-2 T1 the last 8: branch 20, short 0, nothing listed', :'sh'::numeric = 0 and tt.qty('P1',2) = 20 and tt.qty('P1',1) = 0
  and not exists (select 1 from jsonb_array_elements(transit_short_open(null)) x where x->>'transfer_id' = :'t1'));
select tt.chk('FX5-GAP-2 T1 batch rows at the branch add up to the balance (20) and keep the factory expiry/made date', tt.bsum('P1',2) = 20
  and (select count(distinct made_at) from stock_batches where item_id = tt.iid('P1') and location_id = 2) = 1
  and (select made_at from stock_batches where item_id = tt.iid('P1') and location_id = 2 limit 1) = (select made_at from stock_batches where item_id = tt.iid('P1') and location_id = 1 limit 1));
select tt.err('FX5-GAP-2 T1 nothing left to receive', format($$select stock_receive_more(%L::uuid, 1)$$, :'t1'), 'not_short');
select tt.as(:'o');
select tt.chk('FX5-GAP-2 T1 ledger transfer_in total at the branch = 20 and equals the balance, stock_reconcile clean', (select sum(qty_delta) from stock_ledger where ref_id = :'t1' and reason = 'transfer_in') = 20 and (select count(*) = 0 from (select * from stock_reconcile(false)) z));
-- a shortage written off cannot be received later
select tt.as(:'o'); select stock_opening(tt.iid('P1'),1,1,50) is not null as a \gset
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('P1'),0.5,null,'x')->>'id')::uuid as t2 \gset
select tt.chk('FX5-GAP-2 T1 setup: factory had 1, sent 0.5, 0.5 left (hand: the audit sent more than it held; with the stock check ON that is refused, so the shortage case starts from a real 0.5)', tt.qty('P1',1) = 0.5);
select tt.as(:'ma'); select stock_receive_transfer(:'t2'::uuid, 0.2) is not null as a \gset
select transit_short_resolve(:'t2'::uuid, 'lost on the van') is not null as a \gset
select tt.err('FX5-GAP-2 T1 after the shortage was written off (transit_loss) no late receive', format($$select stock_receive_more(%L::uuid, 0.1)$$, :'t2'), 'short_already_written_off');
select tt.as(:'o'); 
select set_rule('transit_short_mode',null) is null as fx_mode0 \gset
\echo == T2 GAP-3 marked return to the factory (A5 C9)
select tt.as(:'o'); select stock_opening(tt.iid('P2'),1,30,50) is not null as a \gset
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('P2'),20)->>'id')::uuid as t3 \gset
select tt.as(:'ma'); select stock_receive_transfer(:'t3'::uuid) is not null as a \gset
select tt.as(:'o');  select tt.as(:'ma');
select tt.err('FX5-GAP-3 T2 a reason is required', format($$select stock_return_transfer(2,1,tt.iid('P2'),5,null,%L::uuid)$$, :'t3'), 'reason_required');
select tt.err('FX5-GAP-3 T2 "other" needs a note', format($$select stock_return_transfer(2,1,tt.iid('P2'),5,'other',%L::uuid)$$, :'t3'), 'note_needed');
select tt.err('FX5-GAP-3 T2 a link in the wrong direction is refused', format($$select stock_return_transfer(1,2,tt.iid('P2'),5,'damaged',%L::uuid)$$, :'t3'), 'not allowed');
select tt.as(:'o');
select tt.err('FX5-GAP-3 T2 link to a transfer that does not go the other way (owner sends 1->2 as a return of t3)', format($$select stock_return_transfer(1,2,tt.iid('P2'),5,'damaged',%L::uuid)$$, :'t3'), 'bad_ref');
select tt.as(:'ma');
select stock_return_transfer(2,1,tt.iid('P2'),5,'damaged',:'t3'::uuid,null,'broken in the van',gen_random_uuid()) ->> 'id' as r1 \gset
select tt.chk('FX5-GAP-3 T2 the return is a transfer 2 -> 1 of 5 marked kind=return, reason=damaged, linked to t3; branch 20 - 5 = 15, in transit 5',
  (select kind = 'return' and reason = 'damaged' and ref_transfer_id = :'t3'::uuid and qty = 5 and from_location_id = 2 and to_location_id = 1 and status = 'sent' from stock_transfers where id = :'r1'::uuid)
  and tt.qty('P2',2) = 15);
select tt.err('FX5-GAP-3 T2 returns above what was received (20 - 5 = 15 left; 16 asked) refused', format($$select stock_return_transfer(2,1,tt.iid('P2'),16,'excess',%L::uuid)$$, :'t3'), 'return_exceeds_receipt');
select stock_return_transfer(2,1,tt.iid('P2'),15,'excess',:'t3'::uuid,null,null,gen_random_uuid()) ->> 'id' as r2 \gset
select tt.chk('FX5-GAP-3 T2 the remaining 15 may be returned, branch 0', tt.qty('P2',2) = 0 and (select count(*) from stock_transfers where ref_transfer_id = :'t3'::uuid and kind = 'return') = 2);
select tt.as(:'fm'); select stock_receive_transfer(:'r1'::uuid) is not null as a \gset
select tt.chk('FX5-GAP-3 T2 the factory receives the return normally: factory 30 - 20 + 5 = 15', tt.qty('P2',1) = 15);
select tt.chk('FX5-GAP-3 T2 a normal send stays unmarked', (select kind is null and reason is null and ref_transfer_id is null from stock_transfers where id = :'t3'::uuid));
select tt.as(:'o'); 
\echo == T3 GAP-6 notify the receiving branch (A5 C25)
select tt.as(:'o'); select stock_opening(tt.iid('P3'),1,50,50) is not null as a \gset
select tt.as(:'fm');
select tt.as(:'o');  select tt.as(:'fm');
select (stock_transfer(1,2,tt.iid('P3'),6)->>'id')::uuid as t5 \gset
select tt.chk('FX5-GAP-6 T3 exactly one notification for this transfer, for the managers of place 2, level info (earlier sends of T1/T2 notify too when the switch is on)', (select count(*) = 1 and bool_and(location_id = 2 and audience = 'manager' and level = 'info' and route = 'stock') from notifications where kind = 'transfer_sent' and key = :'t5'));
select (stock_transfer(1,2,tt.iid('P3'),7,null,null,'22222222-2222-2222-2222-222222222222')->>'id')::uuid as t6 \gset
select stock_transfer(1,2,tt.iid('P3'),7,null,null,'22222222-2222-2222-2222-222222222222') is not null as a \gset
select tt.chk('FX5-GAP-6 T3 a replayed send (same client id) makes no second notification: still exactly one for that transfer', (select count(*) = 1 from notifications where kind = 'transfer_sent' and key = :'t6') and tt.qty('P3',1) = 50 - 6 - 7);
select tt.as(:'ma'); select _notif_ok(null, 'manager', 2) as ok_ma \gset
select tt.as(:'fm'); select _notif_ok(null, 'manager', 2) as ok_fm \gset
select tt.chk('FX5-GAP-6 T3 the branch manager of place 2 may see it, the factory in-charge (place 1 only) may not', :'ok_ma'::boolean and not :'ok_fm'::boolean);
select tt.as(:'o'); 
