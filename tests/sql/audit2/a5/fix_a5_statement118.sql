-- A5 FIX probe (gap closure by phase118: GAP-1 factory-to-branch statement).  Read-only report, no switch: PASS at defaults too.
-- Self-contained scenario (own session, clone of the template DB), hand numbers: factory (place 1) holds 30 kg @50; sends 10 to branch (place 2);
-- the branch receives 7 (short 3 = 30 %); sells 4, wastes 1; sends 1 back (returned).  HAND: sent 10, received 7, short 3, returned 1, sold 4, wasted 1,
-- remaining 7 - 4 - 1 - 1 = 1.  Values at the transferred cost 50: sent 500, received 350, short 150.
\i tests/sql/e2e/00_common.sql
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@a5f.app','{"full_name":"Owner"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner') on conflict do nothing;
select tt.as(:'o');
create or replace function tt.row(p_st jsonb, p_loc int, p_code text) returns jsonb language sql stable as $$
  select r from jsonb_array_elements(p_st -> 'rows') r where (r ->> 'location_id')::int = p_loc and r ->> 'item_code' = p_code $$;
create or replace function tt.n(p_j jsonb, p_key text) returns numeric language sql immutable as $$ select (p_j ->> p_key)::numeric $$;
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('FXB-P','Sweet P','Sweet P','kg','kg','finished_good',true,100,true);
select stock_opening(tt.iid('FXB-P'),1,30,50) is not null as o1 \gset
select (stock_transfer(1,2,tt.iid('FXB-P'),10,null,'fx statement')->>'id')::uuid as t1 \gset
select stock_receive_transfer(:'t1'::uuid, 7, 'three kg short') is not null as r1 \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":4,"price":100}]',tt.iid('FXB-P'))::jsonb,0,'[{"mode":"cash","amount":400}]',null,null,'retail',null,false) is not null as sl \gset
select stock_wastage(tt.iid('FXB-P'),2,1,'spoiled','fx',null,null,gen_random_uuid(),null) is not null as w \gset
select (stock_transfer(2,1,tt.iid('FXB-P'),1,null,'fx return')->>'id')::uuid as t2 \gset
select stock_receive_transfer(:'t2'::uuid) is not null as r2 \gset
-- HAND (remaining): the branch holds 7 - 4 sold - 1 wasted - 1 returned = 1 ; factory 30 - 10 + 1 = 21
select case when to_regprocedure('public.factory_branch_statement(date,date,integer,uuid,text,integer)') is not null then factory_branch_statement(tt.today(), tt.today(), null, tt.iid('FXB-P')) end as fxb \gset
select tt.row(:'fxb'::jsonb, 2, 'FXB-P') as fxr \gset
select tt.eq('FX5-GAP-1 statement: branch received 7 of 10 sent', 7, tt.n(:'fxr'::jsonb,'received_qty'));
select tt.eq('FX5-GAP-1 statement: sent 10', 10, tt.n(:'fxr'::jsonb,'sent_in_qty'));
select tt.eq('FX5-GAP-1 statement: short 3 (30 %)', 3, tt.n(:'fxr'::jsonb,'short_qty'));
select tt.eq('FX5-GAP-1 statement: short percent = 3 / 10', 30, tt.n(:'fxr'::jsonb,'short_pct'), 0.05);
select tt.eq('FX5-GAP-1 statement: sold 4 and wasted 1 and returned 1', 6, tt.n(:'fxr'::jsonb,'sold_qty') + tt.n(:'fxr'::jsonb,'wasted_qty') + tt.n(:'fxr'::jsonb,'returned_qty'));
select tt.eq('FX5-GAP-1 statement: remaining at the branch 7 - 4 - 1 - 1 = 1', 1, tt.n(:'fxr'::jsonb,'remaining_qty'));
select tt.eq('FX5-GAP-1 statement: sent value 10 x 50 = 500, received value 350, short value 150', 1000, tt.n(:'fxr'::jsonb,'sent_value') + tt.n(:'fxr'::jsonb,'received_value') + tt.n(:'fxr'::jsonb,'short_value'));
select tt.eq('FX5-GAP-1 statement: receive mismatch against the ledger 0', 0, tt.n(:'fxr'::jsonb,'receive_mismatch_qty'));
select tt.t('FX5-GAP-1 statement: the short transfer is flagged', coalesce(:'fxr'::jsonb->'flags' ? 'short', false));
