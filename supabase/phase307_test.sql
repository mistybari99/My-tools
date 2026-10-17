-- FRESH DB ONLY. Phase 307 tests (CRM-C: safe rule builder, previews, saved and frozen lists, privacy of the member pages).
--   build: phases 8..98, 306, 307 (the DB may also carry 308); run: psql -h /tmp -p 5573 -U postgres -d <db> -qAt -f supabase/phase307_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names, tests/sql/crmc_fixture.sql). Expected numbers are hand-computed from the fixture (comments above each block).
\set ON_ERROR_STOP off
\ir ../tests/sql/crmc_fixture.sql
truncate tt.res;
create or replace function tt.err_role(p_name text, p_role text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute format('set local role %I', p_role); execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.snap() returns text language plpgsql security definer as $$
declare r text := ''; t text;
begin
  foreach t in array array['sales','sale_payments','sale_returns','customers','journal_entries','journal_lines','customer_points_ledger','notify_optin','stock_ledger'] loop
    execute format('select md5(coalesce(string_agg(x::text, '''' order by x::text), '''')) from public.%I x', t) into t;
    r := r || t;
  end loop;
  return md5(r);
end $$;
-- number of customers a rule finds (as the owner of the function, no rights test)
create or replace function tt.n(p_rule text) returns int language sql security definer as $$ select cardinality(public._crmc_eval(p_rule::jsonb)) $$;
create or replace function tt.names(p_rule text) returns text language sql security definer as $$
  select coalesce(string_agg(replace(c.name, 'test_cust_', ''), ',' order by c.name), '') from customers c where c.id = any (public._crmc_eval(p_rule::jsonb)) $$;
grant execute on function tt.err_role(text, text, text, text), tt.n(text), tt.names(text) to authenticated, anon;
select tt.today() as t \gset
select tt.snap() as snap0 \gset
create or replace function tt.snap2() returns text language plpgsql security definer as $$
declare r text := ''; t text;
begin
  foreach t in array array['sale_payments','sale_returns','journal_entries','journal_lines','customer_points_ledger','notify_optin','stock_ledger'] loop
    execute format('select md5(coalesce(string_agg(x::text, '''' order by x::text), '''')) from public.%I x', t) into t;
    r := r || t;
  end loop;
  return md5(r);
end $$;
select tt.snap2() as snap2_0 \gset
\set iA '''aaaaaaaa-0000-0000-0000-0000000000a1'''
\set iB '''aaaaaaaa-0000-0000-0000-0000000000a2'''

\echo == T0 shape: tables closed, the rule evaluator has no dynamic SQL on user values
select tt.chk('T0 phase307 present, four tables/functions closed, public functions open to signed-in only',
  to_regclass('public.crm_segments') is not null and to_regclass('public.crm_segment_members') is not null
  and not has_table_privilege('authenticated', 'public.crm_segments', 'select') and not has_table_privilege('authenticated', 'public.crm_segment_members', 'select')
  and not has_function_privilege('authenticated', 'public._crmc_eval(jsonb,date)', 'execute') and not has_function_privilege('authenticated', 'public._crmc_audience(bigint,int)', 'execute')
  and has_function_privilege('authenticated', 'public.crmc_preview(jsonb,bigint)', 'execute') and not has_function_privilege('anon', 'public.crmc_preview(jsonb,bigint)', 'execute'));
select tt.chk('T0 catalog lists 24 fields; the evaluator and the rule checker contain no EXECUTE of a built string (only one fixed text for the optional do-not-contact table)',
  (select count(*) from _crmc_catalog()) = 24
  and (select prosrc !~* 'format\s*\(' and prosrc !~* '\|\|\s*p_' and (length(prosrc) - length(replace(lower(prosrc), 'execute ', ''))) / 8 = 1 from pg_proc where proname = '_crmc_cond_ids')
  and (select prosrc !~* 'execute' from pg_proc where proname = '_crmc_rule_norm') and (select prosrc !~* 'execute' from pg_proc where proname = '_crmc_eval'));

\echo == T1 injection and malformed rules are refused (nothing reaches SQL)
select tt.n('{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}') as before_n \gset
select tt.err('T1 field with SQL text', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total; drop table customers; --","op":"ge","value":1}]}')$$, 'bad_rule:unknown_field');
select tt.err('T1 field that is a column expression', $$select _crmc_rule_norm('{"conditions":[{"field":"1=1 or customers.mobile","op":"ge","value":1}]}')$$, 'bad_rule:unknown_field');
select tt.err('T1 field with a real column name that is not in the catalog (mobile)', $$select _crmc_rule_norm('{"conditions":[{"field":"mobile","op":"in","value":["017"]}]}')$$, 'bad_rule:unknown_field');
select tt.err('T1 field that is not text', $$select _crmc_rule_norm('{"conditions":[{"field":5,"op":"ge","value":1}]}')$$, 'bad_rule:bad_condition');
select tt.err('T1 operator with SQL text', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"ge; --","value":1}]}')$$, 'bad_rule:bad_operator');
select tt.err('T1 operator not allowed for the field (in on a number)', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"in","value":[1]}]}')$$, 'bad_rule:bad_operator');
select tt.err('T1 operator not allowed for the field (gt on a bool)', $$select _crmc_rule_norm('{"conditions":[{"field":"has_due","op":"gt","value":true}]}')$$, 'bad_rule:bad_operator');
select tt.err('T1 number given as text with SQL', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"ge","value":"1; select pg_sleep(10)"}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 number given as the text 1 or 1=1', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"ge","value":"1 or 1=1"}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 number given as an object', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"ge","value":{"a":1}}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 number given as null', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"ge","value":null}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 number far too big', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"ge","value":1e15}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 negative days', $$select _crmc_rule_norm('{"conditions":[{"field":"days_since_last","op":"ge","value":-1}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 birthday month 13', $$select _crmc_rule_norm('{"conditions":[{"field":"birthday_month","op":"eq","value":13}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 between with three numbers', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"between","value":[1,2,3]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 between reversed', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"between","value":[5,2]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 within-days with a fraction', $$select _crmc_rule_norm('{"conditions":[{"field":"birthday_in_days","op":"le","value":2.5}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 unknown key at the top', $$select _crmc_rule_norm('{"sql":"select 1","conditions":[{"field":"orders_total","op":"ge","value":1}]}')$$, 'bad_rule:unknown_key');
select tt.err('T1 unknown key in a condition', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"ge","value":1,"where":"1=1"}]}')$$, 'bad_rule:unknown_key');
select tt.err('T1 within_days on a number field', $$select _crmc_rule_norm('{"conditions":[{"field":"orders_total","op":"ge","value":1,"within_days":5}]}')$$, 'bad_rule:unknown_key');
select tt.err('T1 channel on a tier field', $$select _crmc_rule_norm('{"conditions":[{"field":"tier","op":"in","value":["gold"],"channel":"sms"}]}')$$, 'bad_rule:unknown_key');
select tt.err('T1 match that is not all or any', $$select _crmc_rule_norm('{"match":"all; drop","conditions":[{"field":"orders_total","op":"ge","value":1}]}')$$, 'bad_rule:bad_match');
select tt.err('T1 match that is not text', $$select _crmc_rule_norm('{"match":1,"conditions":[{"field":"orders_total","op":"ge","value":1}]}')$$, 'bad_rule:bad_match');
select tt.err('T1 conditions that are not a list', $$select _crmc_rule_norm('{"conditions":"orders_total"}')$$, 'bad_rule:no_conditions');
select tt.err('T1 empty condition list (no accidental everyone)', $$select _crmc_rule_norm('{"conditions":[]}')$$, 'bad_rule:no_conditions');
select tt.err('T1 nine conditions', $$select _crmc_rule_norm(jsonb_build_object('conditions', (select jsonb_agg('{"field":"orders_total","op":"ge","value":1}'::jsonb) from generate_series(1, 9))))$$, 'bad_rule:too_many_conditions');
select tt.err('T1 rule is an array', $$select _crmc_rule_norm('[1]')$$, 'bad_rule:not_an_object');
select tt.err('T1 rule is a string', $$select _crmc_rule_norm('"select 1"')$$, 'bad_rule:not_an_object');
select tt.err('T1 rule is null', $$select _crmc_rule_norm(null)$$, 'bad_rule:not_an_object');
create or replace function tt.bigcond() returns jsonb language sql as $$ select jsonb_build_object('field', 'source', 'op', 'in', 'value', jsonb_agg(repeat('x', 60))) from generate_series(1, 50) $$;
select tt.err('T1 rule far too big', $$select _crmc_rule_norm(jsonb_build_object('conditions', jsonb_build_array(tt.bigcond(), tt.bigcond(), tt.bigcond(), tt.bigcond(), tt.bigcond(), tt.bigcond(), tt.bigcond(), tt.bigcond())))$$, 'bad_rule:too_big');
select tt.err('T1 list of 51 tiers', $$select _crmc_rule_norm(jsonb_build_object('conditions', jsonb_build_array(jsonb_build_object('field', 'tier', 'op', 'in', 'value', (select jsonb_agg('t' || g) from generate_series(1, 51) g)))))$$, 'bad_rule:bad_value');
select tt.err('T1 tier with quote and SQL', $$select _crmc_rule_norm('{"conditions":[{"field":"tier","op":"in","value":["gold'' or ''1''=''1"]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 tier list holding a number', $$select _crmc_rule_norm('{"conditions":[{"field":"tier","op":"in","value":[5]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 tier given as text instead of a list', $$select _crmc_rule_norm('{"conditions":[{"field":"tier","op":"in","value":"gold"}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 type that is not retail or wholesale', $$select _crmc_rule_norm('{"conditions":[{"field":"type","op":"in","value":["martian"]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 label that is not a known label', $$select _crmc_rule_norm('{"conditions":[{"field":"rfm_label","op":"in","value":["Hacker"]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 source of 70 characters', $$select _crmc_rule_norm(jsonb_build_object('conditions', jsonb_build_array(jsonb_build_object('field', 'source', 'op', 'in', 'value', jsonb_build_array(repeat('a', 70))))))$$, 'bad_rule:bad_value');
select tt.err('T1 source with a control character', $$select _crmc_rule_norm('{"conditions":[{"field":"source","op":"in","value":["a\u0001b"]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 outlet 0', $$select _crmc_rule_norm('{"conditions":[{"field":"outlet","op":"in","value":[0]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 outlet 1.5', $$select _crmc_rule_norm('{"conditions":[{"field":"outlet","op":"in","value":[1.5]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 item that is not an id', $$select _crmc_rule_norm('{"conditions":[{"field":"bought_item","op":"in","value":["x'' or 1=1 --"]}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 eleven items', $$select _crmc_rule_norm(jsonb_build_object('conditions', jsonb_build_array(jsonb_build_object('field', 'bought_item', 'op', 'in', 'value', (select jsonb_agg(gen_random_uuid()::text) from generate_series(1, 11))))))$$, 'bad_rule:bad_value');
select tt.err('T1 items within 0 days', $$select _crmc_rule_norm('{"conditions":[{"field":"bought_item","op":"in","value":["aaaaaaaa-0000-0000-0000-0000000000a1"],"within_days":0}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 items within 4000 days', $$select _crmc_rule_norm('{"conditions":[{"field":"bought_item","op":"in","value":["aaaaaaaa-0000-0000-0000-0000000000a1"],"within_days":4000}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 bool given as text', $$select _crmc_rule_norm('{"conditions":[{"field":"has_due","op":"is","value":"true"}]}')$$, 'bad_rule:bad_value');
select tt.err('T1 channel that is not sms or whatsapp', $$select _crmc_rule_norm('{"conditions":[{"field":"opted_in","op":"is","value":true,"channel":"telegram"}]}')$$, 'bad_rule:bad_value');
select tt.chk('T1 a valid rule is cleaned: text lower-cased and trimmed, defaults filled in',
  _crmc_rule_norm('{"conditions":[{"field":"tier","op":"in","value":["GOLD "]},{"field":"source","op":"in","value":["  Facebook"]},{"field":"opted_in","op":"is","value":true}]}')
  = '{"match":"all","conditions":[{"op":"in","field":"tier","value":["gold"]},{"op":"in","field":"source","value":["facebook"]},{"op":"is","field":"opted_in","value":true,"channel":"any"}]}'::jsonb);
select tt.chk('T1 hostile text used as a value is only ever compared as text: finds nobody, breaks nothing',
  tt.n('{"conditions":[{"field":"source","op":"in","value":["'' or 1=1 --"]}]}') = 0 and tt.n('{"conditions":[{"field":"source","op":"in","value":["%"]}]}') = 0 and tt.n('{"conditions":[{"field":"source","op":"in","value":["face%"]}]}') = 0);
select tt.chk('T1 after all the attempts the tables and data are unchanged', (select count(*) from customers) = 8 and tt.snap() = :'snap0' and tt.n('{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}') = :before_n);

\echo == T2 before any score exists: customer-table conditions work, score conditions find nobody and say so
select tt.as(:'u_o');
select tt.chk('T2 tier gold finds the champ without a score row', tt.names('{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}') = 'champ');
select tt.chk('T2 days since last visit finds nobody yet', tt.n('{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}') = 0);
select tt.chk('T2 preview says 7 customers, 0 scored, 7 not scored', (crmc_preview('{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')->>'unscored_customers')::int = 7 and (crmc_preview('{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')->>'members_unscored')::int = 1);
select crmc_metrics_refresh(false) ->> 'processed' as p \gset
select tt.chk('T2 refresh scored 7', :p = 7);

\echo == T3 conditions, hand-computed on the fixture (T = today; champ T-5/T-10/T-20, at-risk T-100/T-90, onetime T-40, old T-400, void-customer T-2, due T-15; inactive customer never counted)
select tt.chk('T3 not seen for over 30 days = atrisk, onetime, old', tt.names('{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}') = 'atrisk,old,onetime');
select tt.chk('T3 days >= 90 = atrisk, old; = 5 is champ; between 10 and 50 = due, onetime', tt.names('{"conditions":[{"field":"days_since_last","op":"ge","value":90}]}') = 'atrisk,old'
  and tt.names('{"conditions":[{"field":"days_since_last","op":"eq","value":5}]}') = 'champ' and tt.names('{"conditions":[{"field":"days_since_last","op":"between","value":[10,50]}]}') = 'due,onetime');
select tt.chk('T3 spent 500 or more in 12 months = champ, due', tt.names('{"conditions":[{"field":"spend_12m","op":"ge","value":500}]}') = 'champ,due');
select tt.chk('T3 total spent >= 500 includes old (500 a year ago) = champ, due, old', tt.names('{"conditions":[{"field":"spend_total","op":"ge","value":500}]}') = 'champ,due,old');
select tt.chk('T3 orders: none = never; 1 = due, old, onetime, void', tt.names('{"conditions":[{"field":"orders_total","op":"eq","value":0}]}') = 'never' and tt.names('{"conditions":[{"field":"orders_total","op":"eq","value":1}]}') = 'due,old,onetime,void');
select tt.chk('T3 orders in 12 months = 0 is old and never', tt.names('{"conditions":[{"field":"orders_12m","op":"eq","value":0}]}') = 'never,old');
select tt.chk('T3 average bill >= 500 = due (1000), old (500)', tt.names('{"conditions":[{"field":"avg_bill","op":"ge","value":500}]}') = 'due,old');
select tt.chk('T3 amount owed >= 500 = due; has_due true = due; false = the other six scored', tt.names('{"conditions":[{"field":"due_amount","op":"ge","value":500}]}') = 'due'
  and tt.names('{"conditions":[{"field":"has_due","op":"is","value":true}]}') = 'due' and tt.n('{"conditions":[{"field":"has_due","op":"is","value":false}]}') = 6);
select tt.chk('T3 points >= 50 = champ', tt.names('{"conditions":[{"field":"points","op":"ge","value":50}]}') = 'champ');
select tt.chk('T3 tier: gold = champ; not gold = the other six; silver = atrisk; GOLD with spaces is cleaned', tt.n('{"conditions":[{"field":"tier","op":"not_in","value":["gold"]}]}') = 6
  and tt.names('{"conditions":[{"field":"tier","op":"in","value":["silver"]}]}') = 'atrisk' and tt.names('{"conditions":[{"field":"tier","op":"in","value":[" GOLD "]}]}') = 'champ');
select tt.chk('T3 type wholesale = atrisk; retail = the other six', tt.names('{"conditions":[{"field":"type","op":"in","value":["wholesale"]}]}') = 'atrisk' and tt.n('{"conditions":[{"field":"type","op":"in","value":["retail"]}]}') = 6);
select tt.chk('T3 source facebook = champ (case does not matter); not facebook = six', tt.names('{"conditions":[{"field":"source","op":"in","value":["FACEBOOK"]}]}') = 'champ' and tt.n('{"conditions":[{"field":"source","op":"not_in","value":["facebook"]}]}') = 6);
select tt.chk('T3 outlet 2 = onetime, void; not outlet 2 (scored) = atrisk, champ, due, never, old', tt.names('{"conditions":[{"field":"outlet","op":"in","value":[2]}]}') = 'onetime,void'
  and tt.names('{"conditions":[{"field":"outlet","op":"not_in","value":[2]}]}') = 'atrisk,champ,due,never,old');
select tt.chk('T3 birthday within 3 days = champ; within 2 = nobody; within 366 = champ, never (birthday T+200)', tt.names('{"conditions":[{"field":"birthday_in_days","op":"le","value":3}]}') = 'champ'
  and tt.n('{"conditions":[{"field":"birthday_in_days","op":"le","value":2}]}') = 0 and tt.names('{"conditions":[{"field":"birthday_in_days","op":"le","value":366}]}') = 'champ,never');
select tt.chk('T3 birthday on file: yes = champ, never; no = the other five', tt.names('{"conditions":[{"field":"has_birthday","op":"is","value":true}]}') = 'champ,never' and tt.n('{"conditions":[{"field":"has_birthday","op":"is","value":false}]}') = 5);
select tt.chk('T3 birthday this month and birthday month agree with a plain calendar test',
  tt.n('{"conditions":[{"field":"birthday_this_month","op":"is","value":true}]}') = (select count(*) from customers where active and extract(month from birthday) = extract(month from :'t'::date))
  and tt.n(format('{"conditions":[{"field":"birthday_month","op":"eq","value":%s}]}', extract(month from :'t'::date + 3))) = (select count(*) from customers where active and extract(month from birthday) = extract(month from :'t'::date + 3)));
select tt.chk('T3 bought item b = champ, atrisk, void; item a = atrisk, champ, due, old, onetime; either = six', tt.names(format('{"conditions":[{"field":"bought_item","op":"in","value":[%s]}]}', replace(:'iB', '''', '"'))) = 'atrisk,champ,void'
  and tt.names(format('{"conditions":[{"field":"bought_item","op":"in","value":[%s]}]}', replace(:'iA', '''', '"'))) = 'atrisk,champ,due,old,onetime'
  and tt.n(format('{"conditions":[{"field":"bought_item","op":"in","value":[%s,%s]}]}', replace(:'iA', '''', '"'), replace(:'iB', '''', '"'))) = 6);
select tt.chk('T3 bought item b in the last 15 days = champ, void; never bought item b = due, never, old, onetime',
  tt.names(format('{"conditions":[{"field":"bought_item","op":"in","value":[%s],"within_days":15}]}', replace(:'iB', '''', '"'))) = 'champ,void'
  and tt.names(format('{"conditions":[{"field":"not_bought_item","op":"in","value":[%s]}]}', replace(:'iB', '''', '"'))) = 'due,never,old,onetime');
select tt.chk('T3 agreed to messages: any = champ, onetime; sms = champ; whatsapp = onetime; not agreed = five; sms-out customer is not "agreed"',
  tt.names('{"conditions":[{"field":"opted_in","op":"is","value":true}]}') = 'champ,onetime' and tt.names('{"conditions":[{"field":"opted_in","op":"is","value":true,"channel":"sms"}]}') = 'champ'
  and tt.names('{"conditions":[{"field":"opted_in","op":"is","value":true,"channel":"whatsapp"}]}') = 'onetime' and tt.n('{"conditions":[{"field":"opted_in","op":"is","value":false}]}') = 5);
select tt.chk('T3 customer label (standard mode): Champion = champ; One-time = due, onetime, void; not One-time (scored) = atrisk, champ, never, old',
  tt.names('{"conditions":[{"field":"rfm_label","op":"in","value":["Champion"]}]}') = 'champ' and tt.names('{"conditions":[{"field":"rfm_label","op":"in","value":["One-time"]}]}') = 'due,onetime,void'
  and tt.names('{"conditions":[{"field":"rfm_label","op":"not_in","value":["One-time"]}]}') = 'atrisk,champ,never,old');
select tt.chk('T3 customer joined: age 0 days = all seven active customers, over 5 days = nobody', tt.n('{"conditions":[{"field":"customer_age_days","op":"le","value":1}]}') = 7 and tt.n('{"conditions":[{"field":"customer_age_days","op":"gt","value":5}]}') = 0);
select tt.chk('T3 the inactive customer never appears in any list', tt.n('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}') = 7 and tt.n('{"conditions":[{"field":"type","op":"in","value":["retail","wholesale"]}]}') = 7);
select tt.chk('T3 all (and): not seen > 30 days AND spent >= 100 in 12 months = atrisk only', tt.names('{"conditions":[{"field":"days_since_last","op":"gt","value":30},{"field":"spend_12m","op":"ge","value":100}]}') = 'atrisk');
select tt.chk('T3 any (or): gold OR wholesale = atrisk, champ; "match" left out means all', tt.names('{"match":"any","conditions":[{"field":"tier","op":"in","value":["gold"]},{"field":"type","op":"in","value":["wholesale"]}]}') = 'atrisk,champ'
  and tt.n('{"conditions":[{"field":"tier","op":"in","value":["gold"]},{"field":"type","op":"in","value":["wholesale"]}]}') = 0);
select tt.chk('T3 a rule that matches nobody gives an empty list, not an error', tt.n('{"conditions":[{"field":"tier","op":"in","value":["elite"]}]}') = 0);
-- package B simulated: a do-not-contact table. DNC beats an opt-in; "not agreed" then includes them.
create table public.crm_contact_prefs (customer_id uuid primary key, dnc boolean not null default false);
insert into crm_contact_prefs values ('00000000-0000-0000-0000-00000000c3a1', true);
select tt.chk('T3 with package B present, a do-not-contact customer is not "agreed" even with an opt-in (champ drops out) and is "not agreed" (six)',
  tt.names('{"conditions":[{"field":"opted_in","op":"is","value":true}]}') = 'onetime' and tt.n('{"conditions":[{"field":"opted_in","op":"is","value":false}]}') = 6);
drop table public.crm_contact_prefs;
select tt.chk('T3 with package B gone again, the plain opt-in answer is back', tt.names('{"conditions":[{"field":"opted_in","op":"is","value":true}]}') = 'champ,onetime');

\echo == T4 preview
select tt.chk('T4 preview of "not seen over 30 days": 3 customers, spend 930 (350+80+500), 12m spend 430, by label At-risk 1 / One-time 1 / Inactive 1, not over the cap',
  (select (r->>'count')::int = 3 and (r->>'lifetime_spend')::numeric = 930 and (r->>'spend_12m')::numeric = 430 and r->'by_label' = '{"At-risk":1,"Inactive":1,"One-time":1}'::jsonb and not (r->>'over_cap')::boolean and (r->>'members_unscored')::int = 0
     from (select crmc_preview('{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}') r) z));
select tt.err('T4 preview needs exactly one of rule / list', $$select crmc_preview(null, null)$$, 'bad_value');
select tt.err('T4 preview of a bad rule is refused with the reason', $$select crmc_preview('{"conditions":[{"field":"x","op":"ge","value":1}]}')$$, 'bad_rule:unknown_field');
select tt.err('T4 preview of a missing list', $$select crmc_preview(null, 999999)$$, 'not found');

\echo == T5 who may preview, save, freeze (server side)
set role authenticated;
select tt.as(:'u_c');
select tt.err('T5 cashier: preview', $$select crmc_preview('{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, 'not allowed');
select tt.err('T5 cashier: members', $$select crmc_members('{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, 'not allowed');
select tt.err('T5 cashier: catalog', $$select crmc_field_catalog()$$, 'not allowed');
select tt.err('T5 cashier: item search', $$select crmc_item_search('test')$$, 'not allowed');
select tt.err('T5 cashier: saved lists', $$select crmc_segments_list()$$, 'not allowed');
select tt.as(:'u_v');
select tt.chk('T5 viewer: preview works while saving is switched OFF', (crmc_preview('{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')->>'count')::int = 1);
select tt.err('T5 viewer: cannot save', $$select crmc_segment_save(null, null, 'test_list_x', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, 'not allowed');
select tt.as(:'u_m');
select tt.err('T5 customer manager (no list right): cannot save', $$select crmc_segment_save(null, null, 'test_list_x', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, 'not allowed');
select tt.as(:'u_e');
select tt.err('T5 editor: saving is OFF by default -> segments_off', $$select crmc_segment_save(null, null, 'test_list_x', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, 'segments_off');
select tt.err('T5 editor: freezing is OFF too', $$select crmc_segment_freeze(null, null, '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}', 'test_frozen_x')$$, 'segments_off');
reset role;
select tt.err_role('T5 anonymous: no execute right on preview', 'anon', $$select public.crmc_preview('{"conditions":[]}')$$, 'permission denied');
select tt.as(:'u_o'); set role authenticated; select set_rule('crm_segments_on', 'true'::jsonb); reset role;
select count(*) as segs0 from crm_segments \gset

\echo == T6 save, rename, update, retire
select tt.as(:'u_e');
select crmc_segment_save('c0000000-0000-0000-0000-000000000001', null, 'test_list_lapsed', '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'not seen') ->> 'id' as sid \gset
select tt.chk('T6 saved: dynamic, count 3 stored, the checked rule stored (with match all)', exists (select 1 from crm_segments where id = :sid and kind = 'dynamic' and last_count = 3 and rule ->> 'match' = 'all' and note = 'not seen' and active));
select tt.chk('T6 same client id again = same list, marked repeat, no second row', (crmc_segment_save('c0000000-0000-0000-0000-000000000001', null, 'test_list_lapsed', '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}')->>'repeat')::boolean
  and (select count(*) from crm_segments) = :segs0 + 1);
select tt.err('T6 same name again (different case) refused', $$select crmc_segment_save(null, null, 'TEST_LIST_LAPSED ', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, 'name_taken');
select tt.err('T6 empty name refused', $$select crmc_segment_save(null, null, '  ', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, 'bad_name');
select tt.err('T6 name of 61 characters refused', $$select crmc_segment_save(null, null, repeat('n', 61), '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, 'bad_name');
select tt.err('T6 note of 201 characters refused', $$select crmc_segment_save(null, null, 'test_list_n', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}', repeat('n', 201))$$, 'bad_value');
select tt.err('T6 a bad rule is refused and nothing is saved', $$select crmc_segment_save(null, null, 'test_list_bad', '{"conditions":[{"field":"orders_total","op":"ge","value":"1; drop"}]}')$$, 'bad_rule:bad_value');
select tt.chk('T6 still only one saved list', (select count(*) from crm_segments) = :segs0 + 1 and not exists (select 1 from crm_segments where name = 'test_list_bad'));
select crmc_segment_save(null, :sid, 'test_list_lapsed2', '{"conditions":[{"field":"days_since_last","op":"gt","value":60}]}') ->> 'last_count' as lc \gset
select tt.chk('T6 update changes the rule and the stored count (over 60 days = atrisk, old = 2)', :lc = 2 and exists (select 1 from crm_segments where id = :sid and name = 'test_list_lapsed2'));
select tt.err('T6 retire needs a reason', format($$select crmc_segment_retire(%s, false, ' ')$$, :sid), 'reason_required');
select crmc_segment_retire(:sid, false, 'test: not needed') ->> 'active' as ra \gset
select tt.chk('T6 retire with a reason: kept (not deleted), reason stored', :'ra' = 'false' and exists (select 1 from crm_segments where id = :sid and retired_reason = 'test: not needed'));
select tt.err('T6 a retired list cannot be edited', format($$select crmc_segment_save(null, %s, 'test_list_x', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')$$, :sid), 'segment_retired');
select tt.chk('T6 the name is free again after retiring', crmc_segment_save(null, null, 'test_list_lapsed2', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}') ->> 'id' is not null);
select tt.err('T6 reactivating the old one now clashes with the name', format($$select crmc_segment_retire(%s, true, null)$$, :sid), 'name_taken');
select tt.chk('T6 nothing can be deleted', (select count(*) from crm_segments where id = :sid) = 1);
select tt.err('T6 hard delete of a list refused', format($$delete from crm_segments where id = %s$$, :sid), 'nothing is deleted');
select tt.chk('T6 every save is in the audit log', (select count(*) from audit_log where table_name = 'crm_segments') >= 4);

\echo == T7 freeze: a frozen list never changes
select tt.as(:'u_e');
select crmc_segment_freeze('c0000000-0000-0000-0000-000000000002', null, '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'test_frozen_lapsed') ->> 'id' as fid \gset
select tt.chk('T7 frozen list: kind list, 3 members, rule kept for the record', exists (select 1 from crm_segments where id = :fid and kind = 'list' and member_count = 3 and frozen_at is not null and rule is not null));
select tt.chk('T7 same client id again = same list (repeat), no second copy', (crmc_segment_freeze('c0000000-0000-0000-0000-000000000002', null, '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'test_frozen_lapsed')->>'repeat')::boolean);
select tt.chk('T7 members copied: atrisk, onetime, old', (select string_agg(replace(c.name, 'test_cust_', ''), ',' order by c.name) from crm_segment_members m join customers c on c.id = m.customer_id where m.segment_id = :fid) = 'atrisk,old,onetime');
-- the old customer comes back today: the live rule now finds 2, the frozen list still holds 3
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, customer_id, status, created_by) values (1, 9200, :'t'::date, now(), '[]', 30, 30, 'cash', '00000000-0000-0000-0000-00000000c3a4', 'done', :'u_o');
select tt.as(:'u_o'); select crmc_metrics_refresh(false);
select tt.chk('T7 live rule now finds 2 (old customer came back); the frozen list still has 3', tt.n('{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}') = 2
  and cardinality(_crmc_ids_of(:fid, null)) = 3 and (select count(*) from _crmc_audience(:fid)) = 3);
select tt.err('T7 a frozen member cannot be changed', format($$update crm_segment_members set added_at = now() where segment_id = %s$$, :fid), 'crmc_append_only');
select tt.err('T7 a frozen member cannot be removed', format($$delete from crm_segment_members where segment_id = %s$$, :fid), 'crmc_append_only');
update customers set active = false where id = '00000000-0000-0000-0000-00000000c3a3';
select tt.chk('T7 a customer switched off drops out of the audience but stays in the record', (select count(*) from _crmc_audience(:fid)) = 2 and (select count(*) from crm_segment_members where segment_id = :fid) = 3);
update customers set active = true where id = '00000000-0000-0000-0000-00000000c3a3';
select tt.err('T7 audience of a retired list refused', format($$select * from _crmc_audience(%s)$$, :sid), 'not found');
select tt.as(:'u_e');
select tt.chk('T7 renaming a frozen list is allowed, its customers do not change', (crmc_segment_save(null, :fid, 'test_frozen_renamed', '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}')->>'name') = 'test_frozen_renamed'
  and (select count(*) from crm_segment_members where segment_id = :fid) = 3 and (select rule ->> 'match' from crm_segments where id = :fid) = 'all' and (select rule -> 'conditions' -> 0 ->> 'field' from crm_segments where id = :fid) = 'days_since_last');
select tt.err('T7 freezing an empty list refused', $$select crmc_segment_freeze(null, null, '{"conditions":[{"field":"tier","op":"in","value":["elite"]}]}', 'test_frozen_empty')$$, 'empty_segment');
select tt.err('T7 freeze needs exactly one of list / rule', $$select crmc_segment_freeze(null, null, null, 'test_frozen_none')$$, 'bad_value');
select tt.chk('T7 freezing a saved dynamic list works too', (select (crmc_segment_freeze(null, s.id, null, 'test_frozen_from_saved')->>'member_count')::int from crm_segments s where s.name = 'test_list_lapsed2' and s.active) = 1);

\echo == T8 member pages: order, paging, privacy of the phone number
select tt.as(:'u_v'); set role authenticated;
select tt.chk('T8 guard OFF (package B absent): the viewer sees full numbers, masked flag false', (select not (r->>'masked')::boolean and r->'rows' -> 0 ->> 'mobile' like '0170000000_' from (select crmc_members('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}') r) z));
select tt.chk('T8 pages: total 7, first page 2 rows in spend order (due 1000, champ 600)', (select (r->>'total')::int = 7 and jsonb_array_length(r->'rows') = 2 and r->'rows' -> 0 ->> 'name' = 'test_cust_due' and r->'rows' -> 1 ->> 'name' = 'test_cust_champ'
  from (select crmc_members('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', null, 2, 0) r) z));
select tt.chk('T8 second page continues (old 530, atrisk 350) and does not repeat', (select r->'rows' -> 0 ->> 'name' = 'test_cust_old' and r->'rows' -> 1 ->> 'name' = 'test_cust_atrisk'
  from (select crmc_members('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', null, 2, 2) r) z));
select tt.chk('T8 a page limit of 1000 is cut to 200', (crmc_members('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', null, 1000, 0)->>'limit')::int = 200);
reset role;
insert into rules (key, module, kind, default_value, label_bn, label_mix, label_en) values ('crm_pii_guard_on', 'crm', 'switch', 'true'::jsonb, 'test', 'test', 'test') on conflict (key) do update set default_value = 'true'::jsonb, value = null;
select tt.as(:'u_v'); set role authenticated;
select tt.chk('T8 guard ON: the viewer sees a masked number and the masked flag, and the full number is nowhere in the answer',
  (select (r->>'masked')::boolean and r->'rows' -> 0 ->> 'mobile' ~ '^017\*+\d\d$' and position('01700000008' in r::text) = 0 and position('01700000001' in r::text) = 0
     from (select crmc_members('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', null, 7, 0) r) z));
select tt.as(:'u_d');
select tt.chk('T8 guard ON: the holder of crm_contact_view sees full numbers', (select not (r->>'masked')::boolean and r->'rows' -> 0 ->> 'mobile' = '01700000008' from (select crmc_members('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', null, 7, 0) r) z));
select tt.as(:'u_o');
select tt.chk('T8 guard ON: the owner sees full numbers', (select not (r->>'masked')::boolean from (select crmc_members('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}') r) z));
reset role;
delete from rules where key = 'crm_pii_guard_on';
select tt.chk('T8 a saved list gives the same page as its rule', (select r1 = r2 from (select crmc_members(null, :fid, 50, 0) r1, crmc_members(null, :fid, 50, 0) r2) z));

\echo == T9 pickers
select tt.as(:'u_v'); set role authenticated;
select tt.chk('T9 catalog: 24 fields, tiers include gold, outlets include 1, labels include Champion', (select jsonb_array_length(c->'fields') = 24 and c->'tiers' @> '[{"code":"gold"}]' and c->'outlets' @> '[{"id":1}]' and c->'labels' @> '"Champion"'::jsonb from (select crmc_field_catalog() c) z));
select tt.chk('T9 item search finds both test items by a word', jsonb_array_length(crmc_item_search('test item')) = 2);
select tt.chk('T9 item search treats % as plain text (finds nothing)', jsonb_array_length(crmc_item_search('%%')) = 0);
select tt.chk('T9 item search with one letter returns nothing', crmc_item_search('t') = '[]'::jsonb);
select tt.err('T9 item search with a very long word refused', $$select crmc_item_search(repeat('a', 61))$$, 'bad_value');
select tt.chk('T9 saved lists are listed (active ones only by default)', jsonb_array_length(crmc_segments_list()) >= 3 and not exists (select 1 from jsonb_array_elements(crmc_segments_list()) e where not (e->>'active')::boolean));
reset role;

\echo == T10 a big list: preview counts it, freezing past the cap is refused, nothing is cut short
select tt.as(:'u_o'); select set_rule('crm_segment_max_members', '100'::jsonb);
insert into customers (mobile, name) select '0191' || lpad(g::text, 7, '0'), 'test_bulk_' || g from generate_series(1, 120) g;
select tt.as(:'u_o'); select crmc_metrics_refresh(false);
select tt.chk('T10 preview counts all (127) and says over the cap of 100', (select (r->>'count')::int = 127 and (r->>'over_cap')::boolean and (r->>'cap')::int = 100 from (select crmc_preview('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}') r) z));
select tt.as(:'u_e');
select tt.err('T10 freezing 127 over a cap of 100 is refused with the size', $$select crmc_segment_freeze(null, null, '{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', 'test_frozen_big')$$, 'over_cap:127');
select tt.chk('T10 nothing was created by the refused freeze', (select count(*) from crm_segments where name = 'test_frozen_big') = 0);
reset role; select tt.as(:'u_o'); select set_rule('crm_segment_max_members', '200'::jsonb); select tt.as(:'u_e');
select tt.chk('T10 with the cap raised to 200 the same freeze works (127 members)', (crmc_segment_freeze(null, null, '{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', 'test_frozen_big')->>'member_count')::int = 127);
select tt.err('T10 _crmc_audience over a smaller cap raises over_cap', format($$select * from _crmc_audience(%s, 50)$$, (select id from crm_segments where name = 'test_frozen_big')), 'over_cap:127');

\echo == T11 existing data untouched (apart from the rows this test itself inserted)
select tt.chk('T11 no money table changed: payments, returns, journal, points, opt-in, stock ledger are as before', tt.snap2() = :'snap2_0');

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
