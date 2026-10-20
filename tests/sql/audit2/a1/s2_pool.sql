\echo == S2 (b) conversion cost pools: labour/gas/electricity/rent, allocation by output kg, smoothing, trueup (mode=pool, normal output 1000 kg/month)
-- HAND pool rates per kg of NORMAL output (1000): labour 30000/1000=30 ; gas: this month 6000 + last month 9000, avg_n(3) with first entry = last month -> span 2 -> 7500/1000 = 7.5 ;
--   electricity avg_n(3) only this month -> 4000/1000 = 4 ; rent 5000/1000 = 5 => 46.5 per kg of ACTUAL output
-- HAND run P1 = 1 batch cake actual 10 kg: material 1500 (avg flour/sugar/butter/box unchanged) + conv 465 = 1965 -> unit 196.5
-- HAND run P2 = sweet 10 kg (flour 5 + sugar 5 = 200+300 = 500) + conv 465 = 965 -> unit 96.5 (same 46.5/kg although it needs less labour: driver = output kg only)
-- HAND run P3 = piece item (unit pc) in pool mode: pool rate is per kg -> conversion NOT charged (reason pool_unit_not_kg); material 10 batches x 0.1 kg x 40 = 40 -> unit 4.0
-- HAND trueup (this month): actual labour 30000 gas 6000 elec 4000 rent 5000 = 45000 ; absorbed labour 300(recipe-mode A) + 300 + 300 + 300(P1,P2)... see below
--   labour = 200 + 100 (A2, A5, recipe mode) + 300 (P1) + 300 (P2) = 900 ; gas = 37 + 21.6 + 75 + 75 = 208.6 ; elec 40+40 = 80 ; rent 50+50 = 100 -> absorbed 1288.6 ; unabsorbed 45000 - 1288.6 = 43711.4
select loc_cost_cfg_set(1,'pool',1000) is null as lc \gset
select pool_set(1, tt.today(), 'labour', 30000) is not null as p1 \gset
select pool_set(1, tt.today(), 'gas', 6000) is not null as p2 \gset
select pool_set(1, (tt.today() - interval '1 month')::date, 'gas', 9000) is not null as p2b \gset
select pool_set(1, tt.today(), 'electricity', 4000) is not null as p3 \gset
select pool_set(1, tt.today(), 'factory_rent', 5000) is not null as p4 \gset
select tt.eq('B1 pool gas smoothed (6000+9000)/2', 7500, _pool_rate_amount(1, date_trunc('month', tt.today())::date, 'gas'));
select tt.eq('B1 pool journal effect of pool_set: expense accounts debited = 0 (pool is a memo, not a posting)', 0, (select coalesce(sum(l.debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.type='expense' and a.code<>'5950'));
select recipe_cost((select id from recipes where item_id=tt.iid('FG-CAKE')),1) as rc2 \gset
select tt.eq('B2 recipe_cost in pool mode: conversion = 46.5 x 10', 465, (:'rc2'::jsonb->>'conversion_cost')::numeric);
select production_post(1, (select id from recipes where item_id=tt.iid('FG-CAKE')), 1, gen_random_uuid(), null, 'pool run', 10) as pp1 \gset
select tt.eq('B3 P1 unit cost', 196.5, (select unit_cost from production_runs where id=(:'pp1'::jsonb->>'run_id')::uuid), 0.0005);
select (recipe_save(null, tt.iid('FG-SW'), 10, 'kg', 'sweet v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',5,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',5,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rsw \gset
select recipe_approve(:'rsw'::uuid,'ok') is not null as ap2 \gset
select production_post(1, :'rsw'::uuid, 1, gen_random_uuid(), null, 'sweet run', null) as pp2 \gset
select tt.eq('B3 P2 sweet unit cost (same rate/kg)', 96.5, (select unit_cost from production_runs where id=(:'pp2'::jsonb->>'run_id')::uuid), 0.0005);
select (recipe_save(null, tt.iid('FG-PC'), 1, 'pc', 'piece v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',0.1,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rpc \gset
select recipe_approve(:'rpc'::uuid,'ok') is not null as ap3 \gset
select production_post(1, :'rpc'::uuid, 10, gen_random_uuid(), null, 'piece run', null) as pp3 \gset
select tt.eq('B3 P3 piece item unit cost = material only (no conversion)', 4, (select unit_cost from production_runs where id=(:'pp3'::jsonb->>'run_id')::uuid), 0.0005);
select tt.is('B3 P3 conversion_complete flag', 'false', (select conversion_complete::text from production_runs where id=(:'pp3'::jsonb->>'run_id')::uuid));
select tt.t('B3 P3 yellow flag raised (conversion_incomplete)', exists (select 1 from exceptions where flag_code='conversion_incomplete'), 'exists', (select count(*)::text from exceptions where flag_code='conversion_incomplete'));
select overhead_trueup(1, tt.today()) as tu \gset
\echo TRUEUP: :tu
select tt.eq('B4 trueup actual total', 45000, (:'tu'::jsonb->>'actual_total')::numeric);
select tt.eq('B4 trueup absorbed total (recipe-mode + pool-mode runs mixed in one month)', 1288.6, (:'tu'::jsonb->>'absorbed_total')::numeric);
select tt.eq('B4 trueup unabsorbed', 43711.4, (:'tu'::jsonb->>'unabsorbed_overhead')::numeric);
select acct_post_pending(false) as pp \gset
select tt.eq('B5 GL 5950 (credit balance) = absorbed 1288.6', -1288.6, tt.bal('5950'));
select tt.eq('B5 GL: no entry ever debits an actual overhead expense for the pool (pool_set is memo) -> expense accts excl 5950', 0, (select coalesce(sum(l.debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.type='expense' and a.code<>'5950'));
select tt.t('B5 NO month-end journal exists for unabsorbed overhead (variance stays only in the report)', not exists (select 1 from journal_entries where source_type ilike '%trueup%' or source_type ilike '%absorb%'), 'no entry', (select count(*)::text from journal_entries where source_type ilike '%trueup%' or source_type ilike '%absorb%'));
-- period lock / month-end closing of pools? production of last month re-priced?
select tt.t('B6 pool_set for a month already used by runs re-prices old runs?', (select unit_cost from production_runs where id=(:'pp1'::jsonb->>'run_id')::uuid) = 196.5, 'unchanged 196.5 (no re-pricing)', (select unit_cost::text from production_runs where id=(:'pp1'::jsonb->>'run_id')::uuid));
-- HAND: a run dated in a month where the pools are not yet typed (45 days back): conversion unknown -> 0 booked, flagged; material 1500 / 10 = 150.0 ; nobody re-prices it when the pools are typed later
select production_post(1, (select id from recipes where item_id=tt.iid('FG-CAKE') and version=1), 1, gen_random_uuid(), now() - interval '45 days', 'back-dated run, pool not typed', 10) as ppb \gset
select tt.eq('B7 run in a month with no pool typed: unit cost = material only', 150, (select unit_cost from production_runs where id=(:'ppb'::jsonb->>'run_id')::uuid), 0.0005);
select tt.is('B7 conversion_complete', 'false', (select conversion_complete::text from production_runs where id=(:'ppb'::jsonb->>'run_id')::uuid));
select tt.is('B7 conversion_detail empty (the reason no_pool is not stored on the run)', '[]', (select conversion_detail::text from production_runs where id=(:'ppb'::jsonb->>'run_id')::uuid), 'detail is [] ; reason only in recipe_cost / exception');
