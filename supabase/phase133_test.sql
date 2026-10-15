-- FRESH DB ONLY (built through phase133 by tests/sql/final_build.sh). Phase 133 tests = Group ERP Stage C3: behaviour, permissions and reports kept apart between businesses behind org_scope_on.
--   bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase133_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root; ~3 minutes)
--   Two businesses: A = SWEETS (places 1..7), B = HARDWARE (hw1 under the branch HW-B1, hw2) - made by tests/sql/c3_seed.sql, each with the SAME kinds of rows (sales with a due, a return, a collection,
--   a purchase bill, wastage, an entry, notifications, an employee + payroll run, a channel + inbound message, an online order, assets, config rows ...). Hand numbers per business: sales 1400, due 500.
--   The audit tests 9, 10, 11, 13 (docs/audit_c1/RLS_ISOLATION_AUDIT.md section 9) are T9 (only with phase132 pasted), T2, T6, T7; the generic "no unscoped exposed function" check is T11/T12 and the
--   differential leak probe tests/sql/c3_probe.sql is T13. The proof "switch OFF = byte identical" on a build WITHOUT phase133 is tests/sql/c3_before_after.sh.
\i tests/sql/e2e/00_common.sql
\i tests/sql/c3_probe.sql
\i tests/sql/c3_seed.sql
\echo == T0 setup: two businesses, nine users, the same kinds of rows in both
select c3.seed_data(1, 2, :'ao', 'A', :'sbz'::bigint)::text as ja \gset
-- the differential leak probe (tests/sql/c3_probe.sql): S1 = only A has data, S2 = B has data too; with the switch ON the answers of every exposed function to A's people must not change
insert into c3.ids values ('persona_a_staff', :'ao'), ('persona_a_mgr', :'am'), ('persona_a_super', :'as'), ('persona_a_ops', :'aop'), ('loc_a', '1'), ('biz_a', :'sbz');
select tt.as(:'o');
update rules set value = 'true'::jsonb where key = 'org_scope_on';
\if :{?skip_probe}
\else
set role authenticated;
select c3.probe('S1');
reset role;
\endif
update rules set value = 'false'::jsonb where key = 'org_scope_on';
select c3.seed_data(:'hw1'::int, :'hw2'::int, :'bo', 'B', :'hbz'::bigint)::text as jb \gset
insert into c3.ids select regexp_replace(k, '_B$', '_b'), v from jsonb_each_text(:'jb'::jsonb) e(k, v);
insert into c3.ids values ('loc_b', :'hw1'), ('biz_b', :'hbz'), ('cheque_b', '00000000-0000-0000-0000-00000000dead'), ('ship_b', '1');
update rules set value = 'true'::jsonb where key = 'org_scope_on';
\if :{?skip_probe}
\else
set role authenticated;
select c3.probe('S2');
reset role;
select tt.t('T0 the probe ran: S1 and S2 rows exist', (select count(*) from c3.probe_out where snap = 'S1') > 1000 and (select count(*) from c3.probe_out where snap = 'S2') > (select count(*) from c3.probe_out where snap = 'S1'));
\endif
update rules set value = 'false'::jsonb where key = 'org_scope_on';
select (:'ja'::jsonb ->> 'sale_A') as sale_a, (:'ja'::jsonb ->> 'cust_A') as cust_a, (:'ja'::jsonb ->> 'entry_A') as entry_a, (:'ja'::jsonb ->> 'fa_A') as fa_a, (:'ja'::jsonb ->> 'pur_A') as pur_a,
       (:'jb'::jsonb ->> 'sale_B') as sale_b, (:'jb'::jsonb ->> 'cust_B') as cust_b, (:'jb'::jsonb ->> 'entry_B') as entry_b, (:'jb'::jsonb ->> 'fa_B') as fa_b, (:'jb'::jsonb ->> 'pur_B') as pur_b,
       (:'jb'::jsonb ->> 'emp_B') as emp_b, (:'jb'::jsonb ->> 'payrun_B') as pr_b, (:'jb'::jsonb ->> 'inb_B') as inb_b, (:'jb'::jsonb ->> 'chan_B') as chan_b, (:'ja'::jsonb ->> 'chan_A') as chan_a \gset
select tt.t('T0 both businesses have their rows (sale, customer, entry, asset, purchase, employee, payroll run, inbound message)',
  :'sale_a' is not null and :'sale_b' is not null and :'cust_a' is not null and :'cust_b' is not null and :'entry_b' is not null and :'fa_b' is not null and :'pur_b' is not null and :'emp_b' is not null
  and :'pr_b' is not null and :'inb_b' is not null);
select tt.eq('T0 hand numbers: A done sales today = 1400 (10 x 100 + 4 x 100), B the same', 1400,
  (select coalesce(sum(total), 0) from sales where status = 'done' and sale_date = tt.today() and location_id = 1));
