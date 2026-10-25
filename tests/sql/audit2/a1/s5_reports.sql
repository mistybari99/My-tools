\echo == S5 (f) report cost == journal == ledger ; unknown-cost production ; cost wait
-- sale of 5 kg cake. HAND cake stock: 18.5@174.97297(=3237) + 10.8@150.14815(=1621.6) + 10@196.5(=1965) + 10@150 (B7 back-dated run = 1500) = 8323.6 / 49.3 kg = 168.8357 ; COGS 5 x 168.8357 = 844.18
select tt.eq('F0 cake value 8323.6 / 49.3', 168.8357, tt.avg('FG-CAKE'), 0.0005);
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":300}]',tt.iid('FG-CAKE'))::jsonb,0,'[{"mode":"cash","amount":1500}]',null,null,'retail',null,false) as sa \gset
select acct_post_pending(false) as pp \gset
select tt.eq('F1 journal COGS 5000 for the sale', 844.18, tt.bal('5000'), 0.01);
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd_
select tt.eq('F1 biz_daily COGS == journal', tt.bal('5000'), :bd_cogs::numeric, 0.01);
select round(sum(-qty_delta * unit_cost),2) as led_cogs from stock_ledger where ref_type='sale' \gset
select tt.eq('F1 ledger sale_out value == journal', tt.bal('5000'), :led_cogs::numeric, 0.01);
select profit_source_check(tt.today(), tt.today(), 1) as psc \gset
select tt.t('F1 profit_source_check agree', (:'psc'::jsonb->>'agree')::boolean, 'true', :'psc'::jsonb->>'agree');
-- production runs vs ledger vs journal, every run: abs differences summed
select tt.eq('F2 sum |run (material+conversion) - ledger production_in value| over all runs', 0,
  (select coalesce(sum(abs(round(coalesce(r.material_cost,0)+coalesce(r.conversion_cost,0),2) - round(l.qty_delta*l.unit_cost,2))),0) from production_runs r join stock_ledger l on l.id=r.ledger_in_id where r.cost_complete), 0.2, 'rounding of unit_cost to 6 dp');
select tt.eq('F2 sum |run total - journal Dr inventory| over all costed runs', 0,
  (select coalesce(sum(abs(round(coalesce(r.material_cost,0)+coalesce(r.conversion_cost,0),2) - j.d)),0) from production_runs r join lateral (select coalesce(sum(jl.debit),0) d from journal_entries e join journal_lines jl on jl.entry_id=e.id join coa_accounts a on a.id=jl.account_id where e.source_type='production' and e.source_id=r.id::text and a.code='1310') j on true where r.cost_complete), 0.05);
