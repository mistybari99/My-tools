\echo == S6 layer 3 (showroom/admin) NOT in product cost, recipe versions / approval, cost sources
-- shared gas-like bill 10000 for places 1 (factory+showroom in one place) and 6 (cake factory): 1:factory 50 %, 1:showroom 30 %, 6:factory 20 %
-- HAND: pool 'other' of place 1 gets 5000 (factory share only); place 6 gets 2000; showroom 3000 goes to branch_overhead(1) and never to a product
select (cost_source_save(null,'water','Water authority','shared',null,array[1,6],'monthly',tt.today()-60)->>'id')::bigint as src \gset
select cost_rule_save(:'src'::bigint,'fixed_percent',tt.today()-60,'[{"location_id":1,"dest":"factory","value":50},{"location_id":1,"dest":"showroom","value":30},{"location_id":6,"dest":"factory","value":20}]'::jsonb) as rl \gset
select cost_rule_approve((:'rl'::jsonb->>'id')::bigint,'ok') as rla \gset
select cost_bill_add(:'src'::bigint,'month',tt.today(),10000) as cb \gset
\echo COST_BILL: :cb
select tt.eq('L1 pool other, place 1 (factory share only)', 5000, _pool_month_actual(1, date_trunc('month',tt.today())::date, 'other'));
select tt.eq('L1 pool other, place 6', 2000, _pool_month_actual(6, date_trunc('month',tt.today())::date, 'other'));
select tt.eq('L1 branch_overhead place 1 showroom row', 3000, (select sum((r->>'amount')::numeric) from jsonb_array_elements(branch_overhead(1, tt.today()-40, tt.today())->'rows') r where r->>'dest'='showroom'));
select tt.eq('L1 branch_overhead place 1 factory row (=pool)', 5000, (select sum((r->>'amount')::numeric) from jsonb_array_elements(branch_overhead(1, tt.today()-40, tt.today())->'rows') r where r->>'dest'='factory'));
-- is a cost bill a journal entry (expense) or just a memo?
select tt.t('L2 cost bill creates an expense journal (Dr expense) so that absorbed credit has a matching actual cost', exists (select 1 from journal_entries where source_type ilike '%cost_bill%' or source_type ilike '%cost_source%'), 'journal exists', (select count(*)::text from journal_entries where source_type ilike '%cost_bill%' or source_type ilike '%cost_source%'));
select tt.t('L2b cost bill pay_mode null -> no payment; total expense accounts debit', true, 'info', (select coalesce(sum(l.debit),0)::text from journal_lines l join coa_accounts a on a.id=l.account_id where a.type='expense' and a.code<>'5950'));
-- recipe approval / versions
select rule_on('recipe_self_approve') as rsa \gset
\echo RECIPE_SELF_APPROVE_DEFAULT=:rsa
select (recipe_copy((select id from recipes where item_id=tt.iid('FG-CAKE') and version=1))->>'id')::uuid as rc2 \gset
select tt.eq('V1 copy is version 2', 2, (select version from recipes where id=:'rc2'::uuid));
select set_rule('recipe_approval_required','"on"') is null as ra \gset
select tt.err('V2 approval=on: unapproved version refused in production', format($$select production_post(1,'%s',1,gen_random_uuid())$$, :'rc2'), 'recipe_not_approved');
select tt.err('V3 approved recipe cannot be edited', format($$select recipe_save('%s',tt.iid('FG-CAKE'),10,'kg','x','[{"ingredient_item_id":"%s","qty":1,"unit":"kg"}]'::jsonb)$$, (select id from recipes where item_id=tt.iid('FG-CAKE') and version=1), tt.iid('RM-F')), 'recipe');
select set_rule('recipe_approval_required','"off"') is null as ra0 \gset
-- recipe_cost for an older version after prices moved = new prices, no history of standard
select tt.t('V4 stored standard cost per recipe version (history of standard)?', exists (select 1 from information_schema.columns where table_name in ('recipes','recipe_versions','recipe_lines') and column_name ~ 'std|standard|cost'), 'none', (select coalesce(string_agg(table_name||'.'||column_name,','),'none') from information_schema.columns where table_schema='public' and table_name in ('recipes','recipe_versions','recipe_lines') and column_name ~ 'std|standard|cost'));
-- labour tied to production?
select tt.t('V5 attendance / payroll hours linked to production_runs', exists (select 1 from information_schema.columns where table_schema='public' and table_name='production_runs' and column_name ~ 'hours|staff|worker|labour'), 'none', (select coalesce(string_agg(column_name,','),'none') from information_schema.columns where table_schema='public' and table_name='production_runs' and column_name ~ 'hours|staff|worker|labour'));