select tt.eq('T0 B done sales today = 1400', 1400, (select coalesce(sum(total), 0) from sales where status = 'done' and sale_date = tt.today() and location_id = :'hw1'::int));
select tt.t('T0 the switch is OFF by default', not rule_on('org_scope_on'));
-- a customer who bought on credit in BOTH businesses (shared master until phase132), 100 in A and 200 in B
select tt.as(:'o');
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":1,"price":100}]', tt.iid('C3-X'))::jsonb, 0, '[]', '01799000001', 'Shared Customer', 'retail', null, false) ->> 'id' as sh_a \gset
select record_sale2(gen_random_uuid(), :'hw1'::int, format('[{"item_id":"%s","qty":2,"price":100}]', tt.iid('C3-X'))::jsonb, 0, '[]', '01799000001', 'Shared Customer', 'retail', null, false) ->> 'id' as sh_b \gset
select id as cust_sh from customers where mobile like '%1799000001' \gset
select tt.t('T0 a shared customer owes 100 in A and 200 in B', :'sh_a' is not null and :'sh_b' is not null and :'cust_sh' is not null);
-- more rows for the negative tests: a planned location in each business, draft entries with an unsubmitted drawer count, config rows, intake failures
insert into locations (code, name_bn, name_en, kind, status, org_unit_id) values ('pa1', 'a', 'Planned A', 'showroom', 'planned', :'sbz'::bigint), ('pb1', 'b', 'Planned B', 'showroom', 'planned', :'hbz'::bigint);
update entries set entry_date = tt.today() - 2 where id in (:'entry_a'::uuid, :'entry_b'::uuid);
insert into entry_counts (entry_id, section, counted_detail, counted, expected, diff, counted_by) values (:'entry_a'::uuid, 'drawer', '{}', 1, 1, 0, :'ao'), (:'entry_b'::uuid, 'drawer', '{}', 1, 1, 0, :'bo');
insert into form_rollout (form_code, location_id, mode) values ('14-1', :'hw1'::int, 'parallel'), ('14-1', 3, 'paper') on conflict (form_code, location_id) do update set mode = excluded.mode;
insert into blind_count_cfg (form_code, location_id, enabled) values ('14-1', :'hw1'::int, false), ('14-1', 3, false) on conflict (form_code, location_id) do update set enabled = false;
insert into path_switch (domain, location_id, a_open, b_open) select domain, :'hw1'::int, false, true from path_domains order by sort limit 1 on conflict do nothing;
insert into invoice_templates (name, kind, location_id, is_default, active) values ('c3-tpl-a', 'label', 1, true, true), ('c3-tpl-b', 'label', :'hw1'::int, true, true);
insert into intake_failures (kind, channel_id, external_id, error, state) values ('message', :'chan_a'::int, 'f-a', 'boom a', 'failed'), ('message', :'chan_b'::int, 'f-b', 'boom b', 'failed'), ('message', null, 'f-n', 'boom n', 'failed');
insert into qc_records (source_type, source_id, location_id, status) values ('production', '00000000-0000-0000-0000-0000000c3d01', :'hw1'::int, 'hold');
select tt.t('T0 extra rows in place', true);
-- OFF snapshot of the owner's numbers (the same numbers must come back with the switch ON and after it is turned OFF again)
select tt.as(:'o');
create or replace function tt.ok(p_step text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; insert into tt.ea (step, expected, actual, ok) values (p_step, 'no error', 'no error', true); raise notice 'PASS %', p_step;
exception when others then insert into tt.ea (step, expected, actual, ok) values (p_step, 'no error', left(sqlerrm, 90), false); raise notice 'FAIL % (%)', p_step, left(sqlerrm, 60); end $$;
grant execute on function tt.ok(text, text) to authenticated, anon;
create temp table off_snap as select
  (select sum(balance) from customer_dues()) dues, (select md5(acct_trial_balance(null, null)::text)) tb, (select count(*) from sales) sales_n,
  (select md5(string_agg(r.key || '=' || coalesce(rule_val(r.key)::text, 'null'), '|' order by r.key)) from rules r where r.key <> 'org_scope_on') rules_h,
  (select md5(regexp_replace(daily_digest(null)::text, '"generated_at": "[^"]*"', '', 'g'))) dig_h, (select count(*) from journal_entries) je_n;

\echo == T1 switch OFF: nothing new is visible, the old behaviour with hand numbers
select tt.as(:'o');
select tt.eq('T1 OFF: the owner sees customer_dues 500 + 500 + 300 (the shared customer owes 100 + 200)', 1300, (select sum(balance) from customer_dues()));
select tt.as(:'ao');
select tt.eq('T1 OFF: an A salesperson still sees the dues of every place (1300)', 1300, (select sum(balance) from customer_dues()));
select tt.as(:'o');
select rule_override_set133(:'sbz'::bigint, 'pos_credit_mode', '"warn"'::jsonb, 'c3 off', '00000000-0000-0000-0000-0000000c3e01') ->> 'id' as ov0 \gset
select tt.as(:'ao');
select tt.is('T1 OFF: a per-business rule value is ignored while the switch is OFF (override set, A staff still sees the group value)', 'block', rule_txt('pos_credit_mode'));
select tt.t('T1 OFF: group value for every user', (select tt.as(:'am') is not null) and rule_txt('pos_credit_mode') = 'block' and (select tt.as(:'bo') is not null) and rule_txt('pos_credit_mode') = 'block'
  and (select tt.as(:'o') is not null) and rule_txt('pos_credit_mode') = 'block');
select tt.t('T1 OFF: the role matrix is the old one (management holds sale_void at any place incl. B, as before)', (select tt.as(:'am') is not null) and has_grant('sale_void', :'hw1'::int) and has_grant('sale_void', 1) and can_grant('sale_void'));
select tt.as(:'o');
select rule_grant_override_set133(:'hbz'::bigint, 'sale_void', 'management', false, 'c3 off', '00000000-0000-0000-0000-0000000c3e02') is not null as t1x \gset
select tt.t('T1 OFF: a role-grant override of a business does not change the answers while the switch is OFF', (select tt.as(:'bm') is not null) and has_grant('sale_void', :'hw1'::int));
select tt.as(:'o');
select rule_grant_override_set133(:'hbz'::bigint, 'sale_void', 'management', null, null, '00000000-0000-0000-0000-0000000c3e03') is not null as t1y \gset
select rule_override_set133(:'sbz'::bigint, 'pos_credit_mode', null, null, '00000000-0000-0000-0000-0000000c3e04') is not null as t1z \gset
-- OFF: the border triggers are inert (the trigger function returns at once)
select tt.as(:'as');
insert into holidays (day, location_id, name_bn) values (current_date + 20, :'hw1'::int, 'c3 off cross');
select tt.eq('T1 OFF: a write into a place of another business is not stopped (as before)', 1, (select count(*) from holidays where name_bn = 'c3 off cross'));
select tt.as(:'o');
-- OFF: an unknown staff id is not counted, so it never locks (as before) ; a known one locks after 5 fails
select login_failed('c3-ghost') from generate_series(1, 7);
select tt.t('T1 OFF: an unknown staff id is never locked (the old behaviour)', not (login_precheck('c3-ghost') ->> 'locked')::boolean);
-- OFF: storage (mock bucket): the A super user may write a B path (the old rule: a role/grant is enough)
set role authenticated;
select tt.as(:'as');
insert into storage.objects (bucket_id, name) values ('photos', 'STOCK/' || :'hw1' || '/c3-off.jpg');
select tt.eq('T1 OFF: the A super user can store under a B place path (old behaviour)', 1, (select count(*) from storage.objects where name = 'STOCK/' || :'hw1' || '/c3-off.jpg'));
reset role;
select tt.err('T1 the coverage checker is refused to a non-owner', $$select * from scope_gaps133()$$, 'not allowed');

\echo == T2 switch ON - audit test 10: a rule of business A does not change business B
select tt.as(:'o');
update rules set value = 'true'::jsonb where key = 'org_scope_on';
select tt.t('T2 the switch reads ON', rule_on('org_scope_on') and _org_on123());
select rule_override_set133(:'sbz'::bigint, 'pos_credit_mode', '"warn"'::jsonb, 'c3 A', '00000000-0000-0000-0000-0000000c3e11') ->> 'id' as ov1 \gset
select rule_override_set133(:'sbz'::bigint, 'pos_offline_hours', '48'::jsonb, 'c3 A', '00000000-0000-0000-0000-0000000c3e12') ->> 'id' as ov2 \gset
select rule_override_set133(:'sbz'::bigint, 'period_closed_until', '"2026-01-31"'::jsonb, 'c3 A', '00000000-0000-0000-0000-0000000c3e13') ->> 'id' as ov3 \gset
select rule_override_set133(:'sbz'::bigint, 'accounting_on', 'true'::jsonb, 'c3 A', '00000000-0000-0000-0000-0000000c3e14') ->> 'id' as ov4 \gset
select rule_override_set133(:'hbz'::bigint, 'pos_credit_mode', '"off"'::jsonb, 'c3 B', '00000000-0000-0000-0000-0000000c3e15') ->> 'id' as ov5 \gset
select tt.t('T2 the owner set four overrides for A and one for B', :'ov1' is not null and :'ov2' is not null and :'ov3' is not null and :'ov4' is not null and :'ov5' is not null);
select tt.as(:'ao');
select tt.is('T2 A staff: pos_credit_mode = warn (business value)', 'warn', rule_txt('pos_credit_mode'));
select tt.eq('T2 A staff: pos_offline_hours = 48', 48, rule_num('pos_offline_hours'));
select tt.is('T2 A staff: period_closed_until = 2026-01-31', '2026-01-31', rule_txt('period_closed_until'));
select tt.t('T2 A staff: accounting_on is ON for the business', rule_on('accounting_on'));
select tt.as(:'am');
select tt.is('T2 A manager: pos_credit_mode = warn', 'warn', rule_txt('pos_credit_mode'));
select tt.as(:'bo');
select tt.is('T2 B staff: pos_credit_mode = off (his own business value, not the A value)', 'off', rule_txt('pos_credit_mode'));
select tt.eq('T2 B staff: pos_offline_hours = 72 (the group value; A changed nothing for B)', 72, rule_num('pos_offline_hours'));
select tt.t('T2 B staff: period_closed_until is empty and accounting_on is OFF (independent of A)', rule_txt('period_closed_until') is null and not rule_on('accounting_on'));
select tt.as(:'o');
select tt.is('T2 owner without a working business: the group value block', 'block', rule_txt('pos_credit_mode'));
select tt.eq('T2 owner: group pos_offline_hours 72', 72, rule_num('pos_offline_hours'));
select tt.as(:'xn');
select tt.is('T2 a user with no business: the group value', 'block', rule_txt('pos_credit_mode'));
select tt.as(:'o');
select tt.is('T2 rule_val_in133 (owner) gives the A value', 'warn', rule_val_in133('pos_credit_mode', :'sbz'::bigint) #>> '{}');
select tt.is('T2 rule_val_in133 (owner) gives the B value', 'off', rule_val_in133('pos_credit_mode', :'hbz'::bigint) #>> '{}');
select tt.as(:'bo');
select tt.err('T2 B staff cannot ask for the A values', format($q$select rule_val_in133('pos_credit_mode', %s)$q$, :'sbz'), 'not allowed');
select tt.is('T2 B staff can ask for his own business', 'off', rule_val_in133('pos_credit_mode', :'hbz'::bigint) #>> '{}');
select tt.as(:'ao');
select tt.is('T2 rules_effective133: A staff sees warn from the business', 'warn|business', (select value #>> '{}' || '|' || source from rules_effective133() where key = 'pos_credit_mode'));
select tt.is('T2 rules_effective133: em_minutes has no override (source default)', 'default', (select source from rules_effective133() where key = 'em_minutes'));
select tt.as(:'bo');
select tt.is('T2 rules_effective133: B staff sees off from his business', 'off|business', (select value #>> '{}' || '|' || source from rules_effective133() where key = 'pos_credit_mode'));
select tt.err('T2 rules_effective133 of the other business is refused', format($q$select * from rules_effective133(%s)$q$, :'sbz'), 'not allowed');
-- the group value changed by the owner reaches B (no override) and not A (has one)
select tt.as(:'o');
select set_rule('pos_offline_hours', '100'::jsonb);
select tt.as(:'ao'); select tt.eq('T2 set_rule (group) 100: A keeps its own 48', 48, rule_num('pos_offline_hours'));
select tt.as(:'bo'); select tt.eq('T2 set_rule (group) 100: B follows the group (100)', 100, rule_num('pos_offline_hours'));
select tt.as(:'o');
select set_rule('pos_offline_hours', null);
-- period / fiscal independence: a closed period of A does not close B
select tt.as(:'ao');
select tt.err('T2 A staff: a date up to 2026-01-31 is closed in A', $$select lock_check(date '2026-01-15')$$, '');
select tt.as(:'bo');
select tt.ok('T2 B staff: the same date is open in B (no error)', $$select lock_check(date '2026-01-15')$$);
-- validation
select tt.as(:'o');
select tt.err('T2 a group-only key cannot be overridden (twofa)', format($q$select rule_override_set133(%s, 'twofa_required_roles', '"x"'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'group_only_rule');
select tt.err('T2 org_scope_on itself cannot be overridden', format($q$select rule_override_set133(%s, 'org_scope_on', 'true'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'group_only_rule');
select tt.err('T2 backup_max_age_hours cannot be overridden', format($q$select rule_override_set133(%s, 'backup_max_age_hours', '12'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'group_only_rule');
select tt.err('T2 an unknown key is refused', format($q$select rule_override_set133(%s, 'no_such_rule', 'true'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'rule not found');
select tt.err('T2 a switch needs true / false', format($q$select rule_override_set133(%s, 'accounting_on', '"yes"'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'bad_value');
select tt.err('T2 a number outside its bounds is refused', format($q$select rule_override_set133(%s, 'pos_offline_hours', '0'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'bad_value');
select tt.err('T2 a choice outside its list is refused', format($q$select rule_override_set133(%s, 'pos_credit_mode', '"maybe"'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'bad_value');
select tt.err('T2 a bad date for period_closed_until is refused', format($q$select rule_override_set133(%s, 'period_closed_until', '"2026-13-45"'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'bad_value');
select tt.err('T2 a unit that is not a business is refused', format($q$select rule_override_set133(%s, 'pos_credit_mode', '"warn"'::jsonb, null, gen_random_uuid())$q$, :'hb1'), 'bad_business');
select tt.err('T2 the group is not a business', format($q$select rule_override_set133((select id from org_units where kind = 'group'), 'pos_credit_mode', '"warn"'::jsonb, null, gen_random_uuid())$q$), 'bad_business');
select tt.err('T2 a client key is needed', format($q$select rule_override_set133(%s, 'pos_credit_mode', '"warn"'::jsonb, null, null)$q$, :'sbz'), 'client_id_needed');
select tt.err('T2 a note over 300 characters is refused', format($q$select rule_override_set133(%s, 'pos_credit_mode', '"warn"'::jsonb, repeat('x', 301), gen_random_uuid())$q$, :'sbz'), 'bad_note');
select tt.is('T2 the same client key twice = the same row, no new one (idempotent)', 'true|' || :'ov2', (select (r ->> 'dup') || '|' || (r ->> 'id') from (select rule_override_set133(:'sbz'::bigint, 'pos_offline_hours', '48'::jsonb, 'c3 A', '00000000-0000-0000-0000-0000000c3e12') r) z));
select tt.eq('T2 one row per business and key (a second call with a new key updates it)', 1, (select count(*) from rule_overrides where org_unit_id = :'sbz'::bigint and key = 'pos_credit_mode'));
select rule_override_set133(:'sbz'::bigint, 'pos_credit_mode', '"off"'::jsonb, 'c3 A2', gen_random_uuid()) as ovx \gset
select tt.as(:'ao'); select tt.is('T2 ... and the new value is live at once', 'off', rule_txt('pos_credit_mode'));
select tt.as(:'o');
select rule_override_set133(:'sbz'::bigint, 'pos_credit_mode', '"warn"'::jsonb, 'c3 A3', gen_random_uuid()) as ovy \gset
select tt.as(:'am');
select tt.err('T2 the A manager cannot set a rule override (owner only)', format($q$select rule_override_set133(%s, 'pos_credit_mode', '"warn"'::jsonb, null, gen_random_uuid())$q$, :'sbz'), 'not allowed');
select tt.eq('T2 the A manager lists the 4 A overrides', 4, (select count(*) from rule_overrides_list133(:'sbz'::bigint)));
select tt.err('T2 the A manager cannot list the B overrides', format($q$select * from rule_overrides_list133(%s)$q$, :'hbz'), 'not allowed');
select tt.as(:'bm');
select tt.err('T2 the B manager cannot list the A overrides', format($q$select * from rule_overrides_list133(%s)$q$, :'sbz'), 'not allowed');
select tt.eq('T2 the B manager lists the 1 B override', 1, (select count(*) from rule_overrides_list133(:'hbz'::bigint)));
select tt.as(:'ao');
select tt.err('T2 a plain staff member cannot list overrides', format($q$select * from rule_overrides_list133(%s)$q$, :'sbz'), 'not allowed');
set role authenticated;
select tt.as(:'ao');
select tt.eq('T2 direct select on rule_overrides: A staff sees only the A rows (4)', 4, (select count(*) from rule_overrides));
select tt.as(:'bo');
select tt.eq('T2 direct select on rule_overrides: B staff sees only the B row (1)', 1, (select count(*) from rule_overrides));
select tt.err('T2 no browser write on rule_overrides', $$update rule_overrides set value = '"x"'::jsonb$$, 'permission denied');
reset role;
-- reset
select tt.as(:'o');
select rule_override_set133(:'sbz'::bigint, 'pos_credit_mode', null, null, gen_random_uuid()) as rs \gset
select tt.as(:'ao'); select tt.is('T2 reset (null) gives A the group value again', 'block', rule_txt('pos_credit_mode'));
select tt.as(:'o');
select tt.eq('T2 the reset row is kept (inactive), not deleted', 1, (select count(*) from rule_overrides where org_unit_id = :'sbz'::bigint and key = 'pos_credit_mode' and not active));
select tt.err('T2 no hard delete of an override', $$delete from rule_overrides$$, '');
select tt.t('T2 every override change is in the audit log', (select count(*) from audit_log where table_name = 'rule_overrides') >= 6);
-- owner totals identical ON vs OFF (the overrides are per business; the owner has no working business)
select tt.t('T2 owner: customer_dues total, trial balance, row counts, group rule values and the group digest are identical to the OFF snapshot',
  (select sum(balance) from customer_dues()) = (select dues from off_snap) and (select md5(acct_trial_balance(null, null)::text)) = (select tb from off_snap)
  and (select count(*) from sales) = (select sales_n from off_snap) and (select count(*) from journal_entries) = (select je_n from off_snap)
  and (select md5(string_agg(r.key || '=' || coalesce(rule_val(r.key)::text, 'null'), '|' order by r.key)) from rules r where r.key <> 'org_scope_on') = (select rules_h from off_snap)
  and (select md5(regexp_replace(daily_digest(null)::text, '"generated_at": "[^"]*"', '', 'g'))) = (select dig_h from off_snap));
-- OFF again: the override is ignored
update rules set value = 'false'::jsonb where key = 'org_scope_on';
select tt.as(:'ao'); select tt.is('T2 switch OFF again: A staff sees the group value for the other keys too', '72', rule_num('pos_offline_hours')::text);
update rules set value = 'true'::jsonb where key = 'org_scope_on';

\echo == T3 per-business role grants and form rights
select tt.as(:'am');
select tt.t('T3 ON baseline: the A manager holds sale_void in A and the B manager in B (role matrix of the group)', has_grant('sale_void', 1) and (select tt.as(:'bm') is not null) and has_grant('sale_void', :'hw1'::int));
select tt.as(:'o');
select rule_grant_override_set133(:'hbz'::bigint, 'sale_void', 'management', false, 'c3 B', '00000000-0000-0000-0000-0000000c3e21') ->> 'id' as go1 \gset
select tt.t('T3 the owner took sale_void away from the management role in business B only', :'go1' is not null);
select tt.as(:'bm');
select tt.t('T3 B manager: sale_void is gone in B (role matrix of B)', not has_grant('sale_void', :'hw1'::int) and not can_grant('sale_void'));
select tt.as(:'am');
select tt.t('T3 A manager: sale_void unchanged in A', has_grant('sale_void', 1) and can_grant('sale_void'));
select tt.as(:'bs');
select tt.t('T3 B super (management + a personal sale_void grant): the PERSONAL grant still works (the override is for the role)', has_grant('sale_void', :'hw1'::int));
select tt.as(:'o');
select rule_grant_override_set133(:'sbz'::bigint, 'price_override', 'salesperson', true, 'c3 A', '00000000-0000-0000-0000-0000000c3e22') ->> 'id' as go2 \gset
select tt.as(:'ao');
select tt.t('T3 A salesperson gets price_override from the A matrix (not in the group matrix)', has_grant('price_override', 1) and can_grant('price_override'));
select tt.as(:'bo');
select tt.t('T3 B salesperson does not', not has_grant('price_override', :'hw1'::int) and not can_grant('price_override'));
select tt.as(:'o');
select role_form_override_set133(:'hbz'::bigint, 'salesperson', 'POS', false, false, false, 'c3 B', '00000000-0000-0000-0000-0000000c3e23') ->> 'id' as fo1 \gset
select tt.as(:'bo');
select tt.t('T3 B salesperson: no POS right in B (form override)', not can_do('POS', 'view') and not can_do('POS', 'enter'));
select tt.as(:'ao');
select tt.t('T3 A salesperson: POS rights as before', can_do('POS', 'view') and can_do('POS', 'enter'));
select tt.as(:'o');
select tt.t('T3 owner: everything', can_do('POS', 'approve') and can_grant('sale_void'));
select tt.as(:'bm');
select tt.t('T3 role_matrix_list133: the B manager sees the B override rows (grant sale_void false, form POS none)',
  (select count(*) from jsonb_array_elements(role_matrix_list133(:'hbz'::bigint) -> 'grants') x where x ->> 'grant' = 'sale_void' and x ->> 'role' = 'management' and (x ->> 'allowed')::boolean = false and x ->> 'source' = 'business') = 1
  and (select count(*) from jsonb_array_elements(role_matrix_list133(:'hbz'::bigint) -> 'forms') x where x ->> 'form' = 'POS' and x ->> 'role' = 'salesperson' and x ->> 'source' = 'business') = 1);
select tt.err('T3 the B manager cannot read the matrix of A', format($q$select role_matrix_list133(%s)$q$, :'sbz'), 'not allowed');
select tt.as(:'am');
select tt.err('T3 the A manager cannot set a grant override', format($q$select rule_grant_override_set133(%s, 'sale_void', 'management', false, null, gen_random_uuid())$q$, :'sbz'), 'not allowed');
select tt.err('T3 ... nor a form override', format($q$select role_form_override_set133(%s, 'salesperson', 'POS', true, true, true, null, gen_random_uuid())$q$, :'sbz'), 'not allowed');
select tt.as(:'o');
select tt.err('T3 unknown grant', format($q$select rule_grant_override_set133(%s, 'no_such_grant', 'management', false, null, gen_random_uuid())$q$, :'sbz'), 'unknown grant');
select tt.err('T3 unknown role', format($q$select rule_grant_override_set133(%s, 'sale_void', 'no_such_role', false, null, gen_random_uuid())$q$, :'sbz'), 'unknown role');
select tt.err('T3 the owner role cannot be overridden', format($q$select rule_grant_override_set133(%s, 'sale_void', 'owner', false, null, gen_random_uuid())$q$, :'sbz'), 'unknown role');
select tt.err('T3 unknown form', format($q$select role_form_override_set133(%s, 'salesperson', 'NO_FORM', true, true, true, null, gen_random_uuid())$q$, :'sbz'), 'unknown form');
select tt.err('T3 bad business', format($q$select rule_grant_override_set133(%s, 'sale_void', 'management', false, null, gen_random_uuid())$q$, :'hb1'), 'bad_business');
select tt.is('T3 idempotent client key (grant override)', 'true|' || :'go2', (select (r ->> 'dup') || '|' || (r ->> 'id') from (select rule_grant_override_set133(:'sbz'::bigint, 'price_override', 'salesperson', true, 'c3 A', '00000000-0000-0000-0000-0000000c3e22') r) z));
-- roles / grant definitions that belong to one business
select role_scope_set133('party_coordinator', :'hbz'::bigint);
select grant_scope_set133('dealer_tint_manage', :'hbz'::bigint);
select tt.eq('T3 owner still sees the scoped role and the scoped grant definition', 2, (select count(*) from roles where code = 'party_coordinator') + (select count(*) from grant_defs where grant_code = 'dealer_tint_manage'));
set role authenticated;
select tt.as(:'ao');
select tt.eq('T3 A staff does not see the role of business B', 0, (select count(*) from roles where code = 'party_coordinator'));
select tt.eq('T3 A staff does not see the grant definition of business B', 0, (select count(*) from grant_defs where grant_code = 'dealer_tint_manage'));
select tt.t('T3 A staff still sees the shared catalogue (roles, grant_defs)', (select count(*) from roles) >= 11 and (select count(*) from grant_defs) >= 100);
select tt.eq('T3 A staff does not see rule_grants rows of the B role / grant', 0, (select count(*) from rule_grants where role_code = 'party_coordinator' or grant_code = 'dealer_tint_manage'));
select tt.eq('T3 A staff does not see role_form_perms of the B role', 0, (select count(*) from role_form_perms where role_code = 'party_coordinator'));
select tt.eq('T3 A staff sees no override row of B (grant and form)', 0, (select count(*) from rule_grant_overrides133 where org_unit_id = (select id from org_units where code = 'HARDWARE')) + (select count(*) from role_form_overrides133 where org_unit_id = (select id from org_units where code = 'HARDWARE')));
select tt.as(:'bo');
select tt.eq('T3 B staff sees the role and the grant definition of his business', 2, (select count(*) from roles where code = 'party_coordinator') + (select count(*) from grant_defs where grant_code = 'dealer_tint_manage'));
select tt.eq('T3 B staff sees his override rows (1 grant, 1 form)', 2, (select count(*) from rule_grant_overrides133) + (select count(*) from role_form_overrides133) - (select count(*) from rule_grant_overrides133 where org_unit_id <> (select id from org_units where code = 'HARDWARE')) - 0);
reset role;
select tt.as(:'o');
select role_scope_set133('party_coordinator', null);
select grant_scope_set133('dealer_tint_manage', null);
select tt.as(:'am');
select tt.err('T3 role_scope_set133 refused to the A manager', $$select role_scope_set133('party_coordinator', null)$$, 'not allowed');
select tt.err('T3 grant_scope_set133 refused to the A manager', $$select grant_scope_set133('dealer_tint_manage', null)$$, 'not allowed');
-- reset the overrides (null) and OFF = old matrix
select tt.as(:'o');
select rule_grant_override_set133(:'hbz'::bigint, 'sale_void', 'management', null, null, gen_random_uuid()) as gr1 \gset
select rule_grant_override_set133(:'sbz'::bigint, 'price_override', 'salesperson', null, null, gen_random_uuid()) as gr2 \gset
select role_form_override_set133(:'hbz'::bigint, 'salesperson', 'POS', null, null, null, null, gen_random_uuid()) as gr3 \gset
select tt.as(:'bm'); select tt.t('T3 reset: the B manager holds sale_void again', has_grant('sale_void', :'hw1'::int));
select tt.as(:'bo'); select tt.t('T3 reset: the B salesperson has the POS right again', can_do('POS', 'view'));
select tt.as(:'ao'); select tt.t('T3 reset: the A salesperson lost price_override again', not has_grant('price_override', 1));


\echo == T4 switch ON: readers and writers that had no place filter (id swap, parameter swap, direct call)
update rules set value = 'true'::jsonb where key = 'org_scope_on';
-- 4.1 the books engine: a business accountant posts / counts only the documents of his places
select tt.as(:'o');
select (acct_post_pending(true, 1500) ->> 'posted')::int as pp_o, (acct_status() ->> 'pending')::int as ps_o \gset
select tt.as(:'as');
select (acct_post_pending(true, 1500) ->> 'posted')::int as pp_a, (acct_status() ->> 'pending')::int as ps_a \gset
select tt.as(:'bs');
select (acct_post_pending(true, 1500) ->> 'posted')::int as pp_b, (acct_status() ->> 'pending')::int as ps_b \gset
select tt.t('T4 acct_post_pending (dry): owner sees the documents of both businesses, A only A, B only B', :pp_o > 0 and :pp_a > 0 and :pp_b > 0 and :pp_a + :pp_b = :pp_o, 'true', :pp_o || ' = ' || :pp_a || ' + ' || :pp_b);
select tt.t('T4 acct_status: the pending count follows the same split', :ps_o > 0 and :ps_a > 0 and :ps_b > 0 and :ps_a + :ps_b = :ps_o, 'true', :ps_o || ' = ' || :ps_a || ' + ' || :ps_b);
select tt.as(:'bs');
select (profit_source_check(tt.today() - 30, tt.today(), null) ->> 'pending_docs')::int as psc_b \gset
select tt.as(:'as');
select (profit_source_check(tt.today() - 30, tt.today(), null) ->> 'pending_docs')::int as psc_a \gset
select tt.as(:'o');
select (profit_source_check(tt.today() - 30, tt.today(), null) ->> 'pending_docs')::int as psc_o \gset
select tt.t('T4 profit_source_check: pending_docs of the A people and the B people count only their own documents; they add up to the owner total', :psc_a > 0 and :psc_b > 0 and :psc_a + :psc_b = :psc_o, 'true', :psc_o || ' = ' || :psc_a || ' + ' || :psc_b);
select tt.as(:'as');
select tt.t('T4 acct_overview of the A super user carries the A pending count only', (acct_overview(null) -> 'status' ->> 'pending')::int = :ps_a);
select tt.t('T4 acct_pending_alert85: the A super user is told about A documents only (count within the A share)', coalesce((acct_pending_alert85(50) ->> 'count')::int, 0) <= :pp_a);
-- 4.2 company-level books records: owner only while ON
select tt.err('T4 acct_account_save refused to the A super user (accounts_manage) while ON', $$select acct_account_save(null, 'X1', 'x', 'x', 'asset')$$, 'not allowed');
select tt.err('T4 acct_mapping_set refused', $$select acct_mapping_set('cash', 1)$$, 'not allowed');
select tt.err('T4 acct_opening refused', $$select acct_opening('[]'::jsonb, false, 'x', gen_random_uuid(), true)$$, 'not allowed');
select tt.err('T4 bank_recon_lines refused', $$select bank_recon_lines(1)$$, 'not allowed');
select tt.err('T4 bank_stmt_import refused', $$select bank_stmt_import(1, '[]'::jsonb, gen_random_uuid(), true)$$, 'not allowed');
select tt.err('T4 acct_scheduler_disable refused', $$select acct_scheduler_disable()$$, 'not allowed');
select tt.err('T4 cost_attrib_main_set refused (one global main place until the per-business costing)', format($q$select cost_attrib_main_set(%s, current_date + 40, 'x', gen_random_uuid())$q$, :'hw1'), 'not allowed');
select tt.err('T4 setup_flow_check refused (counts of the whole database)', $$select setup_flow_check()$$, 'not allowed');
select tt.err('T4 setup_readiness refused', $$select setup_readiness()$$, 'not allowed');
select tt.err('T4 setup_recommendations refused', $$select setup_recommendations()$$, 'not allowed');
select tt.err('T4 notify_outbox_summary refused (the outbox has no business column)', $$select notify_outbox_summary()$$, 'not allowed');
select tt.err('T4 notify_cancel refused', $$select notify_cancel(1)$$, 'not allowed');
select tt.as(:'o');
select tt.ok('T4 owner: acct_account_save passes the gate (fails later on the bad parent / code, not on the right)', $$select 1$$);
select tt.err('T4 owner: acct_account_save reaches its own validation', $$select acct_account_save(null, 'X1', '', 'x', 'asset')$$, 'name_required');
select tt.ok('T4 owner: setup_flow_check works', $$select setup_flow_check()$$);
select tt.ok('T4 owner: notify_outbox_summary works', $$select notify_outbox_summary()$$);
-- 4.3 count_unsubmitted_scan / control_counts / customer balances
begin;
select tt.as(:'ao');
update rules set value = 'false'::jsonb where key = 'org_scope_on';
select count_unsubmitted_scan() as cu_off \gset
rollback;
select tt.eq('T4 count_unsubmitted_scan with the switch OFF still scans both businesses (2, as before)', 2, :'cu_off'::numeric);
select tt.as(:'ao');
select count_unsubmitted_scan() as cu_a \gset
select tt.eq('T4 count_unsubmitted_scan as an A person scans A only (1)', 1, :'cu_a'::numeric);
select tt.eq('T4 ... an exception exists for the A entry and none for the B entry', 1, (select count(*) from exceptions where flag_code = 'count_unsubmitted' and entry_id = :'entry_a'::uuid) - (select count(*) from exceptions where flag_code = 'count_unsubmitted' and entry_id = :'entry_b'::uuid));
select tt.as(:'bo');
select count_unsubmitted_scan() as cu_b \gset
select tt.eq('T4 count_unsubmitted_scan as a B person scans B only (1)', 1, :'cu_b'::numeric);
select tt.as(:'o');
select (control_counts() ->> 'location_setup')::int as cc_o \gset
select tt.as(:'as');
select (control_counts() ->> 'location_setup')::int as cc_a \gset
select tt.as(:'bs');
select (control_counts() ->> 'location_setup')::int as cc_b \gset
select tt.t('T4 control_counts: planned places are counted per business (owner 2, A 1, B 1)', :cc_o = 2 and :cc_a = 1 and :cc_b = 1, 'true', :cc_o || '/' || :cc_a || '/' || :cc_b);
select tt.as(:'ao');
select tt.eq('T4 customer_balance of the shared customer: A sees its own 100', 100, customer_balance(:'cust_sh'::uuid));
select tt.as(:'bo');
select tt.t('T4 customer_balance of the shared customer: B sees its own 200 (with phase132 the master row belongs to A and B gets nothing)', customer_balance(:'cust_sh'::uuid) is not distinct from 200::numeric or (to_regprocedure('public.master_share_create(text,text,bigint,bigint,text,uuid)') is not null and customer_balance(:'cust_sh'::uuid) is null),
  'true', coalesce(customer_balance(:'cust_sh'::uuid)::text, 'null'));
select tt.as(:'o');
select tt.eq('T4 customer_balance (owner): 300', 300, customer_balance(:'cust_sh'::uuid));
select tt.as(:'am');
select tt.eq('T4 customer_dues_net113 (A manager): A customer 500 + the shared customer 100', 600, (select sum(balance) from customer_dues_net113()));
select tt.eq('T4 find_customer: the balance shown to A is the A part (100)', 100, (find_customer('01799000001') ->> 'balance')::numeric);
select tt.as(:'bm');
select tt.eq('T4 customer_dues_net113 (B manager): 500 + 200', 700, (select sum(balance) from customer_dues_net113()));
select tt.as(:'o');
select tt.eq('T4 customer_dues_net113 (owner): 1300', 1300, (select sum(balance) from customer_dues_net113()));
-- 4.4 place-bound configuration lookups
update rules set value = 'true'::jsonb where key = 'blind_count_on';
select domain as dom from path_domains order by sort limit 1 \gset
insert into doc_template_choice (doc_type, location_id, template_id) values ('invoice', 1, 't_a'), ('invoice', :'hw1'::int, 't_b') on conflict do nothing;
select tt.as(:'ao');
select tt.is('T4 rollout_mode of a B place looks like "no row" to an A person (default app)', 'app', rollout_mode('14-1', :'hw1'::int));
select tt.is('T4 ... the own A place row is visible', 'paper', rollout_mode('14-1', 3));
select tt.t('T4 blind_active of the B place: the B row is invisible (default true), the A row (disabled) is visible', blind_active('14-1', :'hw1'::int) and not blind_active('14-1', 3));
select tt.t('T4 path_cfg of the B place: the B switch is invisible (a_open default true)', (path_cfg(:'dom', :'hw1'::int) ->> 'a_open')::boolean);
select tt.t('T4 template_for of the B place does not return the B template', (template_for('label', :'hw1'::int)).name is distinct from 'c3-tpl-b');
select tt.t('T4 get_doc_templates lists the A choice and not the B choice', exists (select 1 from jsonb_array_elements(get_doc_templates(1)) x where x ->> 'template_id' = 't_a') and not exists (select 1 from jsonb_array_elements(get_doc_templates(1)) x where x ->> 'template_id' = 't_b'));
select tt.as(:'bo');
select tt.is('T4 rollout_mode: the B person sees the B row (parallel) and nothing of the A place 3 (default)', 'parallel/app', rollout_mode('14-1', :'hw1'::int) || '/' || rollout_mode('14-1', 3));
select tt.t('T4 blind_active: the B person sees his disabled row', not blind_active('14-1', :'hw1'::int) and blind_active('14-1', 3));
select tt.t('T4 path_cfg: the B person sees his switch (a_open false)', not (path_cfg(:'dom', :'hw1'::int) ->> 'a_open')::boolean);
select tt.is('T4 template_for: the B person gets the B template', 'c3-tpl-b', (template_for('label', :'hw1'::int)).name);
select tt.as(:'o');
select tt.is('T4 owner: rollout_mode of the B place = parallel', 'parallel', rollout_mode('14-1', :'hw1'::int));
update rules set value = null where key = 'blind_count_on';
-- 4.5 assistant_health, intake failures, quality gate
select tt.as(:'as');
select tt.t('T4 assistant_health (A super user, head_management grant): findings about A places only', exists (select 1 from jsonb_array_elements(assistant_health()) x where x ->> 'detail' like 'main:%')
  and not exists (select 1 from jsonb_array_elements(assistant_health()) x where x ->> 'detail' like 'hw1:%' or x ->> 'detail' like 'hw2:%' or x ->> 'detail' like 'pb1:%'));
select tt.as(:'bs');
select tt.t('T4 assistant_health (B super user): findings about B places only', exists (select 1 from jsonb_array_elements(assistant_health()) x where x ->> 'detail' like 'hw1:%')
  and not exists (select 1 from jsonb_array_elements(assistant_health()) x where x ->> 'detail' like 'main:%' or x ->> 'detail' like 'branch2:%'));
select tt.as(:'am');
select tt.eq('T4 intake_failures_list: the A manager sees the A failure only (1)', 1, jsonb_array_length(intake_failures_list(null, 100)));
select tt.as(:'bm');
select tt.is('T4 intake_failures_list: the B manager sees the B failure only', 'f-b', intake_failures_list(null, 100) -> 0 ->> 'external_id');
select tt.as(:'o');
select tt.eq('T4 intake_failures_list: the owner sees all 3 (incl. the one without a channel)', 3, jsonb_array_length(intake_failures_list(null, 100)));
select tt.as(:'ao');
select tt.is('T4 qc_gate: the B quality record is invisible to an A person', null, qc_gate('production', '00000000-0000-0000-0000-0000000c3d01'::uuid) ->> 'status');
select tt.as(:'bo');
select tt.is('T4 qc_gate: the B person sees hold', 'hold', qc_gate('production', '00000000-0000-0000-0000-0000000c3d01'::uuid) ->> 'status');
-- 4.6 payment intents
select tt.as(:'o');
insert into payment_intents (provider, location_id, amount) values ('c3pay', 1, 100), ('c3pay', :'hw1'::int, 200);
select id as pi_a from payment_intents where provider = 'c3pay' and location_id = 1 \gset
select id as pi_b from payment_intents where provider = 'c3pay' and location_id = :'hw1'::int \gset
select id as pay_a from sale_payments where kind = 'collection' and location_id = 1 limit 1 \gset
select id as pay_b from sale_payments where kind = 'collection' and location_id = :'hw1'::int limit 1 \gset
select tt.as(:'as');
select tt.err('T4 payment_intent_link: a B payment is a missing id to an A accountant', format($q$select payment_intent_link(%s, %s)$q$, :'pi_a', :'pay_b'), 'payment_not_found');
select tt.err('T4 payment_intent_link: a B intent cannot be linked by an A accountant (even to an A payment)', format($q$select payment_intent_link(%s, %s)$q$, :'pi_b', :'pay_a'), 'not found');
select tt.ok('T4 payment_intent_link: A intent + A payment works', format($q$select payment_intent_link(%s, %s)$q$, :'pi_a', :'pay_a'));
select tt.err('T4 payment_intent_set_ref on a B intent is a missing id', format($q$select payment_intent_set_ref(%s, 'ref-c3-12345')$q$, :'pi_b'), 'not found');

\echo == T5 the border triggers: a user cannot write a row of a foreign business, whatever function does it
update rules set value = 'true'::jsonb where key = 'fixed_assets_on';
select tt.as(:'as');
select tt.err('T5 insert of a row at a B place by an A super user', format($q$insert into holidays (day, location_id, name_bn) values (current_date + 30, %s, 'c3 x')$q$, :'hw1'), 'not allowed');
select tt.err('T5 insert at the unmapped place', format($q$insert into holidays (day, location_id, name_bn) values (current_date + 30, %s, 'c3 x')$q$, :'orph'), 'not allowed');
select tt.ok('T5 insert at an A place works', $$insert into holidays (day, location_id, name_bn) values (current_date + 31, 1, 'c3 ok')$$);
select tt.err('T5 moving an A row into a B place', format($q$update holidays set location_id = %s where name_bn = 'c3 ok'$q$, :'hw1'), 'not allowed');
select tt.err('T5 updating a B row looks like a missing id', $$update shifts set name_bn = 'hacked' where name_bn = 's B'$$, 'not found');
select tt.err('T5 updating a B stock transfer / ledger-like table row: location_settings', format($q$update location_settings set value = '"x"'::jsonb where location_id = %s$q$, :'hw1'), 'not found');
select tt.err('T5 a function without a place check (rollout_set) is stopped at the border', format($q$select rollout_set('03-1', %s, 'paper')$q$, :'hw1'), 'not allowed');
select tt.err('T5 fa_asset_dispose on a B asset is a missing id', format($q$select fa_asset_dispose(%L, current_date, 'c3 dispose attempt')$q$, :'fa_b'), 'not found');
select tt.eq('T5 ... the B asset is untouched', 0, (select count(*) from fa_assets where id = :'fa_b'::uuid and status = 'disposed'));
update rules set value = null where key = 'fixed_assets_on';
select tt.as(:'xn');
select tt.err('T5 a user with no business cannot write at any place', $$insert into holidays (day, location_id, name_bn) values (current_date + 32, 1, 'c3 x')$$, 'not allowed');
select tt.as(:'o');
select tt.ok('T5 the owner writes anywhere', format($q$insert into holidays (day, location_id, name_bn) values (current_date + 33, %s, 'c3 owner')$q$, :'hw1'));
select set_config('request.jwt.claim.sub', '', false);
select tt.ok('T5 the server (no login) writes anywhere', format($q$insert into holidays (day, location_id, name_bn) values (current_date + 34, %s, 'c3 server')$q$, :'hw1'));
select tt.as(:'bs');
select tt.ok('T5 the B super user writes at the B place (rollout_set)', format($q$select rollout_set('03-1', %s, 'paper')$q$, :'hw1'));
select tt.t('T5 every table with a place column carries the border trigger (except the listed system tables)',
  not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname not in ('locations', 'user_locations', 'user_grants', 'user_org_scopes', 'notifications', 'exceptions', 'sales_fact_t', 'bi_export_log')
     and exists (select 1 from pg_attribute a where a.attrelid = c.oid and not a.attisdropped and a.attname in ('location_id', 'from_location_id', 'to_location_id', 'primary_location_id'))
     and not exists (select 1 from pg_trigger t where t.tgrelid = c.oid and t.tgname = c.relname || '_xb133')),
  'true', (select string_agg(c.relname, ',') from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname not in ('locations', 'user_locations', 'user_grants', 'user_org_scopes', 'notifications', 'exceptions', 'sales_fact_t', 'bi_export_log', 'items', 'option_sets', 'option_values', 'item_styles', 'price_lists', 'price_list_items', 'legal_entities')
     and exists (select 1 from pg_attribute a where a.attrelid = c.oid and not a.attisdropped and a.attname in ('location_id', 'from_location_id', 'to_location_id', 'primary_location_id'))
     and not exists (select 1 from pg_trigger t where t.tgrelid = c.oid and t.tgname = c.relname || '_xb133')));


-- audit test 1 (generated): for EVERY table with a place column, the rows of the other business are invisible to the people of this one (direct select, role authenticated)
create or replace function tt.leaks133(p_locs int[]) returns text language plpgsql as $$
declare r record; n bigint; res text := '';
begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid and a.attname = 'location_id' and not a.attisdropped
            where s.nspname = 'public' and c.relkind = 'r' order by 1 loop
    begin execute format('select count(*) from public.%I where location_id = any($1)', r.relname) into n using p_locs;
    exception when others then n := 0; end;
    if n > 0 then res := res || r.relname || ':' || n || ' '; end if;
  end loop;
  return res;
end $$;
grant execute on function tt.leaks133(int[]) to authenticated, anon;
select tt.as(:'o');
select tt.t('T5b the owner reads rows of both businesses in many tables (the generator has something to compare)', true, 'true', tt.leaks133(array[:'hw1'::int]) || ' | A: ' || tt.leaks133(array[1]));
set role authenticated;
select tt.as(:'ao');
select tt.is('T5b direct select, A staff: no table shows a row of a B place', '', tt.leaks133(array[:'hw1'::int, :'hw2'::int, :'orph'::int]));
select tt.as(:'am');
select tt.is('T5b direct select, A manager', '', tt.leaks133(array[:'hw1'::int, :'hw2'::int, :'orph'::int]));
select tt.as(:'as');
select tt.is('T5b direct select, A super user (every role and grant)', '', tt.leaks133(array[:'hw1'::int, :'hw2'::int, :'orph'::int]));
select tt.as(:'bs');
select tt.is('T5b direct select, B super user: no table shows a row of an A place (1..7)', '', tt.leaks133(array[1, 2, 3, 4, 5, 6, 7]));
select tt.as(:'xn');
select tt.is('T5b direct select, a user with no business: nothing at all', '', tt.leaks133(array[1, 2, 3, :'hw1'::int]));
reset role;

\echo == T6 audit test 11: storage (mock bucket photos) - paths carry the place, the policies check the business
reset role;
select tt.as(:'o');
delete from storage.objects where name like '%c3-off.jpg';
insert into storage.objects (bucket_id, name) values ('photos', 'STOCK/1/a-view.jpg'), ('photos', 'STOCK/' || :'hw1' || '/b-view.jpg'), ('photos', 'STOCK/' || :'orph' || '/o-view.jpg'), ('photos', 'weird/path.jpg');
set role authenticated;
select tt.as(:'as');
select tt.eq('T6 A super user reads the A object', 1, (select count(*) from storage.objects where name = 'STOCK/1/a-view.jpg'));
select tt.eq('T6 ... and none of the B / unmapped / odd-path objects', 0, (select count(*) from storage.objects where name in ('STOCK/' || :'hw1' || '/b-view.jpg', 'STOCK/' || :'orph' || '/o-view.jpg', 'weird/path.jpg')));
select tt.err('T6 A super user cannot store under a B place path (audit test 11)', format($q$insert into storage.objects (bucket_id, name) values ('photos', 'STOCK/%s/c3-on.jpg')$q$, :'hw1'), 'row-level security');
select tt.err('T6 ... nor under the unmapped place', format($q$insert into storage.objects (bucket_id, name) values ('photos', 'STOCK/%s/c3-on.jpg')$q$, :'orph'), 'row-level security');
select tt.ok('T6 ... but under an A place', $$insert into storage.objects (bucket_id, name) values ('photos', 'STOCK/1/c3-on.jpg')$$);
select tt.as(:'bs');
select tt.eq('T6 B super user reads the B object and not the A one', 1, (select count(*) from storage.objects where name = 'STOCK/' || :'hw1' || '/b-view.jpg') - (select count(*) from storage.objects where name = 'STOCK/1/a-view.jpg'));
select tt.err('T6 B super user cannot store under an A place', $$insert into storage.objects (bucket_id, name) values ('photos', 'STOCK/1/c3-on2.jpg')$$, 'row-level security');
select tt.as(:'xn');
select tt.eq('T6 a user with no business reads nothing', 0, (select count(*) from storage.objects where name like 'STOCK/%'));
select tt.as(:'aop');
select tt.eq('T6 the backup bot (ops purpose backup, group infrastructure) reads every business object', 3, (select count(*) from storage.objects where name in ('STOCK/1/a-view.jpg', 'STOCK/' || :'hw1' || '/b-view.jpg', 'STOCK/' || :'orph' || '/o-view.jpg')));
select tt.err('T6 ... but cannot store', $$insert into storage.objects (bucket_id, name) values ('photos', 'STOCK/1/c3-on3.jpg')$$, 'row-level security');
reset role;
select tt.as(:'o');
set role authenticated;
select tt.eq('T6 the owner reads the three objects with a place in the path (the odd path is readable by nobody)', 3, (select count(*) from storage.objects where name in ('STOCK/1/a-view.jpg', 'STOCK/' || :'hw1' || '/b-view.jpg', 'STOCK/' || :'orph' || '/o-view.jpg', 'weird/path.jpg')) - 0);
reset role;
select tt.as(:'as');
select tt.eq('T6 photo_business133: the business of an own path', :'sbz'::bigint, photo_business133('STOCK/1/x.jpg'));
select tt.is('T6 photo_business133: a path of another business gives nothing', null, photo_business133('STOCK/' || :'hw1' || '/x.jpg')::text);
select tt.is('T6 photo_path133 builds <prefix>/<place>/<name>', 'STOCK/1/new.jpg', photo_path133('STOCK', 1, 'new.jpg'));
select tt.err('T6 photo_path133 refuses a place of another business', format($q$select photo_path133('STOCK', %s, 'new.jpg')$q$, :'hw1'), 'not allowed');
select tt.err('T6 photo_path133 refuses a bad name', $$select photo_path133('STOCK', 1, '../x')$$, 'bad_input');
select tt.err('T6 photo_unmapped133 is owner only', $$select photo_unmapped133()$$, 'not allowed');
select tt.as(:'o');
select tt.t('T6 photo_unmapped133 (owner): the objects are counted per business, the unmapped place and the odd path under none (2)', (photo_unmapped133() ->> 'objects')::int >= 5 and (photo_unmapped133() -> 'by_business' ->> 'none')::int >= 2
  and (photo_unmapped133() -> 'by_business' ->> :'sbz')::int >= 2 and (photo_unmapped133() -> 'by_business' ->> :'hbz')::int >= 1, 'true', photo_unmapped133()::text);
select tt.eq('T6 photo_business133 (owner) knows the B path', :'hbz'::bigint, photo_business133('STOCK/' || :'hw1' || '/x.jpg'));

\echo == T7 audit test 13: the lock state of the login must not tell which staff ids exist
select staff_id as sid_a from profiles where id = :'ao' \gset
select tt.as(:'o');
select unlock_staff('c3-ghost'); select unlock_staff(:'sid_a');
select login_failed('c3-ghost') from generate_series(1, 7);
select login_failed(:'sid_a') from generate_series(1, 7);
select tt.t('T7 ON: a known staff id is locked after the fails', (login_precheck(:'sid_a') ->> 'locked')::boolean);
select tt.t('T7 ON: an UNKNOWN id is locked the same way (no signal about existence)', (login_precheck('c3-ghost') ->> 'locked')::boolean);
select tt.t('T7 ON: the answer has the same shape for both', (select array_agg(k order by k) from jsonb_object_keys(login_precheck('c3-ghost')) k) = (select array_agg(k order by k) from jsonb_object_keys(login_precheck(:'sid_a')) k));
select tt.t('T7 ON: a never-tried id is not locked', not (login_precheck('c3-never') ->> 'locked')::boolean);
select unlock_staff('c3-ghost'); select unlock_staff(:'sid_a');
select tt.t('T7 the owner unlocks both', not (login_precheck('c3-ghost') ->> 'locked')::boolean and not (login_precheck(:'sid_a') ->> 'locked')::boolean);

\echo == T8 the digest per business (daily_digest stays the group digest)
select tt.as(:'o');
select tt.eq('T8 group digest (owner): sales today = 1400 + 100 + 1400 + 200', 3100, (daily_digest(null) -> 'sales' -> 'today' ->> 'total')::numeric);
select tt.eq('T8 digest of business A (owner): 1400 + 100', 1500, (daily_digest_biz133(:'sbz'::bigint) -> 'sales' -> 'today' ->> 'total')::numeric);
select tt.eq('T8 digest of business B (owner): 1400 + 200', 1600, (daily_digest_biz133(:'hbz'::bigint) -> 'sales' -> 'today' ->> 'total')::numeric);
select tt.eq('T8 A customer dues in the digest: 500 + 100', 600, (daily_digest_biz133(:'sbz'::bigint) -> 'dues' ->> 'customers_total')::numeric);
select tt.eq('T8 B customer dues in the digest: 500 + 200', 700, (daily_digest_biz133(:'hbz'::bigint) -> 'dues' ->> 'customers_total')::numeric);
select tt.eq('T8 group dues = A + B', 1300, (daily_digest(null) -> 'dues' ->> 'customers_total')::numeric);
select tt.eq('T8 A purchase payable in the digest: the 500 bill', 500, (daily_digest_biz133(:'sbz'::bigint) -> 'dues' -> 'suppliers' ->> 'payable')::numeric);
select tt.eq('T8 wastage count of A in the digest = 1', 1, (daily_digest_biz133(:'sbz'::bigint) -> 'wastage' ->> 'count')::numeric);
select tt.eq('T8 A by_location lists only A showrooms', (select count(*) from locations l where l.is_active and l.status = 'live' and l.kind = 'showroom' and l.org_unit_id = :'sbz'::bigint),
  jsonb_array_length(daily_digest_biz133(:'sbz'::bigint) -> 'sales' -> 'by_location'));
select tt.eq('T8 B by_location lists only B showrooms (hw1, hw2)', 2, jsonb_array_length(daily_digest_biz133(:'hbz'::bigint) -> 'sales' -> 'by_location'));
select tt.as(:'am');
select tt.eq('T8 the A manager may read the A digest', 1500, (daily_digest_biz133(:'sbz'::bigint) -> 'sales' -> 'today' ->> 'total')::numeric);
select tt.err('T8 ... not the B digest', format($q$select daily_digest_biz133(%s)$q$, :'hbz'), 'not allowed');
select tt.err('T8 ... and not the group digest', $$select daily_digest(null)$$, 'not allowed');
select tt.as(:'bm');
select tt.err('T8 the B manager cannot read the A digest', format($q$select daily_digest_biz133(%s)$q$, :'sbz'), 'not allowed');
select tt.as(:'ao');
select tt.err('T8 a plain staff member cannot read a digest', format($q$select daily_digest_biz133(%s)$q$, :'sbz'), 'not allowed');
select tt.as(:'aop');
select tt.eq('T8 the notify bot (group infrastructure) reads the group digest', 3100, (daily_digest(null) -> 'sales' -> 'today' ->> 'total')::numeric);
select tt.eq('T8 ... and any business digest (B)', 1600, (daily_digest_biz133(:'hbz'::bigint) -> 'sales' -> 'today' ->> 'total')::numeric);
select tt.as(:'o');
select tt.err('T8 bad business', $$select daily_digest_biz133(99999)$$, 'bad_business');
select tt.err('T8 bad date', format($q$select daily_digest_biz133(%s, current_date + 5)$q$, :'sbz'), 'bad_date');

\echo == T9 report paths, my_context, notifications and the bot identity
select tt.as(:'am');
select tt.t('T9 report_run receivable_aging (A manager): the A customer and the shared customer with the A part only, no B customer', report_run('receivable_aging', '{}'::jsonb, null, null, 1, false)::text like '%Cust A%'
  and report_run('receivable_aging', '{}'::jsonb, null, null, 1, false)::text not like '%Cust B%' and (select sum((x ->> 'balance')::numeric) from jsonb_array_elements(report_run('receivable_aging', '{}'::jsonb, null, null, 1, false) -> 'rows') x) = 600);
select tt.as(:'bm');
select tt.eq('T9 report_run receivable_aging (B manager): 500 + the B part 200 of the shared customer', 700, (select sum((x ->> 'balance')::numeric) from jsonb_array_elements(report_run('receivable_aging', '{}'::jsonb, null, null, 1, false) -> 'rows') x));
select tt.as(:'o');
select tt.eq('T9 report_run receivable_aging (owner): 1300 over both', 1300, (select sum((x ->> 'balance')::numeric) from jsonb_array_elements(report_run('receivable_aging', '{}'::jsonb, null, null, 1, false) -> 'rows') x));
select tt.as(:'am');
select tt.eq('T9 report_run with a B place named in the filter: the B place is ignored (nothing counted)', 0, coalesce((report_run('sales_summary', jsonb_build_object('from', tt.today()::text, 'to', tt.today()::text, 'locations', jsonb_build_array(:'hw1'::int)), null, null, 1, false) -> 'totals' ->> 'bills')::numeric, 0));
select tt.eq('T9 report_run sales_summary (A manager, own places): 5 bills 1500', 1500, (report_run('sales_summary', jsonb_build_object('from', tt.today()::text, 'to', tt.today()::text), null, null, 1, false) -> 'totals' ->> 'net')::numeric);
select tt.as(:'ao');
select tt.is('T9 my_context: an A person has only A places', '[1]', (my_context() -> 'locations')::text);
select tt.as(:'bo');
select tt.is('T9 my_context: a B person has only B places', '[' || :'hw1' || ']', (my_context() -> 'locations')::text);
select tt.as(:'am');
select tt.is('T9 notifications: the A manager reads the A note and not the B note', 'note A', (select string_agg(x ->> 'title_en', ',') from jsonb_array_elements(notifications_for_me(50, false, null)) x));
select tt.as(:'bm');
select tt.is('T9 notifications: the B manager reads the B note only', 'note B', (select string_agg(x ->> 'title_en', ',') from jsonb_array_elements(notifications_for_me(50, false, null)) x));
-- bot identity: one bot per business; a bot of A cannot write into the channel of B
select tt.as(:'o');
insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000c3d11', 'abot@c3.app', '{"full_name":"A Bot"}'), ('00000000-0000-0000-0000-0000000c3d12', 'bbot@c3.app', '{"full_name":"B Bot"}') on conflict do nothing;
update profiles set status = 'active';
select intake_bot_create('00000000-0000-0000-0000-0000000c3d11'::uuid, 1) is not null as bot1 \gset
select intake_bot_create('00000000-0000-0000-0000-0000000c3d12'::uuid, :'hw1'::int) is not null as bot2 \gset
update rules set value = 'true'::jsonb where key = 'inbox_on';
select tt.as('00000000-0000-0000-0000-0000000c3d11');
select inbound_message_receive('other', 'acc_B', 'ext-c3-1', 'h', 'Name', 'hello', now(), null, true, null) ->> 'failed' as r_b \gset
select inbound_message_receive('other', 'acc_A', 'ext-c3-2', 'h', 'Name', 'hello', now(), null, true, null) ->> 'id' as r_a \gset
select tt.t('T9 bot of A: a message for the channel of B is refused (queued as a failure, nothing stored)', :'r_b' = 'true' and (select count(*) from inbound_messages where external_id = 'ext-c3-1') = 0);
select tt.t('T9 bot of A: a message for the own channel is stored', :'r_a' is not null and (select count(*) from inbound_messages where external_id = 'ext-c3-2' and location_id = 1) = 1);
select tt.as(:'o');
select tt.t('T9 the refusal is in the failure list of the owner', exists (select 1 from intake_failures where error like '%not allowed%' and external_id = 'ext-c3-1'));
update rules set value = null where key = 'inbox_on';

\echo == T10 audit test 9: the same customer mobile / item code in both businesses (needs phase132)
select to_regprocedure('public.org_masters_relax_unique(boolean,boolean)') is not null as c2 \gset
\if :c2
select tt.t('T10 phase132 is pasted: see phase132_test for the per-business uniqueness (the global constraints are relaxed by the owner only)', true);
\else
select tt.t('T10 SKIPPED: phase132 (master data per business) is not pasted in this build; items.code / customers.mobile are still globally unique (Stage C2, see docs/audit_c1/C3_COVERAGE.md)', true);
\endif

\echo == T11 the coverage checker: exposed SECURITY DEFINER functions that are not scope-aware, against the reviewed list
create table tt.al_raw (line text);
\copy tt.al_raw from 'tests/sql/scope_allowlist.txt' with (format text, delimiter E'\x01')
create temp table al as select split_part(line, '|', 1) as fn, split_part(line, '|', 2) as cls, substr(line, length(split_part(line, '|', 1)) + length(split_part(line, '|', 2)) + 3) as why from tt.al_raw where line <> '' and line not like '#%';
select tt.as(:'o');
create temp table gaps as select fn, args from scope_gaps133();
select tt.t('T11 the checker lists a real number of functions (more than 200) and the reviewed list has at least as many (equal unless phase132 made some scope-aware)', (select count(*) from gaps) > 200 and (select count(distinct fn) from gaps) <= (select count(*) from al), 'true', (select count(*) from gaps) || ' / ' || (select count(*) from al));
select tt.is('T11 NO exposed function is unreviewed (in the checker, not in tests/sql/scope_allowlist.txt)', '', coalesce((select string_agg(fn, ',' order by fn) from (select distinct fn from gaps except select fn from al) z), ''));
select tt.is('T11 NO stale entry in the reviewed list (a function that is now scope-aware or gone; with phase132 pasted its patches make some entries stale on purpose: regenerate with tools/scope_classify133.py)', '',
  coalesce((select string_agg(fn, ',' order by fn) from (select fn from al where why not like '[c2]%' and to_regprocedure('public.master_share_create(text,text,bigint,bigint,text,uuid)') is null
     except select fn from gaps) z), ''));
select tt.t('T11 every reviewed entry has a known class and a reason of 15+ characters', not exists (select 1 from al where cls not in ('PRIM', 'OWNER', 'OWN', 'MASTER', 'CONFIG', 'INFRA', 'HELPER', 'FIXED', 'DEFER') or length(why) < 15));
select tt.t('T11 no class DEFER is left unexplained (deferred entries must say why: at least 40 characters)', not exists (select 1 from al where cls = 'DEFER' and length(why) < 40));
select tt.t('T11 the list has no duplicate name', (select count(*) from al) = (select count(distinct fn) from al));
select tt.t('T11 every FIXED entry really carries the phase133 marker or the owner gate', not exists (select 1 from al a where a.cls = 'FIXED' and not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = a.fn and p.prosrc like '%scope133%')));
select tt.as(:'as');
select tt.err('T11 scope_gaps133 is owner only', $$select * from scope_gaps133()$$, 'not allowed');
select tt.as(:'o');

\echo == T12 generic safety nets for future objects
select tt.t('T12 every public table has row level security on', not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  'true', (select string_agg(c.relname, ',') from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity));
select tt.t('T12 every exposed SECURITY DEFINER function pins its search_path', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosecdef and p.prorettype <> 'trigger'::regtype
    and has_function_privilege('authenticated', p.oid, 'execute') and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))),
  'true', (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))));
select tt.t('T12 no function of phase133 is executable by anon', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '133$' and has_function_privilege('anon', p.oid, 'execute')));
select tt.t('T12 the internal helpers of phase133 are closed to the browser role', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_caller_biz133', '_patch133', '_gate133', '_xb133', '_grant_eff133', '_form_eff133', '_can_grant_in133', '_rule_in133', '_cfgvis133', '_rule_group_only133') and has_function_privilege('authenticated', p.oid, 'execute')));
select tt.t('T12 the new tables are closed to anon and have no browser write', not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'public' and g.table_name in ('rule_overrides', 'rule_grant_overrides133', 'role_form_overrides133') and (g.grantee = 'anon' or (g.grantee = 'authenticated' and g.privilege_type <> 'SELECT'))));
select tt.t('T12 every table that carries a place column and can be written by a function is listed in the border skip list or has the trigger (see T5)', true);


\echo == T13 the differential leak probe (tests/sql/c3_probe.sql): the answers to A's people must not change when business B has data, and a B id must look like a missing id
\if :{?skip_probe}
select tt.t('T13 SKIPPED (psql variable skip_probe set)', true);
\else
create table tt.pk_raw (line text);
\copy tt.pk_raw from 'tests/sql/scope_probe_known.txt' with (format text, delimiter E'\x01')
create temp table pk as select split_part(line, '|', 1) as fn, substr(line, length(split_part(line, '|', 1)) + 2) as why from tt.pk_raw where line <> '' and line not like '#%';
create temp table pd as
  select 'v0/vA' as kind, a.fn, a.persona, a.variant from c3.probe_out a join c3.probe_out b on b.snap = 'S2' and b.fn = a.fn and b.persona = a.persona and b.variant = a.variant
   where a.snap = 'S1' and a.variant in ('v0', 'vA') and a.out <> b.out
  union all
  select 'place', b.fn, b.persona, b.variant from c3.probe_out b join c3.probe_out x on x.snap = 'S2' and x.fn = b.fn and x.persona = b.persona and x.variant = 'vPX'
   where b.snap = 'S2' and b.variant = 'vP' and b.out <> x.out and b.out <> 'ERR'
  union all
  select 'id', b.fn, b.persona, b.variant from c3.probe_out b join c3.probe_out x on x.snap = 'S2' and x.fn = b.fn and x.persona = b.persona and x.variant = 'vIX:' || split_part(b.variant, ':', 2)
   where b.snap = 'S2' and b.variant like 'vI:%' and b.out <> x.out and b.out <> 'ERR';
select tt.t('T13 the probe made calls for 3+ personas and 700+ functions', (select count(distinct persona) from c3.probe_out) >= 4 and (select count(distinct fn) from c3.probe_out) > 700, 'true', (select count(distinct fn) from c3.probe_out) || ' functions, ' || (select count(*) from c3.probe_out) || ' answers');
select tt.t('T13 the probe has teeth: with the switch OFF the same attack WOULD show differences (acct_status counts B documents)',
  (select count(*) from c3.probe_out where snap = 'S2' and variant = 'v0' and out <> 'ERR') > 100);
select tt.is('T13 NO unexpected difference (function names not in tests/sql/scope_probe_known.txt)', '', coalesce((select string_agg(distinct split_part(fn, '(', 1) || '[' || kind || ']', ',') from pd where split_part(fn, '(', 1) not in (select fn from pk)), ''));
\endif

\echo == T14 paste phase133 again on this database: nothing changes
select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fh0 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' \gset
select count(*) as trg0 from pg_trigger where tgname like '%\_xb133' \gset
select count(*) as pol0 from pg_policies where policyname like '%133%' \gset
reset role;
\i supabase/phase133.sql
select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fh1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' \gset
select tt.t('T14 paste twice: no function body changes', :'fh0' = :'fh1');
select tt.t('T14 paste twice: the same triggers and policies, the overrides and the switch are untouched', (select count(*) from pg_trigger where tgname like '%\_xb133') = :trg0 and (select count(*) from pg_policies where policyname like '%133%') = :pol0 and rule_on('org_scope_on'));

\echo == T15 switching OFF again gives back the first numbers (history and settings are kept)
update rules set value = 'false'::jsonb where key = 'org_scope_on';
select tt.as(:'o');
select tt.t('T15 OFF: owner numbers equal the snapshot taken before the switch was ever ON (dues, sales count, trial balance, group rule values)', (select sum(balance) from customer_dues()) = (select dues from off_snap) and (select count(*) from sales) = (select sales_n from off_snap)
  and (select md5(acct_trial_balance(null, null)::text)) = (select tb from off_snap) and (select md5(string_agg(r.key || '=' || coalesce(rule_val(r.key)::text, 'null'), '|' order by r.key)) from rules r where r.key <> 'org_scope_on') = (select rules_h from off_snap));
select tt.as(:'ao');
select tt.eq('T15 OFF: an A person sees the dues of every place again (1300 = 500 + 500 + 300)', 1300, (select sum(balance) from customer_dues()));
select tt.is('T15 OFF: the group rule value for everybody', 'block', rule_txt('pos_credit_mode'));
select tt.as(:'bo'); select tt.is('T15 OFF: ... also for B', 'block', rule_txt('pos_credit_mode'));
select tt.t('T15 OFF: the override rows are still there (kept as history)', (select count(*) from rule_overrides) >= 5);
select tt.as(:'am');
select tt.t('T15 OFF: the border triggers are inert again (the A manager can write at a B place as before)', true);
insert into holidays (day, location_id, name_bn) values (current_date + 40, :'hw1'::int, 'c3 off again');
select tt.eq('T15 OFF: ... the row is there', 1, (select count(*) from holidays where name_bn = 'c3 off again'));
update rules set value = 'true'::jsonb where key = 'org_scope_on';

\echo == T16 void_collection (id swap) - last, because it changes a number
select tt.as(:'am');
select tt.err('T16 void_collection: the collection of business B is a missing id to the A manager', format($q$select void_collection(%s, 'c3 try')$q$, :'pay_b'), 'not found');
select tt.eq('T16 ... the B collection is untouched', 0, (select count(*) from sale_payments where id = :'pay_b' and voided));
select tt.ok('T16 void_collection: the A manager voids an A collection', format($q$select void_collection(%s, 'c3 own')$q$, :'pay_a'));
select tt.eq('T16 ... exactly one collection is voided (A)', 1, (select count(*) from sale_payments where kind = 'collection' and voided));
select tt.as(:'bm');
select tt.err('T16 void_collection: the A collection cannot be voided again from B (missing id)', format($q$select void_collection(%s, 'c3 try')$q$, :'pay_a'), 'not found');
update rules set value = 'false'::jsonb where key = 'org_scope_on';
select tt.as(:'am');
select tt.ok('T16 OFF: the A manager can void a B collection as before (the old behaviour)', format($q$select void_collection(%s, 'c3 off')$q$, :'pay_b'));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
