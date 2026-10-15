-- A2 FIX probes (gap closure by phase118: G1 stock movement statement, G2 sales-vs-stock check).  The reports are read-only functions with no switch,
-- so these probes PASS at defaults too (the old a2_40 probes looked for report/function NAMES that the fix did not use).
-- Self-contained scenario, own session on a clone of the template DB.  Hand numbers in the comments.  Labels FX2-G1 / FX2-G2.
\i tests/sql/e2e/00_common.sql
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@a2f.app','{"full_name":"Owner"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner') on conflict do nothing;
select tt.as(:'o');
create or replace function tt.row(p_st jsonb, p_loc int, p_code text) returns jsonb language sql stable as $$
  select r from jsonb_array_elements(p_st -> 'rows') r where (r ->> 'location_id')::int = p_loc and r ->> 'item_code' = p_code $$;
create or replace function tt.n(p_j jsonb, p_key text) returns numeric language sql immutable as $$ select (p_j ->> p_key)::numeric $$;
create or replace function tt.fxsale(p_loc int, p_code text, p_qty numeric) returns jsonb language plpgsql as $$
declare amt numeric; l jsonb;
begin select round(p_qty * sell_price, 2) into amt from public.items where code = p_code;
  l := jsonb_build_array(jsonb_build_object('item_id', tt.iid(p_code), 'qty', p_qty));
  return public.record_sale2(gen_random_uuid(), p_loc, l, 0, jsonb_build_array(jsonb_build_object('mode','cash','amount', amt)), null, null, 'retail', null, false, null); end $$;
grant execute on all functions in schema tt to authenticated, anon;
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,category) values
 ('FXS-A','Stmt A','Stmt A','kg','kg','finished_good',true,10,true,'fx'),
 ('FXS-U','Untracked','Untracked','pc','pc','resale',false,10,true,'fx'),
 ('FXS-K','No conversion','No conversion','pc','kg','resale',true,10,true,'fx');
\echo == FX2 scenario: opening 10 @5, production 4, sale 3, wastage 1, count to 9 (all place 1, today)
select stock_opening(tt.iid('FXS-A'),1,10,5) is not null as s0 \gset
select stock_production_in(tt.iid('FXS-A'),1,4) is not null as s1 \gset
select tt.fxsale(1,'FXS-A',3) is not null as s2 \gset
select stock_wastage(tt.iid('FXS-A'),1,1,'spoiled','fx',null,null,gen_random_uuid(),null) is not null as s3 \gset
select stock_count_adjust(tt.iid('FXS-A'),1,9,'count') is not null as s4 \gset
-- HAND: balance 10 + 4 - 3 - 1 = 10, count to 9 = -1 -> 9.  Window today..today: opening 0 ; production 4 ; sales 3 ; wastage 1 ; adjustments +10 (opening row) - 1 (count) = +9 ; closing 0+4-3-1+9 = 9
create temp table fxst as select to_jsonb(r) j from (select case when to_regprocedure('public.stock_recon_statement(date,date,integer,uuid,text,integer)') is not null then stock_recon_statement(tt.today(), tt.today(), 1, tt.iid('FXS-A')) end r_) z, lateral (select z.r_ as r) r;
select tt.row(j, 1, 'FXS-A') as fxr from fxst \gset
select tt.eq('FX2-G1 statement: production 4', 4, tt.n(:'fxr'::jsonb,'production_qty'));
select tt.eq('FX2-G1 statement: sales 3', 3, tt.n(:'fxr'::jsonb,'sales_qty'));
select tt.eq('FX2-G1 statement: wastage 1', 1, tt.n(:'fxr'::jsonb,'wastage_qty'));
select tt.eq('FX2-G1 statement: opening 0 and closing 9', 9, tt.n(:'fxr'::jsonb,'closing_qty') + tt.n(:'fxr'::jsonb,'opening_qty'));
select tt.eq('FX2-G1 statement: identity opening + in - out +/- adjustments = closing (difference 0)', 0,
  tt.n(:'fxr'::jsonb,'opening_qty') + tt.n(:'fxr'::jsonb,'production_qty') + tt.n(:'fxr'::jsonb,'purchases_qty') + tt.n(:'fxr'::jsonb,'transfer_in_qty') + tt.n(:'fxr'::jsonb,'give_back_qty')
  - tt.n(:'fxr'::jsonb,'used_qty') - tt.n(:'fxr'::jsonb,'sales_qty') - tt.n(:'fxr'::jsonb,'wastage_qty') - tt.n(:'fxr'::jsonb,'transit_loss_qty') - tt.n(:'fxr'::jsonb,'transfer_out_qty') + tt.n(:'fxr'::jsonb,'adjustments_qty') - tt.n(:'fxr'::jsonb,'closing_qty'));
