-- Phase 457 tests (RPT-C2 R6 part 3: crew and hours on a production run, output per labour hour #149). Neutral test_* data only.  bash tests/sql/c2_run.sh phase457
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_staff_fixture.sql

select tt.as(:'o');
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('TST-RM','test_raw','test_raw','kg','kg','raw_material',true,0);
select id as irm from items where code='TST-RM' \gset
select stock_opening(:'irm'::uuid, 1, 500, 20, null, 'seed') is not null as oprm \gset
select (recipe_save(null, :'ia'::uuid, 10, null, 'test recipe', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'irm','qty',5,'waste_pct',0)))->>'id')::uuid as rc \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run1 \gset
select production_post(1, :'rc'::uuid, 2, gen_random_uuid())->>'run_id' as run2 \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run3 \gset
insert into user_grants (user_id, grant_code, location_id) values (:'m', 'stock_production', 1) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 functions open, helper closed, table read-only, RLS on, anon none', has_function_privilege('authenticated','public.c2_production_crew_set(uuid,jsonb,text)','execute') and has_function_privilege('authenticated','public.c2_output_per_labour_hour(date,date,int)','execute')
  and has_function_privilege('authenticated','public.c2_crew_pick(int)','execute') and not has_function_privilege('authenticated','public._c2_can_crew(int)','execute') and not has_function_privilege('anon','public.c2_production_crew_set(uuid,jsonb,text)','execute')
  and not has_table_privilege('authenticated','public.production_crew','insert') and (select relrowsecurity from pg_class where relname='production_crew'));

\echo == T1 set the crew
select tt.as(:'m');
select c2_production_crew_set(:'run1'::uuid, format('[{"employee_id":"%s","hours":4},{"employee_id":"%s","minutes":120}]', :'emp1', :'emp2')::jsonb) as c1 \gset
select tt.chk('T1 crew of 2: 240 + 120 = 360 minutes saved by the production-right holder', (:'c1'::jsonb ->> 'workers')::int=2 and (:'c1'::jsonb ->> 'minutes')::int=360);
select tt.chk('T1 same crew again = no-op', (c2_production_crew_set(:'run1'::uuid, format('[{"employee_id":"%s","minutes":120},{"employee_id":"%s","minutes":240}]', :'emp2', :'emp1')::jsonb) ->> 'noop')::boolean);
select c2_production_crew_set(:'run1'::uuid, format('[{"employee_id":"%s","hours":5}]', :'emp1')::jsonb, 'test_changed') is not null as c1b \gset
select tt.chk('T1 a change voids the old rows (history kept) and writes the new: 3 void... 2 void + 1 active', (select count(*) from production_crew where run_id=:'run1'::uuid and state='active')=1 and (select count(*) from production_crew where run_id=:'run1'::uuid and state='void')=2);
select tt.err('T1 duplicate worker refused', format($$select c2_production_crew_set('%s','[{"employee_id":"%s","minutes":10},{"employee_id":"%s","minutes":20}]')$$, :'run2', :'emp1', :'emp1'), 'duplicate_worker');
select tt.err('T1 minutes must be 1 to 1440', format($$select c2_production_crew_set('%s','[{"employee_id":"%s","minutes":0}]')$$, :'run2', :'emp1'), 'bad_minutes');
select tt.err('T1 hours or minutes is needed', format($$select c2_production_crew_set('%s','[{"employee_id":"%s"}]')$$, :'run2', :'emp1'), 'bad_minutes');
select tt.err('T1 an unknown employee is refused', format($$select c2_production_crew_set('%s','[{"employee_id":"%s","minutes":10}]')$$, :'run2', gen_random_uuid()), 'employee_not_active');
select tt.as(:'p');
select tt.err('T1 a salesperson (no production right) refused', format($$select c2_production_crew_set('%s','[{"employee_id":"%s","minutes":10}]')$$, :'run2', :'emp1'), 'not allowed');
select tt.err('T1 a production row cannot be edited directly', format($$update production_crew set minutes=1 where run_id='%s'$$, :'run1'), 'append_only');
select tt.as(:'m');
select tt.chk('T1 the picker lists the two active place-1 employees, no pay in it', jsonb_array_length(c2_crew_pick(1))=2 and (c2_crew_pick(1)::text !~ 'salary|pay|net'));
select tt.err('T1 the picker refuses a place the person has no production right at', $$select c2_crew_pick(2)$$, 'not allowed');
select tt.chk('T1 crew read back', jsonb_array_length(c2_production_crew_get(:'run1'::uuid) -> 'rows')=1);

\echo == T2 output per labour hour (#149)
select c2_production_crew_set(:'run2'::uuid, format('[{"employee_id":"%s","hours":2}]', :'emp1')::jsonb) is not null as c2 \gset
select tt.as(:'o');
select c2_output_per_labour_hour(tt.today()-1, tt.today()+1) as ph \gset
select tt.chk('T2 3 runs (10 + 20 + 10 units), 2 with a crew: coverage 66.7 percent; run3 has no crew and is counted apart', (:'ph'::jsonb #>> '{summary,runs}')::int=3 and (:'ph'::jsonb #>> '{summary,runs_with_crew}')::int=2
  and (:'ph'::jsonb #>> '{summary,runs_without_crew}')::int=1 and (:'ph'::jsonb #>> '{summary,coverage_pct}')::numeric=66.7);
select tt.chk('T2 output per labour hour only over the crewed runs: (10 + 20) units / (5 h + 2 h) = 4.29', (select (r ->> 'output_per_labour_hour')::numeric from jsonb_array_elements(:'ph'::jsonb -> 'rows') r where r ->> 'code'='TST-A')=4.29
  and (select (r ->> 'crew_hours')::numeric from jsonb_array_elements(:'ph'::jsonb -> 'rows') r where r ->> 'code'='TST-A')=7.00);
select tt.chk('T2 the run without a crew has hours null and per-hour null (not 0)', (select r -> 'output_per_labour_hour' from jsonb_array_elements(:'ph'::jsonb -> 'runs') r where r ->> 'run_id'=:'run3')='null'::jsonb and (select r -> 'crew_hours' from jsonb_array_elements(:'ph'::jsonb -> 'runs') r where r ->> 'run_id'=:'run3')='null'::jsonb);
select tt.chk('T2 nothing in the range: empty, coverage null', (c2_output_per_labour_hour(tt.today()-300, tt.today()-290) #>> '{summary,coverage_pct}') is null);
select tt.as(:'k');
select tt.err('T2 storekeeper without production or report right refused', $$select c2_output_per_labour_hour(current_date-1, current_date)$$, 'not allowed');
select tt.as(:'r');
select tt.chk('T2 a view_reports holder reads it', (c2_output_per_labour_hour(tt.today()-1, tt.today()+1) #>> '{summary,runs}')::int=3);

\echo == T9 paste twice
\ir phase457.sql
select tt.chk('T9 pasted again without error, no new rows', (select count(*) from production_crew)=4);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