select inventory_vs_gl(tt.today(), 1) as ivg \gset
\echo INV_VS_GL: :ivg
select tt.eq('F3 inventory_vs_gl total unexplained', 0, (:'ivg'::jsonb->'total'->>'unexplained')::numeric, 0.05);
-- dual cost sources: item_costs typed vs ledger
insert into item_costs (item_id, cost_price) values (tt.iid('FG-CAKE'), 120) on conflict (item_id) do update set cost_price=excluded.cost_price;
select rule_txt('report_cost_source') as rcs0 \gset
\echo REPORT_COST_SOURCE_DEFAULT=:rcs0
select set_rule('report_cost_source','"item_costs"') is null as r1 \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd2_
select tt.t('F4 mode item_costs: report COGS (5 x 120 = 600) differs from journal COGS 844.18', abs(:bd2_cogs::numeric - tt.bal('5000')) > 1, 'differs', :bd2_cogs::text);
select set_rule('report_cost_source',null) is null as r2 \gset
-- unknown-cost ingredient: cost null -> what is booked
select stock_opening(tt.iid('RM-NC'),1,50,null) is not null as o1 \gset
select (recipe_save(null, tt.iid('FG-NC'), 10, 'kg', 'nc v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-NC'),'qty',5,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',5,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rnc \gset
select recipe_approve(:'rnc'::uuid,'ok') is not null as apn \gset
-- HAND: sugar 5 x 60 = 300 known ; uncosted 5 kg unknown -> system should NOT book a cost it cannot know: unit_cost NULL, cost_complete false
select production_post(1, :'rnc'::uuid, 1, gen_random_uuid(), null, 'uncosted', null) as ppn \gset
select tt.is('G1 uncosted ingredient: cost_complete false', 'false', (select cost_complete::text from production_runs where id=(:'ppn'::jsonb->>'run_id')::uuid));
select tt.t('G1 uncosted ingredient: unit_cost is NULL (not silently 30 = sugar only)', (select unit_cost from production_runs where id=(:'ppn'::jsonb->>'run_id')::uuid) is null, 'null', coalesce((select unit_cost::text from production_runs where id=(:'ppn'::jsonb->>'run_id')::uuid),'null'));
select tt.t('G1 FG-NC stock avg_cost is NULL (a sale of it would have no COGS)', tt.avg('FG-NC') is null, 'null', coalesce(tt.avg('FG-NC')::text,'null'));
select acct_post_pending(false) as ppx \gset
select tt.t('G2 production journal posted with partial cost? (Dr 1310 amount; flags)', true, 'info', (select string_agg(e.flags||' D='||coalesce((select sum(debit)::text from journal_lines where entry_id=e.id),'-'),';') from journal_entries e where source_type='production' and source_id=(:'ppn'::jsonb->>'run_id')));
select tt.t('G2 the uncosted PRODUCTION run is on the cost-waiting list (not only the opening row)', exists (select 1 from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind' in ('production','run') or x->>'move' in ('production_in','issue_out')), 'listed', (select string_agg(x->>'kind'||'/'||coalesce(x->>'move','-'),',') from jsonb_array_elements(cost_wait_list96()->'items') x));
select cost_wait_list96() as cwl \gset
\echo COST_WAIT: :cwl

-- supply the missing cost for the raw material (20/kg). HAND: production should be re-costed 5x20 + 5x60 = 400 -> FG-NC unit 40
select cost_wait_supply96('ledger', (select x->>'ref' from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind'='ledger' and x->'items'->0->>'code'='RM-NC'), 'manual', format('[{"item_id":"%s","cost":20}]', tt.iid('RM-NC'))::jsonb, 'supplier quote', gen_random_uuid()) as spn \gset
select tt.eq('G3 RM-NC avg cost now 20', 20, tt.avg('RM-NC'));
select tt.eq('G3 FG-NC first run (made before the cost was known) is re-costed to 40', 40, tt.avg('FG-NC'), 0.01, 'NULL = the finished good stays uncosted forever; GL has only the known 300');
select tt.t('G3 production_runs row of that run updated after the cost arrived', (select unit_cost from production_runs where id=(:'ppn'::jsonb->>'run_id')::uuid) is not null, 'not null', coalesce((select unit_cost::text from production_runs where id=(:'ppn'::jsonb->>'run_id')::uuid),'null'));
-- a NEW run after the cost was supplied: HAND 5 x 20 + 5 x 60 = 400 -> unit 40
select production_post(1, :'rnc'::uuid, 1, gen_random_uuid(), null, 'uncosted again', null) as ppn2 \gset
select tt.eq('G3 second run after the cost was supplied: unit cost', 40, (select unit_cost from production_runs where id=(:'ppn2'::jsonb->>'run_id')::uuid), 0.01, 'NULL = supplied cost lives only in the ledger overlay, production reads stock_balance.avg_cost');
select acct_post_pending(false) as ppy \gset
select (inventory_vs_gl(tt.today(),1)->'total') as ivg2 \gset
\echo IVG_AFTER_UNCOSTED: :ivg2
select tt.eq('G3 inventory_vs_gl unexplained after all (should be explained, not hidden)', 0, (:'ivg2'::jsonb->>'unexplained')::numeric, 0.05);
-- free-cost flag (phase80): flagged 'really free' -> known cost 0. HAND: sugar 5 x 60 = 300 + 0 = 300 / 10 = 30
select item_cost_free_set(tt.iid('RM-NC'), true, 'declared free for audit test', gen_random_uuid()) is not null as fr \gset
select production_post(1, :'rnc'::uuid, 1, gen_random_uuid(), null, 'free flagged', null) as ppn3 \gset
select tt.eq('H1 free-cost flagged ingredient: unit cost known', 30, (select unit_cost from production_runs where id=(:'ppn3'::jsonb->>'run_id')::uuid), 0.0005);
select tt.is('H1 cost_complete', 'true', (select cost_complete::text from production_runs where id=(:'ppn3'::jsonb->>'run_id')::uuid));