select tt.eq('FX2-G1 statement: ledger total equals the cached balance (variance 0)', 0, tt.n(:'fxr'::jsonb,'variance_qty'));
select case when to_regprocedure('public.stock_recon_statement(date,date,integer,uuid,text,integer)') is not null then stock_recon_statement(tt.today()+1, tt.today()+2, 1, tt.iid('FXS-A')) end as fxf \gset
select tt.eq('FX2-G1 statement of a later window: opening = 9 = closing, no movement', 9, tt.n(tt.row(:'fxf'::jsonb,1,'FXS-A'),'opening_qty') + 0 * tt.n(tt.row(:'fxf'::jsonb,1,'FXS-A'),'closing_qty'));
-- a cached balance that no longer equals the ledger (tampered +1) must be flagged
update stock_balance set qty = qty + 1 where item_id = tt.iid('FXS-A') and location_id = 1;
select case when to_regprocedure('public.stock_recon_statement(date,date,integer,uuid,text,integer)') is not null then stock_recon_statement(tt.today(), tt.today(), 1, tt.iid('FXS-A')) end as fxt \gset
select tt.t('FX2-G1 statement: a balance tampered by +1 shows a variance flag of 1', abs(coalesce(tt.n(tt.row(:'fxt'::jsonb,1,'FXS-A'),'variance_qty'),0)) = 1 and jsonb_array_length(tt.row(:'fxt'::jsonb,1,'FXS-A')->'flags') > 0);
select stock_reconcile(true) is not null as fxfix \gset
\echo == FX2 G2: sales that did not leave stock
select stock_opening(tt.iid('FXS-K'),1,10,5) is not null as k0 \gset
-- HAND: clean sale of tracked A (3 kg) is matched; untracked item sale 2 -> kind untracked 1 ; 3 pc of K with no pc->kg conversion -> unit_unknown 1, stock stays 10
select tt.fxsale(1,'FXS-U',2) is not null as u1 \gset
select tt.fxsale(1,'FXS-K',3) is not null as u2 \gset
select case when to_regprocedure('public.stock_sales_unmatched(date,date,integer,uuid,integer)') is not null then stock_sales_unmatched(tt.today(), tt.today(), 1) end as fxu \gset
select tt.eq('FX2-G2 sales-vs-ledger check: untracked sale found (1 line)', 1, coalesce((:'fxu'::jsonb->'counts'->>'untracked')::numeric, 0));
select tt.eq('FX2-G2 sales-vs-ledger check: unit-unknown sale (3 pc, no conversion) found, stock stays 10', 1, coalesce((:'fxu'::jsonb->'counts'->>'unit_unknown')::numeric, 0) * (case when tt.qty('FXS-K',1) = 10 then 1 else 0 end));
select tt.eq('FX2-G2 sales-vs-ledger check: the clean sale of FXS-A (3 kg) is NOT listed; total = 2 unmatched lines', 2, coalesce((:'fxu'::jsonb->>'total')::numeric, 0));
select tt.t('FX2-G2 the statement carries the same counts', coalesce(stock_recon_statement(tt.today(), tt.today(), 1)->'sales_unmatched' = :'fxu'::jsonb->'counts', false));
